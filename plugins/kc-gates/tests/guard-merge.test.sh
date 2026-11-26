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
# Routes `gh pr view [<ref>]` to a pull request authored by $1, its head $2 (default $head_sha)
# on base main, its checks the JSON list $3 (default: one passed).
route_pull_request() {
  local fields=headRefOid,author,baseRefName,statusCheckRollup passed_checks='[{"conclusion":"SUCCESS"}]'
  printf '{"headRefOid":"%s","author":{"login":"%s"},"baseRefName":"main","statusCheckRollup":%s}\n' "${2:-$head_sha}" "$1" "${3:-$passed_checks}" > "$work_dir/gh/pr.json"
  printf 'pr view --json %s\tpr.json\npr view 7 --json %s\tpr.json\npr view 7 --repo o/r --json %s\tpr.json\npr view --repo o/r --json %s\tpr.json\npr view 9 --repo x/y --json %s\tpr.json\napi user\tuser.json\n' "$fields" "$fields" "$fields" "$fields" "$fields" > "$work_dir/gh/routes.tsv"
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

# A pull request whose change is small with no risk line (change-class.sh: prose_small or code_small)
# merges with no receipt once its checks pass; a small change on a risk path, or a full-size one, does not.
run_git_in() { local repo=$1; shift; git -C "$repo" -c user.name=t -c user.email=t@example.test "$@"; }
small_repo="$work_dir/small-repo"
git init -q -b main "$small_repo"
git init -q --bare "$small_repo.git"
git -C "$small_repo" remote add origin "$small_repo.git"
printf 'Orders ship in one box.\nRefunds go to the card.\n' > "$small_repo/rules.md"
run_git_in "$small_repo" add rules.md
run_git_in "$small_repo" commit -q -m "shop rules"
git -C "$small_repo" push -q origin main
# Commits a branch from main: $1 the branch, then the files it adds or rewrites.
commit_branch() {
  local branch=$1 changed_file
  shift
  run_git_in "$small_repo" checkout -q -b "$branch" main
  for changed_file in "$@"; do printf 'Refunds go back to the card used.\n' >> "$small_repo/$changed_file"; done
  run_git_in "$small_repo" add "$@"
  run_git_in "$small_repo" commit -q -m "$branch"
  git -C "$small_repo" rev-parse HEAD
}
prose_head=$(commit_branch wording rules.md)
route_pull_request me "$prose_head"
check_verdict allow "allowed: a small prose pull request with its checks passed, no receipt and no phrase" "gh pr merge 7 --squash" "$small_repo"
route_pull_request me "$prose_head" '[{"conclusion":"SUCCESS"},{"status":"IN_PROGRESS","conclusion":null}]'
check_verdict deny "blocked: a small prose pull request whose checks still run" "gh pr merge 7 --squash" "$small_repo"
expect_contains "the block says to wait for the checks, no approval" "1 of them have not passed yet" "$last_hook_output"
expect_not_contains "the block asks for no phrase" "approve merge" "$last_hook_output"
check_verdict allow "allowed: a small prose pull request merged with --auto, which waits for its checks" "gh pr merge 7 --squash --auto" "$small_repo"
route_pull_request me "$prose_head" '[{"conclusion":"FAILURE"}]'
check_verdict deny "blocked: a small prose pull request whose check failed" "gh pr merge 7 --squash" "$small_repo"
code_head=$(commit_branch wording-and-tool rules.md tool.sh)
route_pull_request me "$code_head"
check_verdict allow "allowed: a small code pull request with no risk line, checks passed, no receipt" "gh pr merge 7 --squash" "$small_repo"
route_pull_request me "$code_head" '[{"status":"IN_PROGRESS","conclusion":null}]'
check_verdict deny "blocked: a small code pull request whose checks still run" "gh pr merge 7 --squash" "$small_repo"
route_pull_request me "$(commit_branch risky auth-rules.md tool.sh)"
check_verdict deny "blocked: a small change with a risk line, no receipt" "gh pr merge 7 --squash" "$small_repo"
expect_contains "the block lists every phrase the remaining steps need" 'types one message: \"approve merge\".' "$last_hook_output"
route_pull_request me "$(commit_branch security-fix tool.sh session-timeout.sh)"
check_verdict deny "blocked: a small change in a security path, no receipt" "gh pr merge 7 --squash" "$small_repo"
route_pull_request me "$(commit_branch big rules.md a.sh b.sh c.sh d.sh e.sh)"
check_verdict deny "blocked: a full-size pull request, no receipt" "gh pr merge 7 --squash" "$small_repo"

finish
