#!/usr/bin/env bash
# Tests scripts/verify-gate-receipts.sh: each case saves a round folder (review.diff,
# changed-files.txt, verdicts/) and expects one problem line per missing headline receipt, or the
# passing line when every trigger group the diff hits has its receipt.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
receipts="$(dirname "$tests_dir")/scripts/verify-gate-receipts.sh"

# new_round <changed file> <added line>: a round whose diff adds one line to one file.
new_round() {
  round="$work_dir/round-$RANDOM$RANDOM"
  mkdir -p "$round/verdicts"
  printf '%s\n' "$1" > "$round/changed-files.txt"
  printf 'diff --git a/%s b/%s\n--- a/%s\n+++ b/%s\n@@ -1 +1,2 @@\n old\n+%s\n' "$1" "$1" "$1" "$1" "$2" > "$round/review.diff"
}
set_gate() { printf '%b' "$2" > "$round/verdicts/$1.txt"; }
last_output=""
last_status=0
run_receipts() { last_status=0; last_output=$(bash "$receipts" "$round" 2>&1) || last_status=$?; }

new_round src/a.ts 'const ok = a && b;'
set_gate naming 'GATE: naming\nSTATUS: PASS\n'
run_receipts
expect_eq "boolean added, no receipt: exits 1" 1 "$last_status"
expect_contains "boolean added, no receipt: says" 'naming.txt: boolean logic added' "$last_output"
set_gate naming 'GATE: naming\nSTATUS: PASS\nBOXES:\n- [PASS] §N4: grepped &&/||: 1 hits: src/a.ts:2 named\n'
run_receipts
expect_eq "boolean added with receipt: exits 0" 0 "$last_status"
expect_contains "boolean added with receipt: says" '1 trigger group' "$last_output"

new_round src/a.ts 'const x = flag ? 1 : 2;'
set_gate clarity 'GATE: clarity\nSTATUS: PASS\n'
run_receipts
expect_contains "ternary added: asks for the ternary receipt" 'grepped ternaries' "$last_output"
set_gate clarity 'GATE: clarity\nSTATUS: PASS\nBOXES:\n- [PASS] §C4: grepped ternaries: 1 hit: src/a.ts:2\n'
run_receipts
expect_eq "ternary added with receipt: exits 0" 0 "$last_status"

new_round src/a.ts 'const x = y as Widget;'
set_gate clarity 'GATE: clarity\nSTATUS: PASS\n'
run_receipts
expect_contains "cast added: asks for the cast receipt" 'grepped as-casts' "$last_output"

new_round src/a.ts 'if (a) {} else if (b) {}'
set_gate structure 'GATE: structure\nSTATUS: PASS\n'
run_receipts
expect_contains "else-if added: asks for the chain receipt" 'grepped switch/else-if/IIFE' "$last_output"

new_round src/a.test.ts 'expect(a).toBe(1);'
set_gate testing 'GATE: testing\nSTATUS: PASS\nBOXES:\n- [PASS] §T2: grepped class assertions: 0 hits\n'
run_receipts
expect_contains "test file changed: asks for the loose-assertion receipt" 'grepped loose assertions' "$last_output"

new_round config/locales/en.json '"a": "A"'
set_gate i18n 'GATE: i18n\nSTATUS: PASS\n'
run_receipts
expect_contains "locale file changed: asks for the per-key table" 'locale files changed' "$last_output"
set_gate i18n 'GATE: i18n\nSTATUS: PASS\nBOXES:\n- [PASS] §I1: en.json:L2: a = "A" | namespace: ok, plural: n/a, dupe: none, naming: matches value\n'
run_receipts
expect_eq "locale file changed with a row: exits 0" 0 "$last_status"

new_round app/c.rb 'x = 1'
set_gate security 'GATE: security\nSTATUS: PASS\n'
run_receipts
expect_contains "security gate ran: asks for the request-surface receipt" 'grepped request surface' "$last_output"
set_gate security 'GATE: security\nSTATUS: PASS (N/A)\n'
run_receipts
expect_eq "security gate N/A: no receipt asked" 0 "$last_status"

new_round README.md 'prose only'
run_receipts
expect_eq "docs-only diff, no gate files: exits 0" 0 "$last_status"
expect_contains "docs-only diff: 0 groups" '0 trigger group' "$last_output"

run_status=0
bash "$receipts" >/dev/null 2>&1 || run_status=$?
expect_eq "no argument: usage error" 2 "$run_status"

[ "$failures" -eq 0 ] && echo "$passes passed"
exit "$failures"
