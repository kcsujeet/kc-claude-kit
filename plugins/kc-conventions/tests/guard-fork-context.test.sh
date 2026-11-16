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

# check <label> <deny|allow> <tool> <tool_input json> <transcript> [<PATH override>]
check() {
  local label=$1 want=$2 tool=$3 args=$4 transcript=$5 path_override=${6:-}
  local output status errors got=allow
  cases=$((cases + 1))
  if [ -n "$path_override" ]; then
    output=$(build_payload "$tool" "$args" "$transcript" | PATH="$path_override" "$(command -v bash)" "$hook" 2>"$work_dir/stderr")
  else
    output=$(build_payload "$tool" "$args" "$transcript" | bash "$hook" 2>"$work_dir/stderr")
  fi
  status=$?
  errors=$(cat "$work_dir/stderr")
  if [[ "$output" == *'"permissionDecision":"deny"'* ]] && printf '%s' "$output" | jq -e . >/dev/null 2>&1; then got=deny; fi
  [ -n "$output" ] && [ "$got" = allow ] && got="unexpected output: $output"
  if [ "$got" = "$want" ] && [ "$status" -eq 0 ] && [ -z "$errors" ]; then
    echo "ok   $want  $label"
  else
    echo "FAIL $label: want $want, got $got (status $status, stderr: $errors)"
    failures=$((failures + 1))
  fi
}

big=$(write_transcript big 250000)
small=$(write_transcript small 40000)
edge=$(write_transcript edge 100000)
big_sidechain_only=$(write_transcript sidechain 40000 400000)
no_usage="$work_dir/no-usage.jsonl"
echo '{"type":"user","message":{"content":"hi"}}' > "$no_usage"

start=mcp__ccd_session__start_session
handoff=mcp__ccd_session__hand_off_to_session

check "start_session fork, large context" deny "$start" '{"context":"fork","title":"x"}' "$big"
check "start_session fork, small context" allow "$start" '{"context":"fork","title":"x"}' "$small"
check "start_session fork at exactly the limit" allow "$start" '{"context":"fork"}' "$edge"
check "start_session fresh, large context" allow "$start" '{"context":"fresh","title":"x"}' "$big"
check "start_session with no context field, large context" allow "$start" '{"title":"x"}' "$big"
check "hand_off_to_session, large context" deny "$handoff" '{"title":"x","remaining_plan":"y"}' "$big"
check "hand_off_to_session, small context" allow "$handoff" '{"title":"x"}' "$small"
check "Agent fork, large context" deny Agent '{"subagent_type":"fork","prompt":"p"}' "$big"
check "Agent named type, large context" allow Agent '{"subagent_type":"Explore","prompt":"p"}' "$big"
check "Agent with no type, large context" allow Agent '{"prompt":"p"}' "$big"
check "other tool, large context" allow Bash '{"command":"ls"}' "$big"
check "sidechain usage is ignored" allow "$start" '{"context":"fork"}' "$big_sidechain_only"
check "missing transcript allows" allow "$start" '{"context":"fork"}' "$work_dir/missing.jsonl"
check "transcript with no usage allows" allow "$start" '{"context":"fork"}' "$no_usage"

deny_output=$(build_payload "$start" '{"context":"fork"}' "$big" | bash "$hook")
cases=$((cases + 1))
if [[ "$deny_output" == *"250k tokens"* ]] && [[ "$deny_output" == *'context \"fresh\"'* ]]; then
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
build_payload "$start" '{"context":"fork"}' "$big" > "$payload_file"
cases=$((cases + 1))
no_jq_output=$(PATH="$bin_without_jq" bash "$hook" < "$payload_file" 2>&1)
no_jq_status=$?
if [ -z "$no_jq_output" ] && [ "$no_jq_status" -eq 0 ]; then
  echo "ok   allow  no jq"
else
  echo "FAIL no jq: status $no_jq_status, output $no_jq_output"
  failures=$((failures + 1))
fi

echo "$((cases - failures))/$cases passed"
[ "$failures" -eq 0 ]
