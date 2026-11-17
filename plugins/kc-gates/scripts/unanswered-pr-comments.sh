#!/usr/bin/env bash
# Lists the review comments on the current branch's pull request that its author has not answered:
# inline comments (`pulls/<n>/comments`, grouped into threads by in_reply_to_id) and top-level ones
# (`issues/<n>/comments`), from anyone but the author, bot reviewers included. A comment is
# answered when the PR's author wrote a comment after it in the same thread (top-level comments
# are one thread). ready-receipt.sh refuses a receipt while any comment is unanswered, since a
# bot posts when the PR goes ready and a pass that never read it hands the PR on with it open.
#
# Usage: unanswered-pr-comments.sh      (from the repo of the branch)
# Output: one line per unanswered comment, `<path>:<line> @<author>: <start of the comment>` (or
#         `top-level @<author>: ...`). Exits 1 when there is any, 0 when there is none. With no
#         PR for the branch, no gh, no jq or no network, it prints a note on stderr and exits 0:
#         there is nothing to read yet, and the check must not block work offline.
# Fields: https://docs.github.com/en/rest/pulls/comments, https://docs.github.com/en/rest/issues/comments
set -uo pipefail

skip() { echo "unanswered-pr-comments: $1; PR comments not checked" >&2; exit 0; }

command -v gh >/dev/null 2>&1 || skip "gh is not installed"
command -v jq >/dev/null 2>&1 || skip "jq is not installed"
pr_json=$(gh pr view --json number,author 2>/dev/null) || skip "no pull request for this branch, or gh is offline"
pr_number=$(printf '%s' "$pr_json" | jq -r '.number // empty')
pr_author=$(printf '%s' "$pr_json" | jq -r '.author.login // empty')
[ -n "$pr_number" ] && [ -n "$pr_author" ] || skip "gh gave no pull request number or author"
inline=$(gh api --paginate "repos/{owner}/{repo}/pulls/$pr_number/comments?per_page=100" 2>/dev/null) || skip "gh could not read the review comments"
top_level=$(gh api --paginate "repos/{owner}/{repo}/issues/$pr_number/comments?per_page=100" 2>/dev/null) || skip "gh could not read the PR comments"

unanswered=$(jq -rn --arg author "$pr_author" --slurpfile inline_pages <(printf '%s' "$inline" | jq -s 'add // []') \
  --slurpfile top_pages <(printf '%s' "$top_level" | jq -s 'add // []') '
  def snippet: (.body // "") | gsub("[\r\n\t]+"; " ") | .[0:60];
  def root_id($by_id):
    if .in_reply_to_id != null and ($by_id[.in_reply_to_id | tostring] != null)
    then $by_id[.in_reply_to_id | tostring] | root_id($by_id)
    else .id end;
  def unanswered_in($thread):
    . as $comment
    | $comment.user.login != $author
      and ([$thread[] | select(.user.login == $author and .created_at > $comment.created_at)] | length) == 0;

  ($inline_pages[0]) as $inline
  | ($inline | map({key: (.id | tostring), value: .}) | from_entries) as $by_id
  | ($inline | map(. + {root: root_id($by_id)})) as $rooted
  | ($rooted[] | . as $comment
      | select($comment | unanswered_in($rooted | map(select(.root == $comment.root))))
      | "\(.path):\(.line // .original_line // "?") @\(.user.login): \(snippet)"),
    ($top_pages[0] as $top | $top[] | select(unanswered_in($top))
      | "top-level @\(.user.login): \(snippet)")
')

[ -n "$unanswered" ] || exit 0
printf '%s\n' "$unanswered"
exit 1
