#!/usr/bin/env bash
# Tests scripts/check-walk-receipt.sh: every walk-item needs a receipt line with something seen and
# evidence that is an existing capture or a request with its status.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
walk_receipt_checker="$(dirname "$tests_dir")/scripts/check-walk-receipt.sh"

select_output=$work_dir/select.txt
printf 'GATES=naming\nWALK=required\nwalk: x\nwalk-item: app/models/order.rb\nwalk-item: src/cart/total.ts\n' > "$select_output"
printf 'png' > "$work_dir/total.png"
receipt=$work_dir/walk-receipt.tsv

# Runs the checker; prints its output, or "clean" when it passes.
run_walk_receipt_check() {
  local output status=0
  output=$(bash "$walk_receipt_checker" "$select_output" "$receipt") || status=$?
  if [ "$status" -eq 0 ]; then echo clean; else printf '%s\n' "$output"; fi
}

printf 'app/models/order.rb\tcreated an order with a free item, total 0\tPOST /orders 201\nsrc/cart/total.ts\tcart page shows 2 items\t%s\n' "$work_dir/total.png" > "$receipt"
expect_eq "§V11: a full receipt passes" clean "$(run_walk_receipt_check)"

printf 'app/models/order.rb\tcreated an order\tPOST /orders 201\n' > "$receipt"
missing=$(run_walk_receipt_check)
expect_contains "§V11: an item with no receipt line fails" "walk-item src/cart/total.ts: no receipt line" "$missing"
expect_eq "only the missing item is listed" 1 "$(printf '%s\n' "$missing" | grep -c '^walk-item')"

rm -f "$receipt"
expect_contains "§V11: no receipt file fails every item" "walk-item app/models/order.rb: no receipt line" "$(run_walk_receipt_check)"

printf 'app/models/order.rb\t\tPOST /orders 201\nsrc/cart/total.ts\t  \t%s\n' "$work_dir/total.png" > "$receipt"
empty_seen=$(run_walk_receipt_check)
expect_contains "an empty seen fails" "walk-item app/models/order.rb: nothing seen" "$empty_seen"
expect_contains "a blank seen fails" "walk-item src/cart/total.ts: nothing seen" "$empty_seen"

printf 'app/models/order.rb\tcreated an order\tlooked fine\nsrc/cart/total.ts\tcart page\t%s\n' "$work_dir/gone.png" > "$receipt"
bad_evidence=$(run_walk_receipt_check)
expect_contains "evidence that is prose fails" "walk-item app/models/order.rb: evidence is neither" "$bad_evidence"
expect_contains "a capture that does not exist fails" "walk-item src/cart/total.ts: evidence file does not exist" "$bad_evidence"

printf 'app/models/order.rb\tcreated an order\tPOST /orders\nsrc/cart/total.ts\tcart page\t%s\n' "$work_dir/total.png" > "$receipt"
expect_contains "a request line with no status fails" "walk-item app/models/order.rb: evidence is neither" "$(run_walk_receipt_check)"

printf 'app/models/order.rb\tcreated an order\tPOST /orders 201\nsrc/cart/total.ts\tcart page\ttotal.png\n' > "$receipt"
expect_eq "a relative capture path is read from the receipt's folder" clean "$(run_walk_receipt_check)"

printf 'app/models/order.rb\tcreated an order\tPOST /orders 201\nsrc/cart/total.ts\tcart page\t%s\n' "$work_dir/total.webm" > "$receipt"
printf 'webm' > "$work_dir/total.webm"
expect_eq "a recording in the shared capture formats (webm) is evidence" clean "$(run_walk_receipt_check)"

printf 'GATES=naming\nWALK=not-required\nwalk: no non-test source file in the diff\n' > "$select_output"
rm -f "$receipt"
expect_eq "no walk-item lines: nothing to walk, passes with no receipt" clean "$(run_walk_receipt_check)"

status=0
bash "$walk_receipt_checker" > /dev/null 2>&1 || status=$?
expect_eq "usage error exits 2" 2 "$status"

status=0
unreadable=$(bash "$walk_receipt_checker" "$work_dir/no-such-select.txt" "$receipt" 2>&1) || status=$?
expect_eq "an unreadable select-gates file exits 2" 2 "$status"
expect_contains "it says which file it cannot read" "check-walk-receipt.sh: cannot read $work_dir/no-such-select.txt" "$unreadable"

# A blank `walk-item:` line names no file to walk.
printf 'WALK=required\nwalk-item: \n' > "$select_output"
rm -f "$receipt"
expect_eq "a blank walk-item line is not an item" clean "$(run_walk_receipt_check)"

finish
