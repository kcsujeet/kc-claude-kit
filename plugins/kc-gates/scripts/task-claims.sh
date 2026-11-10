#!/usr/bin/env bash
# Before work on a task starts: lists the pull requests that already name it, so a task someone
# else is building (or has built) is seen before a second change is made for it. It makes no
# judgment; the person decides whether to build, review the open one, or leave it.
#
# Usage: task-claims.sh <task-key> [--repo <owner/name>]...
#   <task-key>  the task's id as titles and descriptions carry it (`ABC-1`, `#42`)
#   --repo      a repository to search; repeat for each repository the task may touch
#               (default: the current directory's repository)
#
# Output, per repository: `## <owner/name>`, then one line per pull request whose title or
# description names the key, newest first (at most `max_rows`, 50):
#   `#<n> <state> @<author> <head branch>: <title>`
# or `(none)`.
#
# gh fields: https://cli.github.com/manual/gh_pr_list (search uses GitHub's issue search syntax).
# The task's assignee lives in the tracker, which this script does not read; check it there.
# Exits 0 on success, 1 when a gh call fails, 2 on a usage error.
set -euo pipefail

script_name=$(basename "$0")
usage() {
  echo "usage: $script_name <task-key> [--repo <owner/name>]..." >&2
  exit 2
}
fail() {
  echo "$script_name: $1" >&2
  exit 1
}

[ "$#" -ge 1 ] || usage
task_key=$1
shift
[ -n "$task_key" ] || usage
repos=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo)
      [ "$#" -ge 2 ] && [ -n "$2" ] || usage
      repos+=("$2")
      shift 2
      ;;
    *) usage ;;
  esac
done
if [ "${#repos[@]}" -eq 0 ]; then
  current_repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner) || fail "gh repo view failed; pass --repo"
  repos=("$current_repo")
fi

# gh pr list returns at most this many per repository; a task named by more is claimed already.
max_rows=50

for repo in "${repos[@]}"; do
  echo "## $repo"
  rows=$(gh pr list --repo "$repo" --state all --search "\"$task_key\" in:title,body" --limit "$max_rows" \
    --json number,state,author,headRefName,title \
    --jq '.[] | "#\(.number) \(.state) @\(.author.login) \(.headRefName): \(.title)"') \
    || fail "gh pr list --repo $repo failed"
  if [ -n "$rows" ]; then
    printf '%s\n' "$rows"
  else
    echo "(none)"
  fi
done
