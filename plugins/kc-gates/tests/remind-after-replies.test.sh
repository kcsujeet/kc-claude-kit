#!/usr/bin/env bash
# Tests scripts/remind-after-replies.sh: every way of posting a reply on a pull request gets the
# reminder of the steps still owed; reads, other writes and unrelated commands get nothing. Each
# case runs twice, once with jq and once through the sed fallback.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
hook="$(dirname "$tests_dir")/scripts/remind-after-replies.sh"

# Wraps a shell command in the PostToolUse stdin payload, its double quotes escaped.
build_payload() {
  local command
  command=$(printf '%s' "$1" | sed 's/"/\\"/g')
  printf '{"session_id":"s","cwd":"%s","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"%s"},"tool_response":{"stdout":"","stderr":""},"tool_use_id":"t"}' "$work_dir" "$command"
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
    elif printf '%s' "$output" | grep -q '"hookEventName":"PostToolUse","additionalContext":"kc-gates: Replies are posted'; then
      verdict=remind
    else
      verdict="unexpected output: $output"
    fi
    expect_eq "[$mode] $label" "$expectation" "$verdict"
  done
}

# --- replies -------------------------------------------------------------------------------------
expect_hook remind "a reply to a review comment, POST named" "gh api -X POST repos/shop/web/pulls/12/comments/345/replies -f body='Done in abc1234'"
expect_hook remind "a reply with --method POST" "gh api --method POST repos/shop/web/pulls/12/comments/345/replies -f body=Done"
expect_hook remind "a reply with a field and no method (gh defaults to POST)" "gh api repos/shop/web/pulls/12/comments/345/replies -f body=Done"
expect_hook remind "a reply with an --input file" "gh api repos/shop/web/pulls/12/comments/345/replies --input reply.json"
expect_hook remind "a reply to the comments endpoint with in_reply_to" "gh api repos/shop/web/pulls/12/comments -f body=Done -F in_reply_to=345"
expect_hook remind "in_reply_to as a JSON field" "gh api -X POST repos/shop/web/pulls/12/comments --raw-field 'in_reply_to=345' -f body=Done"
expect_hook remind "a reply with ids held in shell variables" "gh api repos/shop/web/pulls/\$PR/comments/\${ID}/replies -f body=Done"
expect_hook remind "an in_reply_to reply with the PR number in a variable" "gh api repos/shop/web/pulls/\$PR/comments -f body=Done -F in_reply_to=\$ID"
expect_hook remind "a reply with the method in lowercase" "gh api -X post repos/shop/web/pulls/12/comments/345/replies -f body=Done"
expect_hook remind "a reply with the field attached to its flag" "gh api repos/shop/web/pulls/12/comments/345/replies -fbody=Done"
expect_hook remind "gh pr comment" "gh pr comment 12 --body 'Fixed in abc1234'"
expect_hook remind "gh pr comment with a body file" "gh pr comment 12 --body-file reply.md"
expect_hook remind "a reply after another command" "cd /tmp && gh api repos/shop/web/pulls/12/comments/345/replies -f body=Done"
expect_hook remind "a reply in a loop of several" "gh api repos/shop/web/pulls/12/comments/1/replies -f body=a; gh api repos/shop/web/pulls/12/comments/2/replies -f body=b"
expect_contains "the reminder lists CI, the reviewer, the ticket and the look-back" \
  "wait for CI on the pull request head to pass; re-request the reviewer (\`gh pr edit <n> --add-reviewer <login>\`); move the tracker ticket back to the review status, assigned to that reviewer; then, once the round is handed off, the look-back (\`kc-conventions:kc-look-back\`). Put them on the task list." \
  "$(build_payload "gh pr comment 12 --body hi" | bash "$hook")"

# --- not replies ---------------------------------------------------------------------------------
expect_hook quiet "a GET of a comment's replies" "gh api repos/shop/web/pulls/12/comments/345/replies"
expect_hook quiet "a GET of a PR's comments" "gh api repos/shop/web/pulls/12/comments"
expect_hook quiet "a GET of replies with ids held in shell variables" "gh api repos/shop/web/pulls/\$PR/comments/\$ID/replies"
expect_hook quiet "an explicit lowercase get with an attached query field" "gh api -X get repos/shop/web/pulls/12/comments/345/replies -fper_page=5"
expect_hook quiet "an explicit GET with a query field" "gh api -X GET repos/shop/web/pulls/12/comments/345/replies -f per_page=5"
expect_hook quiet "a new top-level review comment (no in_reply_to)" "gh api repos/shop/web/pulls/12/comments -f body=Hi -f path=a.rb -F line=3"
expect_hook quiet "a POST to a reply endpoint by another tool" "curl -X POST https://api.example.test/repos/shop/web/pulls/12/comments/345/replies -d body=Done"
expect_hook quiet "in_reply_to on another endpoint" "gh api -X POST repos/shop/web/issues/12/comments -f body=Done -F in_reply_to=345"
expect_hook quiet "an unrelated gh api POST" "gh api -X POST repos/shop/web/issues/12/labels -f labels[]=bug"
expect_hook quiet "a PATCH of a review comment" "gh api -X PATCH repos/shop/web/pulls/comments/345 -f body=Edited"
expect_hook quiet "a review comment deleted" "gh api -X DELETE repos/shop/web/pulls/comments/345"
expect_hook quiet "gh pr view" "gh pr view 12 --comments"
expect_hook quiet "gh issue comment" "gh issue comment 12 --body hi"
expect_hook quiet "an unrelated command" "git status"
expect_hook quiet "the words echoed, not run" "echo run gh-pr-comment later"
expect_hook quiet "in_reply_to named by a read in a later command" "gh api repos/shop/web/pulls/12/comments ; echo in_reply_to"

finish
