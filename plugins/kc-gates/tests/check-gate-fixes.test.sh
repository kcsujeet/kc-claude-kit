#!/usr/bin/env bash
# Tests scripts/check-gate-fixes.sh against gate verdict blocks written in a scratch directory.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
check="$(dirname "$tests_dir")/scripts/check-gate-fixes.sh"

verdicts="$work_dir/verdicts"
mkdir -p "$verdicts"
cat > "$verdicts/naming.txt" <<'EOF'
GATE: naming
STATUS: FAIL
BOXES:
- [FAIL] §N1: src/cart.ts:4 `data`
FINDINGS:
- 🟡 src/cart.ts:4: `data` says nothing. Rename to `openOrders`.
EDIT src/cart.ts
<<<<<<< SEARCH
const data = orders.filter(isOpen)
======= REPLACE
const openOrders = orders.filter(isOpen)
>>>>>>> END
EOF
cat > "$verdicts/correctness.txt" <<'EOF'
GATE: correctness
STATUS: FAIL
BOXES:
- [FAIL] §B2: src/total.ts:8 empty cart
FINDINGS:
- 🟠 src/total.ts:8: an empty cart divides by zero. FIX: an empty cart shows a total of 0.
EDIT src/total.ts
<<<<<<< SEARCH
  return sum / items.length
======= REPLACE
  if (items.length === 0) {
    return 0
  }
  return sum / items.length
>>>>>>> END
- 🟠 src/total.ts:12: a null price is read as 0. FIX: a null price is left out of the average.
EDIT src/total.ts
<<<<<<< SEARCH
  const price = item.price
======= REPLACE
  const price = item.price ?? skip()
>>>>>>> END
- 🟡 src/old.ts:1: unused. Delete it.
DELETE src/old.ts
EOF
cat > "$verdicts/structure.txt" <<'EOF'
GATE: structure
STATUS: FAIL
FINDINGS:
- 🟡 src/cart.ts:20: helper belongs in its own module.
CREATE src/cart/visible.ts
<<<<<<< CONTENT
export const visibleItems = (cart) => cart.items.filter((item) => !item.archived)
>>>>>>> END
MOVE src/util.ts src/cart/util.ts
EDIT src/cart.ts
<<<<<<< SEARCH
  const label = isGift ? giftLabel : plainLabel
  const unused = 1
======= REPLACE
  const label = isGift ? giftLabel : plainLabel
>>>>>>> END
EOF

out=$(bash "$check" "$verdicts")
expect_contains "a rename is applied as written" "apply naming: EDIT src/cart.ts" "$out"
expect_contains "a deleted file is applied as written" "apply correctness: DELETE src/old.ts" "$out"
expect_contains "a moved file is applied as written" "apply structure: MOVE src/util.ts src/cart/util.ts" "$out"
expect_contains "a deleted line beside a condition it keeps is applied" "apply structure: EDIT src/cart.ts" "$out"
expect_contains "more than two replacement lines are the caller's to write" "write correctness: EDIT src/total.ts: 4 replacement lines" "$out"
expect_contains "a short edit that adds a condition is the caller's to write" "write correctness: EDIT src/total.ts: adds a condition" "$out"
expect_contains "a new file is the caller's to write" "write structure: CREATE src/cart/visible.ts: a new file" "$out"
expect_eq "the summary counts both" "edits: 4 to apply, 3 to write from the finding" "$(printf '%s\n' "$out" | tail -1)"

empty="$work_dir/empty"
mkdir -p "$empty"
expect_eq "no blocks: nothing to apply or write" "edits: 0 to apply, 0 to write from the finding" "$(bash "$check" "$empty")"

status=0
bash "$check" >/dev/null 2>&1 || status=$?
expect_eq "no argument: exit 2" 2 "$status"
status=0
bash "$check" "$work_dir/missing" >/dev/null 2>&1 || status=$?
expect_eq "a missing folder: exit 2" 2 "$status"

finish
