#!/usr/bin/env bash
# Tests scripts/rename-only-lines.sh (verification §V9): a re-review delta mixing renamed lines
# with real changes lists only the renamed ones, on their new-side line numbers.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
script="$(dirname "$tests_dir")/scripts/rename-only-lines.sh"
fixture="$tests_dir/fixtures/rename-only-lines/delta.diff"

output=$(bash "$script" "$fixture")
expect_contains "a renamed declaration is listed on its new line" "src/orders/summary.ts:11: target -> store" "$output"
expect_contains "a line where the rename repeats is listed once with one mapping" "src/orders/summary.ts:12: target -> store" "$output"
expect_contains "a property swap is listed too" "src/orders/summary.ts:31: length -> size" "$output"
expect_eq "nothing else is listed: a changed expression or literal, an added term, one name mapped two ways, a changed operator, an unequal run" 3 "$(printf '%s\n' "$output" | grep -c .)"
expect_eq "stdin works the same" "$output" "$(bash "$script" - < "$fixture")"

status=0
bash "$script" > /dev/null 2>&1 || status=$?
expect_eq "no argument exits 2" 2 "$status"
status=0
bash "$script" "$work_dir/missing.diff" > /dev/null 2>&1 || status=$?
expect_eq "an unreadable diff exits 2" 2 "$status"

finish
