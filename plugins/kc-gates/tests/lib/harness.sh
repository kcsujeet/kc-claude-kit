# shellcheck shell=bash
# Shared assertions for the kc-gates script tests. Sourced, never executed.
# The sourcing runner sets tests_dir before sourcing.

# run_git_in <repo> <git args>...: runs git in the repo with a throwaway identity.
run_git_in() { local repo=$1; shift; git -C "$repo" -c user.name=t -c user.email=t@example.test "$@"; }

passes=0
failures=0
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

record() {
  local label=$1 verdict=$2 detail=${3:-}
  if [ "$verdict" = ok ]; then
    echo "ok   $label"
    passes=$((passes + 1))
  else
    echo "FAIL $label"
    if [ -n "$detail" ]; then printf '%s\n' "$detail" | sed 's/^/     /'; fi
    failures=$((failures + 1))
  fi
}

expect_eq() {
  local label=$1 expected=$2 actual=$3
  if [ "$expected" = "$actual" ]; then
    record "$label" ok
  else
    record "$label" fail "expected: $expected
actual:   $actual"
  fi
}

# Passes when <file> matches <expected-file> exactly; shows the diff otherwise.
expect_file() {
  local label=$1 expected_file=$2 actual_file=$3
  if diff -u "$expected_file" "$actual_file" > "$work_dir/expect-file.diff"; then
    record "$label" ok
  else
    record "$label" fail "$(cat "$work_dir/expect-file.diff")"
  fi
}

# Passes when <needle> is absent from <haystack>.
expect_not_contains() {
  local label=$1 needle=$2 haystack=$3
  case "$haystack" in
    *"$needle"*) record "$label" fail "unexpected: $needle
in:         $haystack" ;;
    *) record "$label" ok ;;
  esac
}

expect_contains() {
  local label=$1 needle=$2 haystack=$3
  case "$haystack" in
    *"$needle"*) record "$label" ok ;;
    *) record "$label" fail "missing: $needle
in:      $haystack" ;;
  esac
}

# Puts the stub gh first on PATH, answering from <fixture-dir>/routes.tsv, and
# logs every call to $KC_GH_LOG.
use_gh_fixtures() {
  export KC_GH_ROUTES="$1/routes.tsv"
  export KC_GH_LOG="$work_dir/gh-calls.log"
  : > "$KC_GH_LOG"
  case ":$PATH:" in
    *":${tests_dir:?}/lib:"*) ;;
    *) export PATH="$tests_dir/lib:$PATH" ;;
  esac
}

# jq backs the stub's --jq; the scripts under test need it only through gh.
require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "FAIL jq is required to run these tests (the gh stub emulates --jq with it)"
    exit 1
  fi
}

# Wraps a shell command (no double quotes or backslashes in it) and a working directory in the
# PreToolUse stdin payload.
build_hook_payload() {
  printf '{"session_id":"s","cwd":"%s","transcript_path":"%s","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"%s","description":"test"},"tool_use_id":"t"}' "$2" "${3:-}" "$1"
}

# expect_hook_verdict <hook script> <deny|allow> <label> <command> <cwd> [<transcript>]: runs the hook twice, with
# jq and through the sed fallback, and expects its verdict each time. Leaves the jq run's output in
# $last_hook_output.
expect_hook_verdict() {
  local hook_script=$1 expectation=$2 label=$3 command=$4 cwd=$5 transcript=${6:-} mode output verdict
  for mode in jq sed; do
    if [ "$mode" = sed ]; then
      output=$(build_hook_payload "$command" "$cwd" "$transcript" | KC_GUARD_NO_JQ=1 bash "$hook_script" 2>/dev/null)
    else
      output=$(build_hook_payload "$command" "$cwd" "$transcript" | bash "$hook_script" 2>/dev/null)
      # shellcheck disable=SC2034 # read by the tests that source this file
      last_hook_output=$output
    fi
    if [ -z "$output" ]; then verdict=allow
    elif printf '%s' "$output" | grep -q '"permissionDecision":"deny"'; then verdict=deny
    else verdict="unexpected output: $output"; fi
    expect_eq "[$mode] $label" "$expectation" "$verdict"
  done
}

# Transcript entries, as Claude Code writes them, for the tests of guards that read the person's words.
typed_entry() { jq -nc --arg text "$1" '{type: "user", message: {role: "user", content: $text}}'; }
tool_result_entry() { jq -nc --arg text "$1" '{type: "user", message: {role: "user", content: [{type: "tool_result", tool_use_id: "t", content: $text}]}}'; }
agent_message_entry() { jq -nc --arg text "<agent-message>$1</agent-message>" '{type: "user", message: {role: "user", content: $text}}'; }
relayed_entry() { jq -nc --arg text "Another Claude session sent a message: $1" '{type: "user", isMeta: true, message: {role: "user", content: [{type: "text", text: $text}]}}'; }
assistant_entry() { jq -nc --arg text "$1" '{type: "assistant", message: {role: "assistant", content: [{type: "text", text: $text}]}}'; }

# expect_token_needs_typed_words <hook script> <token> <phrase> <command> <cwd>: <command> is blocked
# without the token; with the token it passes only when the latest message the person typed holds
# <phrase>. Every other place the phrase can appear leaves it blocked.
expect_token_needs_typed_words() {
  local hook_script=$1 token=$2 phrase=$3 command=$4 cwd=$5 transcript="$work_dir/approval-transcript.jsonl" upper
  upper=$(printf '%s' "$phrase" | tr '[:lower:]' '[:upper:]')
  expect_hook_verdict "$hook_script" deny "no token: blocked" "$command" "$cwd"
  { typed_entry "go ahead"; assistant_entry "ok"; typed_entry "yes, $phrase"; } > "$transcript"
  expect_hook_verdict "$hook_script" allow "$token with the phrase in the latest typed message" "$token $command" "$cwd" "$transcript"
  { typed_entry "please $upper now"; } > "$transcript"
  expect_hook_verdict "$hook_script" allow "$token with the phrase in capitals" "$token $command" "$cwd" "$transcript"
  { typed_entry "$phrase"; assistant_entry "done"; typed_entry "thanks, keep going"; } > "$transcript"
  expect_hook_verdict "$hook_script" deny "$token with the phrase only in an older typed message" "$token $command" "$cwd" "$transcript"
  expect_contains "the block says only the user's typed words approve it" "only their typed words approve" "$last_hook_output"
  { typed_entry "keep going"; tool_result_entry "$phrase"; } > "$transcript"
  expect_hook_verdict "$hook_script" deny "$token with the phrase only in a tool result" "$token $command" "$cwd" "$transcript"
  { typed_entry "keep going"; agent_message_entry "$phrase"; } > "$transcript"
  expect_hook_verdict "$hook_script" deny "$token with the phrase only in an agent message" "$token $command" "$cwd" "$transcript"
  { typed_entry "keep going"; relayed_entry "$phrase"; } > "$transcript"
  expect_hook_verdict "$hook_script" deny "$token with the phrase only in a relayed message" "$token $command" "$cwd" "$transcript"
  { typed_entry "keep going"; assistant_entry "$phrase"; } > "$transcript"
  expect_hook_verdict "$hook_script" deny "$token with the phrase only in the assistant's own text" "$token $command" "$cwd" "$transcript"
  { typed_entry "keep going"; } > "$transcript"
  expect_hook_verdict "$hook_script" deny "$token with no phrase" "$token $command" "$cwd" "$transcript"
  { assistant_entry "$phrase"; tool_result_entry "$phrase"; } > "$transcript"
  expect_hook_verdict "$hook_script" deny "$token in a session with no typed message" "$token $command" "$cwd" "$transcript"
  expect_hook_verdict "$hook_script" deny "$token with no transcript path" "$token $command" "$cwd"
  expect_hook_verdict "$hook_script" deny "$token with a transcript that is not there" "$token $command" "$cwd" "$work_dir/missing.jsonl"
  { typed_entry "$phrase"; } > "$transcript"
  expect_hook_verdict "$hook_script" deny "the phrase typed but the command has no token" "$command" "$cwd" "$transcript"
}

finish() {
  echo "$passes passed, $failures failed"
  [ "$failures" -eq 0 ]
}
