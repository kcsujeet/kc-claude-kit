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

# expect_investigation_verdict <pass|fail> <label> <file> [<text the output must hold>]
expect_investigation_verdict() {
  local expectation=$1 label=$2 write_up=$3 needle=${4:-} output status verdict
  output=$(bash "$checker" "$write_up" 2>&1)
  status=$?
  verdict=fail
  [ "$status" -eq 0 ] && verdict=pass
  local is_expected_verdict=false has_expected_text=false
  [ "$verdict" = "$expectation" ] && is_expected_verdict=true
  if [ -z "$needle" ] || printf '%s' "$output" | grep -qF -- "$needle"; then has_expected_text=true; fi
  if [ "$is_expected_verdict" = true ] && [ "$has_expected_text" = true ]; then
    echo "ok   $label"
    passes=$((passes + 1))
  else
    echo "FAIL $label (expected $expectation, got status $status)"
    printf '%s\n' "$output" | sed 's/^/     /'
    failures=$((failures + 1))
  fi
}

# write_variant <name> <sed expression>: the base write-up with one edit.
write_variant() { sed -E "$2" "$work_dir/base.md" > "$work_dir/$1.md"; printf '%s' "$work_dir/$1.md"; }

expect_investigation_verdict pass "§INV1-§INV9: the skill's example write-up passes" "$work_dir/base.md"
for box in §INV1 §INV2 §INV3 §INV4 §INV5 §INV6 §INV7 §INV8 §INV9; do
  expect_investigation_verdict fail "$box: a missing box fails" "$(write_variant "missing-${box#§}" "/- \[x\] $box /d")" "$box: missing"
done
expect_investigation_verdict fail "§INV2: an unticked box fails" "$(write_variant unticked 's/- \[x\] §INV2/- [ ] §INV2/')" "§INV2: the box is not ticked"
expect_investigation_verdict fail "§INV4: a box with no evidence fails" "$(write_variant no-evidence 's/^- \[x\] §INV4 .*/- [x] §INV4 failures nearby: looked, nothing odd/')" "§INV4: no evidence"
expect_investigation_verdict pass "§INV6: a reasoned n/a passes" "$(write_variant na-ok 's/^- \[x\] §INV6 .*/- [x] §INV6 n\/a: nothing measured through a library hook/')"
expect_investigation_verdict fail "§INV6: an n/a with no reason fails" "$(write_variant na-short 's/^- \[x\] §INV6 .*/- [x] §INV6 n\/a: none/')" "§INV6: n/a needs a reason"
expect_investigation_verdict fail "§INV1: n/a is not allowed for hops" "$(write_variant na-hops 's/^- \[x\] §INV1 .*/- [x] §INV1 n\/a: we already know the slow hop/')" "§INV1: n/a is not allowed"
expect_investigation_verdict fail "§INV9: a cause ruled out citing no box fails" "$(write_variant out-no-box 's/^\| slow enqueue \| .*/| slow enqueue | out: obviously fast |/')" 'cause "slow enqueue" is ruled out without citing a box'
expect_investigation_verdict fail "§INV9: a cause ruled in citing no box fails" "$(write_variant in-no-box 's/^\| payload size \| .*/| payload size | in: clearly |/')" 'cause "payload size" is ruled in without citing a box'
expect_investigation_verdict fail "§INV9: an open cause with no probe fails" "$(write_variant open-no-probe 's/^\| worker capacity \| .*/| worker capacity | open |/')" 'cause "worker capacity" is open without naming the probe'
expect_investigation_verdict fail "§INV9: a row with no verdict fails" "$(write_variant no-verdict 's/^\| payload size \| .*/| payload size | likely |/')" 'cause "payload size" has no verdict'
expect_investigation_verdict fail "§INV9: a box with no table after it fails" "$(write_variant no-table '/^\|/d')" "§INV9: no cause table"
expect_investigation_verdict fail "§INV3: a box listed twice fails" "$(write_variant twice '/^- \[x\] §INV3 /p')" "§INV3: listed 2 times"

set +e
unreadable_output=$(bash "$checker" "$work_dir/none.md" 2>&1)
unreadable_status=$?
set -e
if [ "$unreadable_status" -eq 2 ] && printf '%s' "$unreadable_output" | grep -qF 'cannot read'; then
  echo "ok   usage: an unreadable write-up exits 2"; passes=$((passes + 1))
else
  echo "FAIL usage: unreadable write-up gave $unreadable_status: $unreadable_output"; failures=$((failures + 1))
fi
set +e
bash "$checker" > /dev/null 2>&1
usage_status=$?
set -e
if [ "$usage_status" -eq 2 ]; then echo "ok   usage: no argument exits 2"; passes=$((passes + 1)); else echo "FAIL usage: exit $usage_status"; failures=$((failures + 1)); fi

echo "$passes passed, $failures failed"
[ "$failures" -eq 0 ]
