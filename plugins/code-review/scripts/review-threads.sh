#!/usr/bin/env bash
# Prints a PR's review comment threads for a re-review: every review comment,
# grouped into threads by in_reply_to_id, each thread as its root comment then
# its replies in order.
#
# Usage: review-threads.sh <pr-number> [--mine <login>]
#   --mine  also mark, per thread, whether <login> started it and whether the
#           PR author replied after <login>'s last comment in it
#
# Fetches `gh api --paginate repos/{owner}/{repo}/pulls/<n>/comments`; gh fills
# {owner} and {repo} from the current directory's repository or GH_REPO, and
# prints each page as its own JSON array, which jq -s joins
# (https://cli.github.com/manual/gh_api). Response fields:
# https://docs.github.com/en/rest/pulls/comments#list-review-comments-on-a-pull-request
#
# Output: `<t> thread(s), <c> comment(s)`, then per thread:
#   thread <root-id> <path>:<line> (<n> comment[s])
#   started-by-you: yes|no                        (with --mine)
#   author-replied-after-your-last: yes|no|n/a    (with --mine; n/a when you
#                                                  have no comment in it)
#     <id> @<user> <path>:<line>[ (reply to <parent-id>)]
#       <body, indented>
# <line> is the comment's current line, or `<original_line> (outdated)` when
# GitHub reports no current line; a file-level comment shows the path alone.
#
# Requires jq. Exits 0 on success, 1 when jq is missing or gh fails, 2 on a
# usage error.
set -euo pipefail

script_name=$(basename "$0")
usage() {
  echo "usage: $script_name <pr-number> [--mine <login>]" >&2
  exit 2
}
fail() {
  echo "$script_name: $1" >&2
  exit 1
}

pr_number=""
mine_login=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --mine)
      [ "$#" -ge 2 ] && [ -n "$2" ] || usage
      mine_login=$2
      shift
      ;;
    '' | *[!0-9]*) usage ;;
    *)
      [ -z "$pr_number" ] || usage
      pr_number=$1
      ;;
  esac
  shift
done
[ -n "$pr_number" ] || usage

command -v jq >/dev/null 2>&1 || fail "jq is required but not installed (https://jqlang.org/download/)"

pages=$(gh api --paginate "repos/{owner}/{repo}/pulls/$pr_number/comments?per_page=100") \
  || fail "gh api for PR $pr_number review comments failed"

pr_author=""
if [ -n "$mine_login" ]; then
  pr_author=$(gh pr view "$pr_number" --json author --jq '.author.login') \
    || fail "gh pr view $pr_number failed"
fi

printf '%s\n' "$pages" | jq -r -s --arg mine "$mine_login" --arg author "$pr_author" '
  # Follows in_reply_to_id up to the thread root. A parent missing from the
  # listing makes the comment its own root.
  def root_id($by_id):
    if .in_reply_to_id != null and ($by_id[.in_reply_to_id | tostring] != null)
    then $by_id[.in_reply_to_id | tostring] | root_id($by_id)
    else .id end;
  def location:
    if .line != null then "\(.path):\(.line)"
    elif .original_line != null then "\(.path):\(.original_line) (outdated)"
    else .path end;
  def indent_body: (.body // "") | gsub("\r"; "") | split("\n") | map("      " + .) | join("\n");

  (add // []) as $comments
  | ($comments | map({key: (.id | tostring), value: .}) | from_entries) as $by_id
  | ($comments | map(. + {root: root_id($by_id)})
      | group_by(.root)
      | map(sort_by((if .id == .root then 0 else 1 end), .created_at, .id))
      | sort_by(.[0].created_at, .[0].id)) as $threads
  | "\($threads | length) thread(s), \($comments | length) comment(s)",
    ($threads[] as $thread
      | ($thread | map(.user.login)) as $users
      | ([$users | to_entries[] | select(.value == $mine) | .key] | last) as $my_last
      | "",
        "thread \($thread[0].id) \($thread[0] | location) (\($thread | length) comment\(if ($thread | length) == 1 then "" else "s" end))",
        (if $mine == "" then empty else
          "started-by-you: \(if $users[0] == $mine then "yes" else "no" end)",
          "author-replied-after-your-last: \(
            if $my_last == null then "n/a"
            elif ([$users[($my_last + 1):][] | select(. == $author)] | length) > 0 then "yes"
            else "no" end)"
        end),
        ($thread[]
          | "  \(.id) @\(.user.login) \(location)\(if .in_reply_to_id != null then " (reply to \(.in_reply_to_id))" else "" end)",
            indent_body))
'
