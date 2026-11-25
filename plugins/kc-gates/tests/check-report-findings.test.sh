#!/usr/bin/env bash
# Tests scripts/check-report-findings.sh: a finding a gate confirmed must be in the review reply
# or on a Dropped: line, never silently missing.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
check_report_findings_script="$(dirname "$tests_dir")/scripts/check-report-findings.sh"

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
get_check_output() {
  local output status=0
  output=$(printf '%s\n' "$1" | bash "$check_report_findings_script" "$verdicts" -) || status=$?
  if [ "$status" -eq 0 ]; then echo clean; else printf '%s\n' "$output"; fi
}

missing_findings_report=$(get_check_output "### Review: Add refunds")
expect_contains "a finding the reply never names is reported" "a gate found total.ts:4 and the reply neither reports it nor lists it under Dropped: with a reason" "$missing_findings_report"
expect_contains "a finding with @sha is reported by basename and line" "a gate found refund.ts:42 and the reply" "$missing_findings_report"
expect_eq "a line outside FINDINGS: is not a finding" 2 "$(printf '%s\n' "$missing_findings_report" | wc -l | tr -d ' ')"

expect_eq "findings named as basename:Lline and basename:line are clean" clean \
  "$(get_check_output $'- 🟡 `total.ts:L4`: opaque name.\n- 🟠 `refund.ts:42`: skips archived orders.')"
expect_contains "a longer line number is not a match for a shorter one" "total.ts:4" \
  "$(get_check_output $'- 🟡 `total.ts:L44`: opaque name.\n- 🟠 refund.ts:42: skips archived orders.')"
expect_eq "findings listed under Dropped: are clean" clean \
  "$(get_check_output $'Dropped: total.ts:L4, refund.ts:42 (both already fixed in the next commit)')"
expect_eq "a Dropped: line may give the file and line apart" clean \
  "$(get_check_output $'Dropped: total.ts line 4 and refund.ts line 42, the author fixed both')"
expect_contains "a mention outside Dropped: with another line number is not enough" "refund.ts:42" \
  "$(get_check_output $'- 🟡 total.ts:L4: opaque.\nDropped: refund.ts line 7, not a bug')"

# A Dropped: line counts only when it names the finding as file:line (or file line N) and gives a reason.
expect_contains "Dropped: with the file and line but no reason does not count" "total.ts:4" \
  "$(get_check_output $'Dropped: total.ts:4\n- refund.ts:42 reported')"
expect_contains "Dropped: with the file but no line (a number in the reason) does not count" "total.ts:4" \
  "$(get_check_output $'Dropped: total.ts (ran 4 tests)\n- refund.ts:42 reported')"
expect_eq "Dropped: with file:line and a reason counts" clean \
  "$(get_check_output $'Dropped: total.ts:4 not reachable from checkout\n- refund.ts:42 reported')"
expect_contains "Dropped: listing two findings with no reason counts for neither" "refund.ts:42" \
  "$(get_check_output $'Dropped: total.ts:4, refund.ts:42')"

# A large reply that names the findings early must not hit SIGPIPE when grep stops reading.
large_filler=$(head -c 300000 /dev/zero | tr '\0' 'x')
expect_eq "a 300KB reply that names the findings early is clean" clean \
  "$(get_check_output "- total.ts:L4 and refund.ts:42 reported"$'\n'"$large_filler")"

reply_file=$work_dir/reply.md
printf -- '- total.ts:L4 and refund.ts:42 reported\n' > "$reply_file"
status=0
bash "$check_report_findings_script" "$verdicts" "$reply_file" > /dev/null || status=$?
expect_eq "a reply file works as well as stdin" 0 "$status"

status=0
bash "$check_report_findings_script" "$work_dir/no-verdicts" "$reply_file" > /dev/null || status=$?
expect_eq "no verdicts directory: nothing to check" 0 "$status"
mkdir "$work_dir/empty-verdicts"
status=0
bash "$check_report_findings_script" "$work_dir/empty-verdicts" "$reply_file" > /dev/null || status=$?
expect_eq "an empty verdicts directory: nothing to check" 0 "$status"

status=0
bash "$check_report_findings_script" "$verdicts" "$work_dir/no-such-reply.md" > /dev/null 2>&1 || status=$?
expect_eq "an unreadable reply exits 2" 2 "$status"
status=0
bash "$check_report_findings_script" > /dev/null 2>&1 || status=$?
expect_eq "no arguments exit 2" 2 "$status"

finish
