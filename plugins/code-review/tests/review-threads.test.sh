#!/usr/bin/env bash
# Tests scripts/review-threads.sh against the stub gh in lib/, answering from
# fixtures/review-threads/: two pages of comments (a thread split across them,
# a reply to a reply, an outdated thread, a file-level comment), with and
# without --mine, plus an empty PR and a missing jq.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
threads="$(dirname "$tests_dir")/scripts/review-threads.sh"
fixtures="$tests_dir/fixtures/review-threads"
require_jq
use_gh_fixtures "$fixtures"

bash "$threads" 12 > "$work_dir/plain.txt"
expect_file "threads grouped across pages, root first, replies in order" "$fixtures/expected-plain.txt" "$work_dir/plain.txt"

bash "$threads" 12 --mine reviewer > "$work_dir/mine.txt"
expect_file "--mine: started-by-you and author-replied-after-your-last" "$fixtures/expected-mine.txt" "$work_dir/mine.txt"
expect_eq "only read calls reached gh" "api --paginate repos/{owner}/{repo}/pulls/12/comments?per_page=100
api --paginate repos/{owner}/{repo}/pulls/12/comments?per_page=100
pr view 12 --json author" "$(cat "$KC_GH_LOG")"

expect_eq "no comments: summary only" "0 thread(s), 0 comment(s)" "$(bash "$threads" 13)"

# A PATH holding the stub gh and the basic tools, but no jq.
no_jq_bin="$work_dir/no-jq-bin"
mkdir -p "$no_jq_bin"
for tool in bash basename; do ln -s "$(command -v "$tool")" "$no_jq_bin/$tool"; done
ln -s "$tests_dir/lib/gh" "$no_jq_bin/gh"
set +e
no_jq_output=$(PATH="$no_jq_bin" bash "$threads" 12 2>&1)
no_jq_status=$?
bash "$threads" > /dev/null 2>&1
no_args_status=$?
bash "$threads" 12 --mine > /dev/null 2>&1
mine_without_login_status=$?
set -e
expect_eq "missing jq: exits 1" 1 "$no_jq_status"
expect_contains "missing jq: says so" "jq is required" "$no_jq_output"
expect_eq "usage: no arguments exits 2" 2 "$no_args_status"
expect_eq "usage: --mine without a login exits 2" 2 "$mine_without_login_status"

finish
