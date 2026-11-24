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
expect_eq "--path: a leading ./ is dropped, so the path still matches" "#52" "$(bash "$task_claims" ABC-1 --repo acme/shop --path ./src/storefront/Header.tsx | grep '^#52' | cut -d' ' -f1)"
expect_contains "--path: only open pull requests are asked for" "--state open" "$(grep 'json number,author' "$KC_GH_LOG" | tail -1)"

# The limits gh has: 100 pull requests per call, 100 files per pull request. Routes for them are added to a copy of the fixtures.
limit_fixtures="$work_dir/limit-fixtures"
cp -R "$tests_dir/fixtures/task-claims" "$limit_fixtures"
jq -n '[range(100) | {number: (200 + .), author: {login: "dave"}, headRefName: "ABC-9-\(.)", title: "Other work \(.)", files: [{path: "src/other/\(.).ts"}]}]' > "$limit_fixtures/pr-files-full-scan.json"
jq -n '[{number: 300, author: {login: "erin"}, headRefName: "ABC-8-rename", title: "ABC-8: Move shared code", files: [range(100) | {path: "src/moved/\(.).ts"}]}, {number: 301, author: {login: "frank"}, headRefName: "ABC-7-small", title: "ABC-7: Small", files: [{path: "src/other/a.ts"}]}]' > "$limit_fixtures/pr-files-wide.json"
printf '%s\t%s\n' \
  "pr list --repo acme/full --state all --search \"ABC-1\" in:title,body --limit 50 --json number,state,author,headRefName,title" pr-list-empty.json \
  "pr list --repo acme/wide --state all --search \"ABC-1\" in:title,body --limit 50 --json number,state,author,headRefName,title" pr-list-empty.json \
  "pr list --repo acme/full --state open --limit 100 --json number,author,headRefName,title,files" pr-files-full-scan.json \
  "pr list --repo acme/wide --state open --limit 100 --json number,author,headRefName,title,files" pr-files-wide.json >> "$limit_fixtures/routes.tsv"
full_scan=$(KC_GH_ROUTES="$limit_fixtures/routes.tsv" bash "$task_claims" ABC-1 --repo acme/full --path src/storefront/Header.tsx | sed -n '/^## acme\/full: open/,$p')
expect_eq "--path: a scan that returned 100 pull requests says older ones were not checked, instead of (none)" "## acme/full: open pull requests changing the paths
(scan stopped at 100 open pull requests: older ones were not checked)" "$full_scan"
wide=$(KC_GH_ROUTES="$limit_fixtures/routes.tsv" bash "$task_claims" ABC-1 --repo acme/wide --path src/storefront/Header.tsx | sed -n '/^## acme\/wide: open/,$p')
expect_eq "--path: a pull request listing 100 files that match no path is marked, not skipped; one with fewer is not" "## acme/wide: open pull requests changing the paths
#300 @erin ABC-8-rename: ABC-8: Move shared code [files list may be cut off]" "$wide"

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

# A glob is taken literally, as the open pull request half takes it: it must not list commits the other half could not find.
glob_output=$(cd "$checkout" && bash "$task_claims" ABC-1 --repo acme/shop --path 'src/*.tsx' --since "$base_sha" | sed -n '/^## commits/,$p')
expect_eq "--since: a glob is a literal path, so it matches no commit" "## commits on origin/main after $base_sha changing the paths
(none)" "$glob_output"
# A remote whose HEAD names no branch leaves the checkout without origin/HEAD even after a fetch: the default branch is then read as origin/main.
git -C "$origin_repo" symbolic-ref HEAD refs/heads/unborn
git_in_checkout remote set-head origin --delete
no_head_output=$(cd "$checkout" && bash "$task_claims" ABC-1 --repo acme/shop --path src/Header.tsx --since "$base_sha" | sed -n '/^## commits/,$p')
expect_eq "--since: without origin/HEAD the default branch is origin/main" "## commits on origin/main after $base_sha changing the paths
$(git_in_checkout log -1 --format='%h dev %s' --grep='Rewrite the header' origin/main)" "$no_head_output"

# --deleting, on a throwaway repo where the configured user added one file and another author added one.
cleanup_repo="$work_dir/cleanup"
git init --quiet --initial-branch=main "$cleanup_repo"
git -C "$cleanup_repo" config user.email dev@example.com
git -C "$cleanup_repo" config user.name dev
mkdir -p "$cleanup_repo/tasks"
echo a > "$cleanup_repo/tasks/mine.rb"
git -C "$cleanup_repo" add -A
git -C "$cleanup_repo" commit --quiet -m "Add mine"
echo b > "$cleanup_repo/tasks/theirs.rb"
git -C "$cleanup_repo" add -A
git -C "$cleanup_repo" -c user.email=other@example.com -c user.name=other commit --quiet -m "Add theirs"
echo changed >> "$cleanup_repo/tasks/mine.rb"
git -C "$cleanup_repo" -c user.email=other@example.com commit --quiet -am "Another author edits mine"
deleting_two_files=$(cd "$cleanup_repo" && bash "$task_claims" ABC-1 --repo acme/shop --deleting tasks/mine.rb --deleting tasks/theirs.rb | sed -n '/^## files to delete/,$p')
expect_eq "--deleting: a file the configured user added is mine, one another author added is NOT YOURS" "## files to delete, by who added them
tasks/mine.rb dev@example.com mine
tasks/theirs.rb other@example.com NOT YOURS" "$deleting_two_files"
deleting_dir=$(cd "$cleanup_repo" && bash "$task_claims" ABC-1 --repo acme/shop --deleting tasks/ | sed -n '/^## files to delete/,$p')
expect_eq "--deleting: a directory expands to its files, and a later edit by another author does not change who added a file" "## files to delete, by who added them
tasks/mine.rb dev@example.com mine
tasks/theirs.rb other@example.com NOT YOURS" "$deleting_dir"
expect_eq "--deleting: without it the output has no deletion section" "$two_repos" "$(cd "$cleanup_repo" && bash "$task_claims" ABC-1 --repo acme/shop --repo acme/shop-api)"
expect_contains "--deleting: a path with no tracked files is listed as NOT YOURS" "tasks/gone.rb (no tracked files) NOT YOURS" "$(cd "$cleanup_repo" && bash "$task_claims" ABC-1 --repo acme/shop --deleting tasks/gone.rb)"

echo c > "$cleanup_repo/tasks/staged.rb"
git -C "$cleanup_repo" add tasks/staged.rb
expect_contains "--deleting: a staged file with no commit has no adder and is NOT YOURS" "tasks/staged.rb unknown NOT YOURS" "$(cd "$cleanup_repo" && bash "$task_claims" ABC-1 --repo acme/shop --deleting tasks/staged.rb)"
git -C "$cleanup_repo" reset --quiet tasks/staged.rb
rm "$cleanup_repo/tasks/staged.rb"

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
bash "$task_claims" ABC-1 --repo acme/shop --path src/Header.tsx --since "" > /dev/null 2>&1
empty_since_status=$?
bash "$task_claims" ABC-1 --deleting > /dev/null 2>&1
bare_deleting_status=$?
set -e
expect_eq "usage: --since without --path exits 2" 2 "$since_alone_status"
expect_eq "usage: --path without a value exits 2" 2 "$bare_path_status"
expect_eq "usage: --since with an empty value exits 2, so the commit check is never skipped silently" 2 "$empty_since_status"
expect_eq "usage: --deleting without a value exits 2" 2 "$bare_deleting_status"
expect_eq "usage: no key exits 2" 2 "$no_key_status"
expect_eq "usage: --repo without a value exits 2" 2 "$bare_repo_status"
expect_eq "a failing gh call exits 1" 1 "$gh_fail_status"
expect_contains "a failing gh call names the repository" "gh pr list --repo acme/unrouted failed" "$(cat "$work_dir/gh-fail.err")"

finish
