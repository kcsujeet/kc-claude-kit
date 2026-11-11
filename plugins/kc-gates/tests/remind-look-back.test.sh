#!/usr/bin/env bash
# Tests scripts/remind-look-back.sh: every way of approving a pull request gets the review's
# look-back reminder and every way of merging one gets the task's; comments, other reviews, reads
# and cancelling a queued merge get nothing. Each case runs twice, once with jq and once through
# the sed fallback.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
hook="$(dirname "$tests_dir")/scripts/remind-look-back.sh"
# `~/` in an --input path is read from $HOME.
export HOME="$work_dir"

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
    elif printf '%s' "$output" | grep -q '"hookEventName":"PostToolUse","additionalContext":"kc-gates: this merged a pull request'; then
      verdict=remind-merge
    else
      verdict="unexpected output: $output"
    fi
    expect_eq "[$mode] $label" "$expectation" "$verdict"
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
expect_hook remind "a pending review submitted as APPROVE" "gh api repos/shop/web/pulls/12/reviews/7/events -X POST -f event=APPROVE"
expect_hook remind "an --input file under ~/" "gh api repos/shop/web/pulls/12/reviews -X POST --input ~/approve.json"
expect_hook remind "an --input file by absolute path, as the payload builder prints it" "gh api repos/shop/web/pulls/12/reviews -X POST --input $work_dir/approve.json"

# --- merges --------------------------------------------------------------------------------------
expect_hook remind-merge "gh pr merge" "gh pr merge 12 --merge"
expect_hook remind-merge "gh pr merge with no number, squashing" "gh pr merge --squash --delete-branch"
expect_hook remind-merge "gh pr merge alone on its line" "gh pr merge"
expect_hook remind-merge "a merge queued with --auto" "gh pr merge 12 --auto --rebase"
expect_hook remind-merge "a merge after another command" "gh pr view 12 --json state && gh pr merge 12 --merge"
expect_hook remind-merge "gh api PUT to the merge endpoint" "gh api repos/shop/web/pulls/12/merge -X PUT -f merge_method=squash"
expect_hook remind-merge "gh api --method PUT, quoted" "gh api --method 'PUT' repos/shop/web/pulls/12/merge"

# --- not merges ----------------------------------------------------------------------------------
expect_hook quiet "cancelling a queued merge" "gh pr merge 12 --disable-auto"
expect_hook quiet "asking whether a pull request is merged" "gh api repos/shop/web/pulls/12/merge"
expect_hook quiet "a PUT to another endpoint of the pull request" "gh api repos/shop/web/pulls/12/update-branch -X PUT"
expect_hook quiet "a merge command echoed, not run" "echo run gh-pr-merge later"
expect_hook quiet "git merge" "git merge main"
expect_hook quiet "a merge endpoint read in one command and a PUT in a later one" "gh api repos/shop/web/pulls/12/merge ; gh api repos/shop/web/pulls/12/update-branch -X PUT"

# --- not approvals -------------------------------------------------------------------------------
expect_hook quiet "a comment review from its --input file" "gh api repos/shop/web/pulls/12/reviews -X POST --input comment.json"
expect_hook quiet "gh pr review --comment" "gh pr review 12 --comment --body 'one question'"
expect_hook quiet "gh pr review --request-changes" "gh pr review 12 --request-changes --body 'see inline'"
expect_hook quiet "reading the reviews" "gh api repos/shop/web/pulls/12/reviews -q '.[].state'"
expect_hook quiet "an approve event on another endpoint" "gh api repos/shop/web/issues/12/comments -f event=APPROVE"
expect_hook quiet "an --input file that isn't there" "gh api repos/shop/web/pulls/12/reviews -X POST --input missing.json"
expect_hook quiet "APPROVE in a later command than the reviews read" "gh api repos/shop/web/pulls/12/reviews -q .id ; echo event=APPROVE"
expect_hook quiet "an approve payload echoed, not sent" "echo repos/shop/web/pulls/12/reviews event=APPROVE"
expect_hook quiet "a review's comments, not its events" "gh api repos/shop/web/pulls/12/reviews/7/comments -f event=APPROVE"
expect_hook quiet "an unrelated command" "git status"

stray_error=$(build_payload "gh api repos/shop/web/pulls/12/reviews -X POST --input" | bash "$hook" 2>&1 >/dev/null)
expect_eq "an --input with no path prints nothing on stderr" "" "$stray_error"

# A payload with no cwd reads a relative --input path from the directory the hook runs in.
no_cwd_payload='{"tool_input":{"command":"gh api repos/shop/web/pulls/12/reviews -X POST --input approve.json"}}'
for mode in jq sed; do
  if [ "$mode" = jq ] && ! command -v jq >/dev/null 2>&1; then
    continue
  fi
  no_jq=0
  [ "$mode" = sed ] && no_jq=1
  no_cwd_output=$(cd "$work_dir" && printf '%s' "$no_cwd_payload" | KC_GUARD_NO_JQ=$no_jq bash "$hook")
  expect_contains "[$mode] a payload with no cwd reads the --input path from where the hook runs" "this approved a pull request" "$no_cwd_output"
done

finish
