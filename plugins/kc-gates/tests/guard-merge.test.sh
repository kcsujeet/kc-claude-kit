#!/usr/bin/env bash
# Tests scripts/guard-merge.sh: `gh pr merge` of the user's own pull request is denied unless its
# head has a clean kc-ready-for-review receipt (clean=yes), or the command carries
# KC_MERGE_APPROVED=1 and the user typed "approve merge". Someone else's pull request, and a
# lookup that fails, are not blocked. The stub gh in lib/ answers the lookups; each case runs twice,
# once with jq and once through the sed fallback.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
scripts="$(dirname "$tests_dir")/scripts"
require_jq
export KC_READY_DIR="$work_dir/receipts"
mkdir -p "$KC_READY_DIR" "$work_dir/gh" "$work_dir/repo"
use_gh_fixtures "$work_dir/gh"

head_sha=$(printf '%040d' 0 | tr 0 a)
printf '{"login":"me"}\n' > "$work_dir/gh/user.json"
# Routes `gh pr view [<ref>]` to a pull request whose head is $head_sha, authored by $1.
route_pull_request() {
  printf '{"headRefOid":"%s","author":{"login":"%s"}}\n' "$head_sha" "$1" > "$work_dir/gh/pr.json"
  printf 'pr view --json headRefOid,author\tpr.json\npr view 7 --json headRefOid,author\tpr.json\npr view 7 --repo o/r --json headRefOid,author\tpr.json\npr view --repo o/r --json headRefOid,author\tpr.json\npr view 9 --repo x/y --json headRefOid,author\tpr.json\napi user\tuser.json\n' > "$work_dir/gh/routes.tsv"
}
check_verdict() { expect_hook_verdict "$scripts/guard-merge.sh" "$@"; }

route_pull_request me
check_verdict deny "blocked: merging your own pull request with no receipt" "gh pr merge 7 --squash" "$work_dir/repo"
expect_contains "the message says why" "has no clean review receipt" "$last_hook_output"
check_verdict deny "blocked: the current branch's pull request, no number" "gh pr merge --squash" "$work_dir/repo"
check_verdict deny "blocked: a flag's value before the number is not the ref" "gh pr merge --subject x 7" "$work_dir/repo"
check_verdict deny "blocked: -R names the repo, the number is still the ref" "gh pr merge -R o/r 7 --squash" "$work_dir/repo"
check_verdict deny "blocked: --repo with no number is the current branch's pull request" "gh pr merge --repo o/r" "$work_dir/repo"
check_verdict deny "blocked: a gh api PUT to the merge endpoint, its number and repo read from the path" "gh api -X PUT repos/x/y/pulls/9/merge" "$work_dir/repo"
check_verdict deny "blocked: a gh api merge written with {owner}/{repo} reads the directory's repo" "gh api -X PUT repos/{owner}/{repo}/pulls/7/merge" "$work_dir/repo"
check_verdict allow "allowed: --disable-auto only cancels a queued merge" "gh pr merge 7 --disable-auto" "$work_dir/repo"

printf 'sha=%s\nrounds=2\nopen=0\nclean=no\n' "$head_sha" > "$KC_READY_DIR/$head_sha"
check_verdict deny "blocked: a receipt whose last round still found something" "gh pr merge 7 --squash" "$work_dir/repo"
expect_token_needs_typed_words "$scripts/guard-merge.sh" KC_MERGE_APPROVED=1 "approve merge" "gh pr merge 7 --squash" "$work_dir/repo"

printf 'sha=%s\nrounds=2\nopen=0\nclean=yes\n' "$head_sha" > "$KC_READY_DIR/$head_sha"
check_verdict allow "allowed: a clean receipt" "gh pr merge 7 --squash" "$work_dir/repo"
rm "$KC_READY_DIR/$head_sha"

route_pull_request someone-else
check_verdict allow "allowed: someone else's pull request" "gh pr merge 7 --squash" "$work_dir/repo"

: > "$work_dir/gh/routes.tsv"
check_verdict allow "allowed: a lookup that fails is not blocked" "gh pr merge 7 --squash" "$work_dir/repo"
check_verdict allow "allowed: a command that is not a merge" "gh pr view 7" "$work_dir/repo"

finish
