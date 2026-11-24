#!/usr/bin/env bash
# Tests skills/kc-investigate/scripts/check-investigation.sh: a write-up passes only when §INV1 to
# §INV9 are each ticked once with evidence (or a reasoned n/a where allowed) and §INV9's cause table
# gives every row a verdict that cites a box or names a probe.
set -u

tests_dir=$(cd "$(dirname "$0")" && pwd)
plugin_dir=$(dirname "$tests_dir")
checker="$plugin_dir/skills/kc-investigate/scripts/check-investigation.sh"
skill="$plugin_dir/skills/kc-investigate/SKILL.md"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

failures=0
passes=0

# The skill's own example write-up, the passing base every case edits.
awk '/^```markdown$/ { inside = 1; next } inside && /^```$/ { exit } inside' "$skill" > "$work_dir/base.md"

# expect <pass|fail> <label> <file> [<text the output must hold>]
expect() {
  local expectation=$1 label=$2 write_up=$3 needle=${4:-} output status verdict
  output=$(bash "$checker" "$write_up" 2>&1)
  status=$?
  verdict=fail
  [ "$status" -eq 0 ] && verdict=pass
  if [ "$verdict" = "$expectation" ] && { [ -z "$needle" ] || printf '%s' "$output" | grep -qF -- "$needle"; }; then
    echo "ok   $label"
    passes=$((passes + 1))
  else
    echo "FAIL $label (expected $expectation, got status $status)"
    printf '%s\n' "$output" | sed 's/^/     /'
    failures=$((failures + 1))
  fi
}

# variant <name> <sed expression>: the base write-up with one edit.
variant() { sed -E "$2" "$work_dir/base.md" > "$work_dir/$1.md"; printf '%s' "$work_dir/$1.md"; }

expect pass "§INV1-§INV9: the skill's example write-up passes" "$work_dir/base.md"
for box in §INV1 §INV2 §INV3 §INV4 §INV5 §INV6 §INV7 §INV8 §INV9; do
  expect fail "$box: a missing box fails" "$(variant "missing-${box#§}" "/- \[x\] $box /d")" "$box: missing"
done
expect fail "§INV2: an unticked box fails" "$(variant unticked 's/- \[x\] §INV2/- [ ] §INV2/')" "§INV2: the box is not ticked"
expect fail "§INV4: a box with no evidence fails" "$(variant no-evidence 's/^- \[x\] §INV4 .*/- [x] §INV4 failures nearby: looked, nothing odd/')" "§INV4: no evidence"
expect pass "§INV6: a reasoned n/a passes" "$(variant na-ok 's/^- \[x\] §INV6 .*/- [x] §INV6 n\/a: nothing measured through a library hook/')"
expect fail "§INV6: an n/a with no reason fails" "$(variant na-short 's/^- \[x\] §INV6 .*/- [x] §INV6 n\/a: none/')" "§INV6: n/a needs a reason"
expect fail "§INV1: n/a is not allowed for hops" "$(variant na-hops 's/^- \[x\] §INV1 .*/- [x] §INV1 n\/a: we already know the slow hop/')" "§INV1: n/a is not allowed"
expect fail "§INV9: a cause ruled out citing no box fails" "$(variant out-no-box 's/^\| slow enqueue \| .*/| slow enqueue | out: obviously fast |/')" 'cause "slow enqueue" is ruled out without citing a box'
expect fail "§INV9: an open cause with no probe fails" "$(variant open-no-probe 's/^\| worker capacity \| .*/| worker capacity | open |/')" 'cause "worker capacity" is open without naming the probe'
expect fail "§INV9: a row with no verdict fails" "$(variant no-verdict 's/^\| payload size \| .*/| payload size | likely |/')" 'cause "payload size" has no verdict'
expect fail "§INV9: a box with no table after it fails" "$(variant no-table '/^\|/d')" "§INV9: no cause table"
expect fail "§INV3: a box listed twice fails" "$(variant twice '/^- \[x\] §INV3 /p')" "§INV3: listed 2 times"

set +e
bash "$checker" > /dev/null 2>&1
usage_status=$?
set -e
if [ "$usage_status" -eq 2 ]; then echo "ok   usage: no argument exits 2"; passes=$((passes + 1)); else echo "FAIL usage: exit $usage_status"; failures=$((failures + 1)); fi

echo "$passes passed, $failures failed"
[ "$failures" -eq 0 ]
