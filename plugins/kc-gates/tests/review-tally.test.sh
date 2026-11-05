#!/usr/bin/env bash
# Tests scripts/review-tally.sh: add records one line per PR (a repeat replaces it), report sums
# per month, and bad counts are refused.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
script="$(dirname "$tests_dir")/scripts/review-tally.sh"
export KC_READY_DIR="$work_dir/ready"

expect_eq "report with nothing tallied" "No reviews tallied yet." "$(bash "$script" report)"

bash "$script" add https://example.com/shop/pull/1 1 2 0
bash "$script" add https://example.com/shop/pull/2 0 1 1
bash "$script" add https://example.com/shop/pull/1 0 2 0
expect_eq "a repeat add replaces the PR's line" 2 "$(wc -l < "$KC_READY_DIR/tally.tsv" | tr -d ' ')"

month=$(date +%Y-%m)
expect_eq "report sums the month" "$(printf '%s\t2\t0\t3\t1' "$month")" "$(bash "$script" report | tail -1)"

status=0
bash "$script" add https://example.com/shop/pull/3 one 0 0 2>/dev/null || status=$?
expect_eq "a non-numeric count is refused" 2 "$status"

finish
