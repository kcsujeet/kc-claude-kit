#!/usr/bin/env bash
# Tests scripts/task-claims.sh against the stub gh in lib/, answering from
# fixtures/task-claims/: one repository with an open and a closed pull request naming the task,
# one with none, and the current repository as the default. --path lists open pull requests by the
# files they change; --since lists default-branch commits to the paths, on a throwaway git repo.
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

plain_output=$(bash "$task_claims" ABC-1 --repo acme/shop --repo acme/shop-api)
expect_eq "no --path or --since: the output is the old output byte for byte" "$two_repos" "$plain_output"

by_file=$(bash "$task_claims" ABC-1 --repo acme/shop --repo acme/shop-api --path src/storefront/Header.tsx --path src/storefront/hours)
expect_eq "--path: open pull requests changing a listed file or a file under a listed directory, after the old output" "$two_repos
## acme/shop: open pull requests changing the paths
#52 @alice ABC-2-footer-links: ABC-2: Footer links [src/storefront/Header.tsx]
#47 @bob ABC-4-hours-layout: ABC-4: Hours layout [src/storefront/hours/Layout.tsx, src/storefront/hours/Row.tsx]
## acme/shop-api: open pull requests changing the paths
(none)" "$by_file"
expect_eq "--path: a trailing slash on a directory still matches" "#47" "$(bash "$task_claims" ABC-1 --repo acme/shop --path src/storefront/hours/ | grep '^#47' | cut -d' ' -f1)"
expect_eq "--path: a path no open pull request changes lists none" "## acme/shop: open pull requests changing the paths
(none)" "$(bash "$task_claims" ABC-1 --repo acme/shop --path src/storefront/Hea | sed -n '/^## acme\/shop: open/,$p')"
expect_contains "--path: only open pull requests are asked for" "--state open" "$(grep 'json number,author' "$KC_GH_LOG" | tail -1)"

# --since, on a throwaway checkout whose origin has a commit to the path after the base, and one to another file.
origin_repo="$work_dir/origin.git"
checkout="$work_dir/checkout"
git init --quiet --bare --initial-branch=main "$origin_repo"
git clone --quiet "$origin_repo" "$checkout" 2> /dev/null
git_in_checkout() { git -C "$checkout" -c user.name=dev -c user.email=dev@example.com "$@"; }
mkdir -p "$checkout/src"
echo one > "$checkout/src/Header.tsx"
git_in_checkout add -A
git_in_checkout commit --quiet -m "Base"
git_in_checkout push --quiet origin HEAD:main 2> /dev/null
base_sha=$(git_in_checkout rev-parse HEAD)
echo two > "$checkout/src/Header.tsx"
git_in_checkout commit --quiet -am "Rewrite the header"
echo notes > "$checkout/NOTES.md"
git_in_checkout add -A
git_in_checkout commit --quiet -m "Add notes"
git_in_checkout push --quiet origin HEAD:main 2> /dev/null
# The checkout has not fetched since the push by another clone: make the commits arrive only through the script's fetch.
git_in_checkout update-ref -d refs/remotes/origin/main
git_in_checkout reset --quiet --hard "$base_sha"

since_output=$(cd "$checkout" && bash "$task_claims" ABC-1 --repo acme/shop --path src/Header.tsx --since "$base_sha" | sed -n '/^## commits/,$p')
expect_eq "--since: a default-branch commit touching the path is listed, one touching another file is not" "## commits on origin/main after $base_sha changing the paths
$(git_in_checkout log -1 --format='%h dev %s' --grep='Rewrite the header' origin/main)" "$since_output"
other_file_output=$(cd "$checkout" && bash "$task_claims" ABC-1 --repo acme/shop --path NOTES.md --path src/Other.tsx --since "$(git_in_checkout rev-parse origin/main)" | sed -n '/^## commits/,$p')
expect_eq "--since: nothing after the commit touches the paths" "## commits on origin/main after $(git_in_checkout rev-parse origin/main) changing the paths
(none)" "$other_file_output"

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
bash "$task_claims" ABC-1 --repo acme/shop --since abc123 > /dev/null 2>&1
since_alone_status=$?
bash "$task_claims" ABC-1 --path > /dev/null 2>&1
bare_path_status=$?
set -e
expect_eq "usage: --since without --path exits 2" 2 "$since_alone_status"
expect_eq "usage: --path without a value exits 2" 2 "$bare_path_status"
expect_eq "usage: no key exits 2" 2 "$no_key_status"
expect_eq "usage: --repo without a value exits 2" 2 "$bare_repo_status"
expect_eq "a failing gh call exits 1" 1 "$gh_fail_status"
expect_contains "a failing gh call names the repository" "gh pr list --repo acme/unrouted failed" "$(cat "$work_dir/gh-fail.err")"

finish
