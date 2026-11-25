#!/usr/bin/env bash
# Tests scripts/check-report-findings.sh: a finding a gate confirmed must be in the review reply
# or on a Dropped: line, never silently missing.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
check="$(dirname "$tests_dir")/scripts/check-report-findings.sh"

verdicts=$work_dir/verdicts
mkdir -p "$verdicts"
cat > "$verdicts/naming.txt" <<'EOF'
STATUS: FAIL
BOXES:
- [FAIL] §N1: `tmp` is opaque
FINDINGS:
- 🟡 src/cart/total.ts:L4: `tmp` is opaque. Rename `total`.
- 🟠 src/orders/refund.ts:42@abc1234: the refund skips archived orders. Include them.

NOTES:
- 🟡 src/ignored.ts:9: not under FINDINGS.
EOF
cat > "$verdicts/testing.txt" <<'EOF'
STATUS: PASS
FINDINGS:
- none
EOF

# Runs the check on <reply>; prints its output, or "clean" when it passes.
result() {
  local output status=0
  output=$(printf '%s\n' "$1" | bash "$check" "$verdicts" -) || status=$?
  if [ "$status" -eq 0 ]; then echo clean; else printf '%s\n' "$output"; fi
}

missing=$(result "### Review: Add refunds")
expect_contains "a finding the reply never names is reported" "a gate found total.ts:4 and the reply neither reports it nor lists it under Dropped: with a reason" "$missing"
expect_contains "a finding with @sha is reported by basename and line" "a gate found refund.ts:42 and the reply" "$missing"
expect_eq "a line outside FINDINGS: is not a finding" 2 "$(printf '%s\n' "$missing" | wc -l | tr -d ' ')"

expect_eq "findings named as basename:Lline and basename:line are clean" clean \
  "$(result $'- 🟡 `total.ts:L4`: opaque name.\n- 🟠 `refund.ts:42`: skips archived orders.')"
expect_contains "a longer line number is not a match for a shorter one" "total.ts:4" \
  "$(result $'- 🟡 `total.ts:L44`: opaque name.\n- 🟠 refund.ts:42: skips archived orders.')"
expect_eq "findings listed under Dropped: are clean" clean \
  "$(result $'Dropped: total.ts:L4, refund.ts:42 (both already fixed in the next commit)')"
expect_eq "a Dropped: line may give the file and line apart" clean \
  "$(result $'Dropped: total.ts line 4 and refund.ts line 42, the author fixed both')"
expect_contains "a mention outside Dropped: with another line number is not enough" "refund.ts:42" \
  "$(result $'- 🟡 total.ts:L4: opaque.\nDropped: refund.ts line 7, not a bug')"

reply_file=$work_dir/reply.md
printf -- '- total.ts:L4 and refund.ts:42 reported\n' > "$reply_file"
status=0
bash "$check" "$verdicts" "$reply_file" > /dev/null || status=$?
expect_eq "a reply file works as well as stdin" 0 "$status"

status=0
bash "$check" "$work_dir/no-verdicts" "$reply_file" > /dev/null || status=$?
expect_eq "no verdicts directory: nothing to check" 0 "$status"
mkdir "$work_dir/empty-verdicts"
status=0
bash "$check" "$work_dir/empty-verdicts" "$reply_file" > /dev/null || status=$?
expect_eq "an empty verdicts directory: nothing to check" 0 "$status"

status=0
bash "$check" "$verdicts" "$work_dir/no-such-reply.md" > /dev/null 2>&1 || status=$?
expect_eq "an unreadable reply exits 2" 2 "$status"
status=0
bash "$check" > /dev/null 2>&1 || status=$?
expect_eq "no arguments exit 2" 2 "$status"

finish
