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
expect_contains "a hunk line whose text starts \"-- \" or \"++ \" is not read as a file header" "db/report.sql:1: total -> amount" "$output"
expect_contains "a hunk header with no line counts reads as one line each, and the path stays the file's" "db/report.sql:9: q -> qq" "$output"
expect_eq "nothing else is listed: a changed expression or literal, an added term, one name mapped two ways, a changed operator, an unequal run, a name and a literal trading places" 5 "$(printf '%s\n' "$output" | grep -c .)"
plain=$(bash "$script" "$tests_dir/fixtures/rename-only-lines/plain.diff")
expect_eq "with no diff --git lines, a header is read only once both line counts of the hunk before it are used up, a no-count hunk holding one line each" \
  "one.txt:1: alpha -> gamma"$'\n'"two.txt:4: x -> y" "$plain"
expect_eq "stdin works the same" "$output" "$(bash "$script" - < "$fixture")"

# The verification gate runs it from an install, where only the plugin's own path reaches it.
agent="$(dirname "$tests_dir")/agents/verification-gate.md"
# shellcheck disable=SC2016 # the literal ${CLAUDE_PLUGIN_ROOT} the agent file holds
expect_eq "every call in the verification gate names the script by its plugin path" \
  "$(grep -o 'rename-only-lines\.sh' "$agent" | wc -l | tr -d ' ')" \
  "$(grep -o '"${CLAUDE_PLUGIN_ROOT}/scripts/rename-only-lines\.sh"' "$agent" | wc -l | tr -d ' ')"

status=0
bash "$script" > /dev/null 2>&1 || status=$?
expect_eq "no argument exits 2" 2 "$status"
status=0
bash "$script" "$work_dir/missing.diff" > /dev/null 2>&1 || status=$?
expect_eq "an unreadable diff exits 2" 2 "$status"

finish
