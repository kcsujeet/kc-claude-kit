#!/usr/bin/env bash
# Tests hooks/guard-fork-context.sh: a fork (start_session with context "fork", hand_off_to_session,
# Agent with subagent_type "fork") is denied above 100000 tokens of context and allowed at or below
# it; fresh starts and other tools are allowed at any size; sidechain usage lines are ignored; a
# missing transcript, a transcript without usage, or no jq allows. Every case also fails when the
# hook exits non-zero or writes to stderr.
set -u

tests_dir=$(cd "$(dirname "$0")" && pwd)
hook="$(dirname "$tests_dir")/hooks/guard-fork-context.sh"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

failures=0
cases=0

# write_transcript <name> <main-chain context tokens> [<sidechain context tokens>]
write_transcript() {
  local path="$work_dir/$1.jsonl"
  {
    echo '{"type":"user","message":{"content":"hi"}}'
    printf '{"type":"assistant","isSidechain":false,"message":{"usage":{"input_tokens":1,"cache_read_input_tokens":%s,"cache_creation_input_tokens":0,"output_tokens":5}}}\n' "$(($2 - 1))"
    [ -n "${3:-}" ] && printf '{"type":"assistant","isSidechain":true,"message":{"usage":{"input_tokens":1,"cache_read_input_tokens":%s,"cache_creation_input_tokens":0}}}\n' "$(($3 - 1))"
  } > "$path"
  echo "$path"
}

build_payload() { jq -n --arg tool "$1" --argjson args "$2" --arg transcript "$3" '{tool_name: $tool, tool_input: $args, transcript_path: $transcript}'; }

# check_fork_guard_decision <label> <deny|allow> <tool> <tool_input json> <transcript>
check_fork_guard_decision() {
  local label=$1 want=$2 tool=$3 args=$4 transcript=$5
  local output status errors got=allow is_deny_json=0 exited_cleanly=0
  cases=$((cases + 1))
  output=$(build_payload "$tool" "$args" "$transcript" | bash "$hook" 2>"$work_dir/stderr")
  status=$?
  errors=$(cat "$work_dir/stderr")
  if [[ "$output" == *'"permissionDecision":"deny"'* ]]; then
    printf '%s' "$output" | jq -e . >/dev/null 2>&1 && is_deny_json=1
  fi
  if [ "$is_deny_json" = 1 ]; then
    got=deny
  elif [ -n "$output" ]; then
    got="unexpected output: $output"
  fi
  if [ "$status" -eq 0 ] && [ -z "$errors" ]; then exited_cleanly=1; fi
  if [ "$got" = "$want" ] && [ "$exited_cleanly" = 1 ]; then
    echo "ok   $want  $label"
  else
    echo "FAIL $label: want $want, got $got (status $status, stderr: $errors)"
    failures=$((failures + 1))
  fi
}

transcript_over_limit=$(write_transcript over-limit 250000)
transcript_under_limit=$(write_transcript under-limit 40000)
transcript_at_limit=$(write_transcript at-limit 100000)
sidechain_only_over_limit=$(write_transcript sidechain 40000 400000)
no_usage="$work_dir/no-usage.jsonl"
echo '{"type":"user","message":{"content":"hi"}}' > "$no_usage"

start_session_tool=mcp__ccd_session__start_session
hand_off_to_session_tool=mcp__ccd_session__hand_off_to_session

check_fork_guard_decision "start_session fork, large context" deny "$start_session_tool" '{"context":"fork","title":"x"}' "$transcript_over_limit"
check_fork_guard_decision "start_session fork, small context" allow "$start_session_tool" '{"context":"fork","title":"x"}' "$transcript_under_limit"
check_fork_guard_decision "start_session fork at exactly the limit" allow "$start_session_tool" '{"context":"fork"}' "$transcript_at_limit"
check_fork_guard_decision "start_session fresh, large context" allow "$start_session_tool" '{"context":"fresh","title":"x"}' "$transcript_over_limit"
check_fork_guard_decision "start_session with no context field, large context" allow "$start_session_tool" '{"title":"x"}' "$transcript_over_limit"
check_fork_guard_decision "hand_off_to_session, large context" deny "$hand_off_to_session_tool" '{"title":"x","remaining_plan":"y"}' "$transcript_over_limit"
check_fork_guard_decision "hand_off_to_session, small context" allow "$hand_off_to_session_tool" '{"title":"x"}' "$transcript_under_limit"
check_fork_guard_decision "Agent fork, large context" deny Agent '{"subagent_type":"fork","prompt":"p"}' "$transcript_over_limit"
check_fork_guard_decision "Agent named type, large context" allow Agent '{"subagent_type":"Explore","prompt":"p"}' "$transcript_over_limit"
check_fork_guard_decision "Agent with no type, large context" allow Agent '{"prompt":"p"}' "$transcript_over_limit"
check_fork_guard_decision "other tool, large context" allow Bash '{"command":"ls"}' "$transcript_over_limit"
check_fork_guard_decision "sidechain usage is ignored" allow "$start_session_tool" '{"context":"fork"}' "$sidechain_only_over_limit"
check_fork_guard_decision "missing transcript allows" allow "$start_session_tool" '{"context":"fork"}' "$work_dir/missing.jsonl"
check_fork_guard_decision "transcript with no usage allows" allow "$start_session_tool" '{"context":"fork"}' "$no_usage"

deny_output=$(build_payload "$start_session_tool" '{"context":"fork"}' "$transcript_over_limit" | bash "$hook")
cases=$((cases + 1))
message_names_size=0 message_names_fresh_start=0
[[ "$deny_output" == *"250k tokens"* ]] && message_names_size=1
[[ "$deny_output" == *'context \"fresh\"'* ]] && message_names_fresh_start=1
if [ "$message_names_size" = 1 ] && [ "$message_names_fresh_start" = 1 ]; then
  echo "ok   deny message names the size and the fresh start"
else
  echo "FAIL deny message: $deny_output"
  failures=$((failures + 1))
fi

bin_without_jq="$work_dir/bin"
mkdir -p "$bin_without_jq"
ln -s "$(command -v bash)" "$bin_without_jq/bash"
ln -s "$(command -v cat)" "$bin_without_jq/cat"
payload_file="$work_dir/payload.json"
build_payload "$start_session_tool" '{"context":"fork"}' "$transcript_over_limit" > "$payload_file"
cases=$((cases + 1))
no_jq_output=$(PATH="$bin_without_jq" bash "$hook" < "$payload_file" 2>&1)
no_jq_status=$?
no_jq_allowed=0
if [ -z "$no_jq_output" ] && [ "$no_jq_status" -eq 0 ]; then no_jq_allowed=1; fi
if [ "$no_jq_allowed" = 1 ]; then
  echo "ok   allow  no jq"
else
  echo "FAIL no jq: status $no_jq_status, output $no_jq_output"
  failures=$((failures + 1))
fi

echo "$((cases - failures))/$cases passed"
[ "$failures" -eq 0 ]
