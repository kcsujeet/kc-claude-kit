#!/usr/bin/env bash
# Tests scripts/task-claims.sh against the stub gh in lib/, answering from
# fixtures/task-claims/: one repository with an open and a closed pull request naming the task,
# one with none, and the current repository as the default.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
task_claims="$(dirname "$tests_dir")/scripts/task-claims.sh"
require_jq
use_gh_fixtures "$tests_dir/fixtures/task-claims"

two_repos=$(bash "$task_claims" ABC-1 --repo acme/shop --repo acme/shop-api)
expect_eq "two repos: every pull request naming the task, then (none) for the other" "## acme/shop
#41 OPEN @alice ABC-1-storefront-hours: ABC-1: Show storefront opening hours
#37 CLOSED @bob abc-1-first-try: Hours on the storefront (ABC-1)
## acme/shop-api
(none)" "$two_repos"

expect_eq "no --repo: the current repository is searched" "## acme/shop" "$(bash "$task_claims" ABC-1 | sed -n 1p)"

if grep -Eqv '^(pr list|repo view) ' "$KC_GH_LOG"; then
  record "only read calls reached gh" fail "$(cat "$KC_GH_LOG")"
else
  record "only read calls reached gh" ok
fi

set +e
bash "$task_claims" > /dev/null 2>&1
no_key_status=$?
bash "$task_claims" ABC-1 --repo > /dev/null 2>&1
bare_repo_status=$?
bash "$task_claims" ABC-1 --repo acme/unrouted > /dev/null 2> "$work_dir/gh-fail.err"
gh_fail_status=$?
set -e
expect_eq "usage: no key exits 2" 2 "$no_key_status"
expect_eq "usage: --repo without a value exits 2" 2 "$bare_repo_status"
expect_eq "a failing gh call exits 1" 1 "$gh_fail_status"
expect_contains "a failing gh call names the repository" "gh pr list --repo acme/unrouted failed" "$(cat "$work_dir/gh-fail.err")"

finish
