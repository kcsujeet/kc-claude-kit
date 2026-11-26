#!/usr/bin/env bash
# Tests skills/kc-shape-the-change/scripts/check-shape.sh (§SH1 to §SH8): the template in the skill
# passes; each box removed, unticked or left short fails; fewer than two shapes, a pick that names
# no shape or gives no reason, a flag line missing a field, a decided-by naming the agent, a yes
# flag justified by a data or deploy gap only, a failure line with no signal and an approval with
# no quoted words each fail; a flag that also names a product rollout passes; the one-line trivial
# declaration passes and fails without any of its three phrases or its reason.
set -u

tests_dir=$(cd "$(dirname "$0")" && pwd)
plugin_dir=$(dirname "$tests_dir")
checker="$plugin_dir/skills/kc-shape-the-change/scripts/check-shape.sh"
skill="$plugin_dir/skills/kc-shape-the-change/SKILL.md"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

failures=0
passes=0

awk '/^```markdown$/ { inside = 1; next } inside && /^```$/ { exit } inside' "$skill" > "$work_dir/passing.md"

# expect_verdict <pass|fail> <label> <file> [problem text the output must contain]
expect_verdict() {
  local expectation=$1 label=$2 file=$3 needle=${4:-} output status verdict
  output=$(bash "$checker" "$file" 2>&1); status=$?
  verdict=pass
  [ "$status" -eq 0 ] || verdict=fail
  if [ "$verdict" = "$expectation" ] && { [ -z "$needle" ] || printf '%s' "$output" | grep -qF -- "$needle"; }; then
    echo "ok   $label"; passes=$((passes + 1))
  else
    echo "FAIL $label: expected $expectation containing '$needle', got $verdict: $output"; failures=$((failures + 1))
  fi
}

# make_variant <name> <sed expression>: the passing file with one edit.
make_variant() { sed -E "$2" "$work_dir/passing.md" > "$work_dir/$1.md"; }

expect_verdict pass "§SH1-§SH8 filled: the skill's template passes" "$work_dir/passing.md"

for n in 1 2 3 4 5 6 7 8; do
  grep -v "§SH$n " "$work_dir/passing.md" > "$work_dir/missing$n.md"
  expect_verdict fail "§SH$n removed is reported" "$work_dir/missing$n.md" "§SH$n: missing"
done
make_variant unticked 's/^- \[x\] §SH3/- [ ] §SH3/'
expect_verdict fail "an unticked box fails" "$work_dir/unticked.md" "§SH3: the box is not ticked"
make_variant short 's/^(- \[x\] §SH1 requirement:).*/\1 reports./'
expect_verdict fail "a one-word answer fails" "$work_dir/short.md" "§SH1: the answer is under 4 words"
make_variant short-facts 's/^(- \[x\] §SH2 facts:).*/\1 stored./'
expect_verdict fail "§SH2 with a one-word answer fails" "$work_dir/short-facts.md" "§SH2: the answer is under 4 words"
make_variant fill-in 's/^(- \[x\] §SH5 .*)$/\1 fill in later/'
expect_verdict fail "a fill in fails" "$work_dir/fill-in.md" "§SH5: unfinished"
awk '{ print } /§SH3 owners/ { print }' "$work_dir/passing.md" > "$work_dir/twice.md"
expect_verdict fail "a box listed twice fails" "$work_dir/twice.md" "§SH3: listed 2 times"
make_variant tbd 's/^(- \[x\] §SH5 .*)$/\1 TBD/'
expect_verdict fail "a TBD fails" "$work_dir/tbd.md" "§SH5: unfinished"

grep -v 'shape B:' "$work_dir/passing.md" > "$work_dir/one-shape.md"
expect_verdict fail "§SH4 with one shape fails" "$work_dir/one-shape.md" "compare at least 2 shapes"
grep -v '  - pick:' "$work_dir/passing.md" > "$work_dir/no-pick.md"
expect_verdict fail "§SH4 with no pick fails" "$work_dir/no-pick.md" "no \"- pick:"
make_variant bad-pick 's/- pick: B,/- pick: Z,/'
expect_verdict fail "a pick naming no shape fails" "$work_dir/bad-pick.md" "the pick must start with the label of a shape"
make_variant no-reason 's/- pick: B,.*/- pick: B/'
expect_verdict fail "a pick with no reason fails" "$work_dir/no-reason.md" "the pick needs its reason"

grep -v '  - flag:' "$work_dir/passing.md" > "$work_dir/no-flag.md"
expect_verdict fail "§SH6 with no flag line fails" "$work_dir/no-flag.md" "no flag line"
make_variant flag-fields 's/ \| decided-by: shop owner$//'
expect_verdict fail "a flag line missing decided-by fails" "$work_dir/flag-fields.md" "flag line must read"
make_variant flag-agent 's/decided-by: shop owner/decided-by: claude/'
expect_verdict fail "a flag decided by the agent fails" "$work_dir/flag-agent.md" "not the agent"
make_variant flag-nobody 's/decided-by: shop owner/decided-by:/'
expect_verdict fail "a flag with an empty decided-by fails" "$work_dir/flag-nobody.md" "not the agent"
make_variant flag-production 's/\| no \| reason: readers tolerate empty rows, so there is no data gap to hide/| yes | reason: backfill of production rows is not finished yet/'
expect_verdict fail "a yes flag naming production is still a data gap" "$work_dir/flag-production.md" "data or deploy gap only"
make_variant flag-product 's/\| yes \| reason: customers get it gradually, starting with one pilot storefront/| yes | reason: a product rollout decision for the owner, after the backfill/'
expect_verdict pass "a flag naming a product rollout passes" "$work_dir/flag-product.md"
make_variant flag-short-reason 's/\| no \| reason: readers tolerate empty rows, so there is no data gap to hide/| no | reason: all safe/'
expect_verdict fail "a flag with a two-word reason fails" "$work_dir/flag-short-reason.md" "no reason of at least 3 words"
make_variant flag-gap 's/\| no \| reason: readers tolerate empty rows, so there is no data gap to hide/| yes | reason: the readers wait for the backfill to finish before they are used/'
expect_verdict fail "a yes flag covering only a data gap fails" "$work_dir/flag-gap.md" "data or deploy gap only"
make_variant flag-deploy 's/\| yes \| reason: customers get it gradually, starting with one pilot storefront/| yes | reason: the code has to deploy before the migration runs/'
expect_verdict fail "a yes flag covering only a deploy order fails" "$work_dir/flag-deploy.md" "data or deploy gap only"
make_variant flag-both 's/\| yes \| reason: customers get it gradually, starting with one pilot storefront/| yes | reason: customers get it gradually while the backfill runs behind a pilot/'
expect_verdict pass "a flag with a product rollout reason passes" "$work_dir/flag-both.md"
make_variant flag-no-gap 's/\| no \| reason: readers tolerate empty rows, so there is no data gap to hide/| no | reason: the backfill is safe to run while the old readers stay live/'
expect_verdict pass "a no flag naming a backfill passes" "$work_dir/flag-no-gap.md"

grep -v '  - failure:' "$work_dir/passing.md" > "$work_dir/no-failure.md"
expect_verdict fail "§SH7 with no failure line fails" "$work_dir/no-failure.md" "no failure line"
make_variant no-signal 's/ \| noticed-by: .*$//'
expect_verdict fail "a failure with no signal fails" "$work_dir/no-signal.md" "failure line must read"
make_variant no-quote 's/^(- \[x\] §SH8 approval:).*/\1 the owner agreed in chat/'
expect_verdict fail "an approval without quoted words fails" "$work_dir/no-quote.md" "quote the approval words"
make_variant one-word-quote 's/^(- \[x\] §SH8 approval:).*/\1 "ok" said the shop owner in chat/'
expect_verdict fail "a one-word quote fails" "$work_dir/one-word-quote.md" "at least 2 words"

printf 'trivial: no new storage, no new unit, no behaviour move: fixes the rounding of one displayed total\n' > "$work_dir/trivial.md"
expect_verdict pass "the one-line trivial declaration passes" "$work_dir/trivial.md"
printf 'trivial: no new unit, no behaviour move: fixes the rounding of one displayed total\n' > "$work_dir/trivial-storage.md"
expect_verdict fail "trivial without \"no new storage\" fails" "$work_dir/trivial-storage.md" "no new storage"
printf 'trivial: no new storage, no behaviour move: fixes the rounding of one displayed total\n' > "$work_dir/trivial-unit.md"
expect_verdict fail "trivial without \"no new unit\" fails" "$work_dir/trivial-unit.md" "no new unit"
printf 'trivial: no new storage, no new unit: fixes the rounding of one displayed total\n' > "$work_dir/trivial-move.md"
expect_verdict fail "trivial without \"no behaviour move\" fails" "$work_dir/trivial-move.md" "no behaviour move"
printf 'trivial: no new storage, no new unit, no behaviour move: typo\n' > "$work_dir/trivial-reason.md"
expect_verdict fail "trivial with no reason fails" "$work_dir/trivial-reason.md" "give the reason"
printf 'a note first\ntrivial: no new storage, no new unit, no behaviour move: fixes a total\n' > "$work_dir/trivial-late.md"
expect_verdict fail "a trivial line that is not first fails" "$work_dir/trivial-late.md" "§SH1: missing"

bash "$checker" >/dev/null 2>&1
if [ $? -eq 2 ]; then echo "ok   no argument is a usage error"; passes=$((passes + 1)); else echo "FAIL no argument should exit 2"; failures=$((failures + 1)); fi
bash "$checker" "$work_dir/absent.md" >/dev/null 2>&1
if [ $? -eq 2 ]; then echo "ok   an unreadable file is a usage error"; passes=$((passes + 1)); else echo "FAIL unreadable file should exit 2"; failures=$((failures + 1)); fi

echo "$passes passed, $failures failed"
[ "$failures" -eq 0 ]
