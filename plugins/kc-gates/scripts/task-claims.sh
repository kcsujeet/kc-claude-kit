#!/usr/bin/env bash
# Before work on a task starts: lists the pull requests that already name it, so a task someone
# else is building (or has built) is seen before a second change is made for it. It makes no
# judgment; the person decides whether to build, review the open one, or leave it.
#
# Work also overlaps by the code it changes, not only by its task key: another open pull request,
# for a different task, may change the same lines, and the default branch may have changed or fixed
# them since the task was assessed. --path and --since check that; run them at assessment and again
# right before handing work to a reviewer.
#
# Usage: task-claims.sh <task-key> [--repo <owner/name>]... [--path <file-or-dir>]... [--since <commit>]
#   <task-key>  the task's id as titles and descriptions carry it (`ABC-1`, `#42`)
#   --repo      a repository to search; repeat for each repository the task may touch
#               (default: the current directory's repository)
#   --path      a file (or a directory, matching every file under it) the change touches; repeat
#               for each. Adds, after the output below, a section per repository listing the open
#               pull requests, any author, whose changed files include one of them
#   --since     with --path, run inside a local checkout: after fetching, lists the commits on the
#               default branch after <commit> that touch the paths, so a change the default branch
#               already made or fixed shows up
#
# Output, per repository: `## <owner/name>`, then one line per pull request whose title or
# description names the key, newest first (at most `max_rows`, 50):
#   `#<n> <state> @<author> <head branch>: <title>`
# or `(none)`. With --path, then, per repository, `## <owner/name>: open pull requests changing
# the paths` and one line per pull request (the newest `max_scan`, 100, are scanned):
#   `#<n> @<author> <head branch>: <title> [<matching paths>]`
# or `(none)`; with --since, last, `## commits on <default branch> after <commit> changing the paths`
# and one `git log` line (`<short sha> <author> <subject>`) per commit, or `(none)`.
# The paths are literal repo-relative files or directories (a leading `./` is dropped, no globs). A
# pull request is matched by the files gh lists for it, so a file it renames away is not seen, and gh
# lists at most `max_pr_files` (100) files per pull request: one with that many that matches no path
# is listed anyway, marked `files list may be cut off`, and a scan that returned `max_scan` pull
# requests ends with a line saying older open ones were not checked. `(none)` alone means all were read.
#
# gh fields: https://cli.github.com/manual/gh_pr_list (search uses GitHub's issue search syntax).
# The task's assignee lives in the tracker, which this script does not read; check it there.
# Exits 0 on success, 1 when a gh or git call fails, 2 on a usage error.
set -euo pipefail

script_name=$(basename "$0")
usage() {
  echo "usage: $script_name <task-key> [--repo <owner/name>]... [--path <file-or-dir>]... [--since <commit>]" >&2
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
paths=()
since=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo)
      [ "$#" -ge 2 ] && [ -n "$2" ] || usage
      repos+=("$2")
      shift 2
      ;;
    --path)
      [ "$#" -ge 2 ] && [ -n "$2" ] || usage
      path=${2%/}
      path=${path#./}
      [ -n "$path" ] || usage
      paths+=("$path")
      shift 2
      ;;
    --since)
      [ "$#" -ge 2 ] && [ -n "$2" ] || usage
      since=$2
      shift 2
      ;;
    *) usage ;;
  esac
done
[ -z "$since" ] || [ "${#paths[@]}" -gt 0 ] || usage
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

if [ "${#paths[@]}" -gt 0 ]; then
  # gh pr list returns at most this many open pull requests per repository, and at most
  # max_pr_files files per pull request.
  max_scan=100
  max_pr_files=100
  # The paths and limits reach the jq filter through the environment, so no quoting is needed.
  KC_CLAIM_PATHS=$(printf '%s\n' "${paths[@]}")
  KC_CLAIM_MAX_SCAN=$max_scan
  KC_CLAIM_MAX_PR_FILES=$max_pr_files
  export KC_CLAIM_PATHS KC_CLAIM_MAX_SCAN KC_CLAIM_MAX_PR_FILES
  for repo in "${repos[@]}"; do
    echo "## $repo: open pull requests changing the paths"
    # shellcheck disable=SC2016 # the $ names are jq variables, not shell ones
    rows=$(gh pr list --repo "$repo" --state open --limit "$max_scan" \
      --json number,author,headRefName,title,files \
      --jq '(env.KC_CLAIM_PATHS | split("\n")) as $p | (.[]
        | [.files[].path | select(. as $f | any($p[]; . as $q | $q == $f or ($f | startswith($q + "/"))))] as $hit
        | if ($hit | length) > 0 then "#\(.number) @\(.author.login) \(.headRefName): \(.title) [\($hit | join(", "))]"
          elif (.files | length) >= (env.KC_CLAIM_MAX_PR_FILES | tonumber) then "#\(.number) @\(.author.login) \(.headRefName): \(.title) [files list may be cut off]"
          else empty end),
        (if length >= (env.KC_CLAIM_MAX_SCAN | tonumber) then "(scan stopped at \(length) open pull requests: older ones were not checked)" else empty end)') \
      || fail "gh pr list --repo $repo (open, by files) failed"
    if [ -n "$rows" ]; then
      printf '%s\n' "$rows"
    else
      echo "(none)"
    fi
  done
fi

if [ -n "$since" ]; then
  git fetch --quiet origin || fail "git fetch origin failed; run inside a checkout of the repository"
  default_ref=$(git symbolic-ref --short refs/remotes/origin/HEAD 2> /dev/null) || default_ref=origin/main
  echo "## commits on $default_ref after $since changing the paths"
  commits=$(git --literal-pathspecs log --format='%h %an %s' "$since..$default_ref" -- "${paths[@]}") \
    || fail "git log $since..$default_ref failed"
  if [ -n "$commits" ]; then
    printf '%s\n' "$commits"
  else
    echo "(none)"
  fi
fi
