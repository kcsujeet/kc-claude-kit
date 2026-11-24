#!/usr/bin/env bash
# Tests scripts/check-review-report.sh (§G6): a report must lead with a does-it-work section
# before the gate table, holding a measurement or "not measured:" and a uses line, and every
# naming or clarity finding must end with (non-blocking). Other gates' findings are untouched.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
check="$(dirname "$tests_dir")/scripts/check-review-report.sh"

# Runs the check on <report>, passing it as a file; prints the exit code, output in last-output.
run_check() {
  printf '%s\n' "$1" > "$work_dir/report.md"
  local code=0
  bash "$check" "$work_dir/report.md" > "$work_dir/last-output" 2>&1 || code=$?
  echo "$code"
}

head_lines=$'### Review: Add free shipping\n**Head:** `abc1234` · **Verdict:** ❌ FAILED (1 gate failing)\n'
works=$'**Does it work / what can it break**\n- Measured: checkout query before 420 ms -> after 38 ms (1,000 orders); orders spec 48 passed.\n- Uses: 4 traced, 3 run in the orders spec, 1 read.\n'
table=$'\n**Gate status:**\n| Gate | Status |\n|------|--------|\n| naming | ❌ FAIL |\n'
labeled=$'\n**Naming:**\n- 🟡 `cart.ts:L4`: `tmp` is opaque. Rename `freeShippingTotal`. (non-blocking)\n- 🟡 `cart.ts:L9`: `d` is opaque. Rename `discount`. (non-blocking) (fails safe)\n\n**Correctness:**\n- 🔴 `cart.ts:L20`: total can go negative. Clamp at 0.\n'
good="$head_lines$works$table$labeled"

expect_eq "§G6 a report that leads with the section and labels style findings passes" 0 "$(run_check "$good")"

no_section="$head_lines$table$labeled"
expect_eq "§G6 no section is reported" 1 "$(run_check "$no_section")"
expect_contains "the problem names the missing section" 'no `**Does it work' "$(cat "$work_dir/last-output")"

late="$head_lines$table$works$labeled"
expect_eq "§G6 a section after the gate table is reported" 1 "$(run_check "$late")"
expect_contains "the problem says to move it above the table" "comes after the gate table" "$(cat "$work_dir/last-output")"

unmeasured=$'**Does it work / what can it break**\n- Measured: it is faster.\n- Uses: 4 traced, 3 run, 1 read.\n'
expect_eq "§G6 a section with no numbers and no not-measured line is reported" 1 "$(run_check "$head_lines$unmeasured$table$labeled")"
expect_contains "the problem names the missing measurement" "no measurement" "$(cat "$work_dir/last-output")"

not_measured=$'**Does it work / what can it break**\n- not measured: the change is a rename, no behaviour moved.\n- Uses: 2 traced, 2 read.\n'
expect_eq "§G6 a not-measured line with its reason passes" 0 "$(run_check "$head_lines$not_measured$table$labeled")"

arrow=$'**Does it work / what can it break**\n- Bundle size 120 KB -> 118 KB.\n- Blast radius: 3 uses traced, all 3 checked.\n'
expect_eq "§G6 an arrow with numbers and a Blast radius line pass" 0 "$(run_check "$head_lines$arrow$table$labeled")"

no_uses=$'**Does it work / what can it break**\n- Measured: before 420 ms, after 38 ms.\n'
expect_eq "§G6 a section with no uses line is reported" 1 "$(run_check "$head_lines$no_uses$table$labeled")"
expect_contains "the problem names the missing uses line" "line with the trace-uses.sh count" "$(cat "$work_dir/last-output")"

unlabeled=$'\n**Naming:**\n- 🟡 `cart.ts:L4`: `tmp` is opaque. Rename `freeShippingTotal`.\n\n**Clarity:**\n- 🟠 `cart.ts:L7`: nested ternary. Use an early return. (non-blocking)\n- 🟡 `cart.ts:L8`: dense chain. Split it.\n'
expect_eq "§G6 naming and clarity findings without the label are reported" 1 "$(run_check "$head_lines$works$table$unlabeled")"
expect_contains "the problem names the naming finding" "without (non-blocking) at its end: - 🟡" "$(cat "$work_dir/last-output")"
expect_contains "the problem names the clarity finding" "cart.ts:L8" "$(cat "$work_dir/last-output")"
expect_not_contains "a labeled finding is not reported" "L7" "$(cat "$work_dir/last-output")"

expect_eq "§G6 a clarity-only unlabeled finding is reported" 1 "$(run_check "$head_lines$works$table"$'\n**Clarity:**\n- 🟡 `a.ts:L1`: dense. Split.\n')"

stdin_code=0
printf '%s\n' "$good" | bash "$check" - > "$work_dir/last-output" 2>&1 || stdin_code=$?
expect_eq "§G6 stdin is read with -" 0 "$stdin_code"
stdin_code=0
printf '%s\n' "$no_section" | bash "$check" - > "$work_dir/last-output" 2>&1 || stdin_code=$?
expect_eq "§G6 stdin problems exit 1" 1 "$stdin_code"

usage_code=0
bash "$check" > /dev/null 2>&1 || usage_code=$?
expect_eq "no argument is a usage error" 2 "$usage_code"
usage_code=0
bash "$check" "$work_dir/missing.md" > /dev/null 2>&1 || usage_code=$?
expect_eq "an unreadable file is a usage error" 2 "$usage_code"

finish
