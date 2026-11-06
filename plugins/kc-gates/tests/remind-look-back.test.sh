#!/usr/bin/env bash
# Tests scripts/remind-look-back.sh: every way of approving a pull request gets the look-back
# reminder; comments, other reviews and reads get nothing. Each case runs twice, once with jq and
# once through the sed fallback.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
hook="$(dirname "$tests_dir")/scripts/remind-look-back.sh"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

passes=0
failures=0

# Wraps a shell command in the PostToolUse stdin payload: its double quotes escaped, and `\n` in
# it left as JSON's newline escape.
build_payload() {
  local command
  command=$(printf '%s' "$1" | sed 's/"/\\"/g')
  printf '{"session_id":"s","cwd":"%s","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"%s","description":"test"},"tool_response":{"stdout":"","stderr":""},"tool_use_id":"t"}' "$work_dir" "$command"
}

expect_hook() {
  local expectation=$1 label=$2 command=$3 mode output verdict
  for mode in jq sed; do
    if [ "$mode" = jq ] && ! command -v jq >/dev/null 2>&1; then
      continue
    fi
    if [ "$mode" = sed ]; then
      output=$(build_payload "$command" | KC_GUARD_NO_JQ=1 bash "$hook")
    else
      output=$(build_payload "$command" | bash "$hook")
    fi
    if [ -z "$output" ]; then
      verdict=quiet
    elif printf '%s' "$output" | grep -q '"hookEventName":"PostToolUse","additionalContext":"kc-gates: this approved a pull request'; then
      verdict=remind
    else
      verdict="unexpected output: $output"
    fi
    if [ "$verdict" = "$expectation" ]; then
      echo "ok   [$mode] $label"
      passes=$((passes + 1))
    else
      echo "FAIL [$mode] $label: expected $expectation, got $verdict"
      failures=$((failures + 1))
    fi
  done
}

printf '{"commit_id":"abc","event":"APPROVE"}' > "$work_dir/approve.json"
printf '{"commit_id":"abc","event":"COMMENT","comments":[]}' > "$work_dir/comment.json"

# --- approvals -----------------------------------------------------------------------------------
expect_hook remind "gh pr review --approve" "gh pr review 12 --approve"
expect_hook remind "gh pr review -a with a body" "gh pr review 12 -a --body 'ship it'"
expect_hook remind "gh api with -f event=APPROVE" "KC_REVIEW_POST_APPROVED=1 gh api repos/shop/web/pulls/12/reviews -X POST -f event=APPROVE -f commit_id=abc"
expect_hook remind "gh api with an --input file holding APPROVE" "gh api repos/shop/web/pulls/12/reviews -X POST --input approve.json"
expect_hook remind "an approval after another command" "cd /tmp && gh pr review 12 --approve"
expect_hook remind "a quoted event field" "gh api repos/shop/web/pulls/12/reviews -X POST -f 'event=APPROVE'"
expect_hook remind "--approve quoted on its own" "gh pr review 12 '--approve'"

# --- not approvals -------------------------------------------------------------------------------
expect_hook quiet "a comment review from its --input file" "gh api repos/shop/web/pulls/12/reviews -X POST --input comment.json"
expect_hook quiet "gh pr review --comment" "gh pr review 12 --comment --body 'one question'"
expect_hook quiet "gh pr review --request-changes" "gh pr review 12 --request-changes --body 'see inline'"
expect_hook quiet "reading the reviews" "gh api repos/shop/web/pulls/12/reviews -q '.[].state'"
expect_hook quiet "an approve event on another endpoint" "gh api repos/shop/web/issues/12/comments -f event=APPROVE"
expect_hook quiet "an --input file that isn't there" "gh api repos/shop/web/pulls/12/reviews -X POST --input missing.json"
expect_hook quiet "APPROVE in a later command than the reviews read" "gh api repos/shop/web/pulls/12/reviews -q .id ; echo event=APPROVE"
expect_hook quiet "an approve payload echoed, not sent" "echo repos/shop/web/pulls/12/reviews event=APPROVE"
expect_hook quiet "an unrelated command" "git status"

stray_error=$(build_payload "gh api repos/shop/web/pulls/12/reviews -X POST --input" | bash "$hook" 2>&1 >/dev/null)
if [ -z "$stray_error" ]; then
  echo "ok   an --input with no path prints nothing on stderr"
  passes=$((passes + 1))
else
  echo "FAIL an --input with no path prints nothing on stderr: $stray_error"
  failures=$((failures + 1))
fi

echo "$passes passed, $failures failed"
[ "$failures" -eq 0 ]
