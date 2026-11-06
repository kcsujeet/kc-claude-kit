#!/usr/bin/env bash
# Tests scripts/check-lesson-proof.sh in a throwaway repo: a rule changed alone fails, and passes
# with an eval or a script test beside it, or with a `wording-only:` reason in the description; a
# checklist box added or rewritten passes only when a changed eval or test names its id; a rule file
# that gains lines but no box passes only with a `wording-only:` reason.
set -euo pipefail

script="$(cd "$(dirname "$0")/.." && pwd)/check-lesson-proof.sh"
repo=$(mktemp -d)
trap 'rm -rf "$repo"' EXIT
passes=0
failures=0

pass() { echo "ok   $1"; passes=$((passes + 1)); }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }

# Runs the check on the current branch against main, with an optional description, and checks its
# verdict; its output is kept in $last_output for the cases that read it.
last_output=""
expect_verdict() {
  local expectation=$1 label=$2 body=${3:-} actual=pass
  if [ -n "$body" ]; then
    printf '%s\n' "$body" > "$repo/.body"
    last_output=$(cd "$repo" && bash "$script" main --body-file .body) || actual=fail
  else
    last_output=$(cd "$repo" && bash "$script" main) || actual=fail
  fi
  if [ "$actual" = "$expectation" ]; then pass "$label"; else fail "$label (expected $expectation, got $actual)"; fi
}

expect_output() {
  local label=$1 expected_text=$2
  case "$last_output" in
    *"$expected_text"*) pass "$label" ;;
    *) fail "$label (no \"$expected_text\" in: $last_output)" ;;
  esac
}

# Runs the check with <args> and checks it exits 2, as a usage error does.
expect_exit_2() {
  local label=$1 status=0
  shift
  (cd "$repo" && bash "$script" "$@" >/dev/null 2>"$repo/.stderr") || status=$?
  if [ "$status" -eq 2 ]; then pass "$label"; else fail "$label (exit $status)"; fi
}

commit_change() {
  git -C "$repo" add -A
  git -C "$repo" -c user.name=t -c user.email=t@example.test commit -q -m "$1"
}

create_branch() { git -C "$repo" checkout -q main && git -C "$repo" checkout -q -b "$1"; }

# Writes <text> to <path> in the repo, making its folder.
write_repo_file() { mkdir -p "$(dirname "$repo/$1")" && printf '%b' "$2" > "$repo/$1"; }

git -C "$repo" init -q -b main
write_repo_file plugins/shop/skills/checkout/SKILL.md 'A total includes tax.\n'
write_repo_file plugins/shop/skills/checkout/references/rounding.md 'Round half up.\n\n- [ ] §T1 Totals round half up.\n- [ ] §T12 Refunds round down.\n'
write_repo_file plugins/shop/agents/totals-gate.md 'Grade totals.\n'
write_repo_file plugins/shop/rules/kc-working-agreement.md 'Ask first.\n'
write_repo_file plugins/shop/rules/kc-checkout.md 'Generated.\n'
write_repo_file CHANGELOG.md '# Changelog\n'
write_repo_file plugins/shop/tests/old.test.sh 'grep tax\ngrep total # §T2\n'
commit_change base

create_branch nothing
expect_verdict pass "nothing changed"

create_branch changelog
echo "- notes" >> "$repo/CHANGELOG.md"
commit_change "changelog only"
expect_verdict pass "a change to no rule"

create_branch generated
echo "Generated again." > "$repo/plugins/shop/rules/kc-checkout.md"
commit_change "generated rule only"
expect_verdict pass "a generated rule file alone is not a rule edit"

for rule in skills/checkout/SKILL.md skills/checkout/references/rounding.md agents/totals-gate.md rules/kc-working-agreement.md; do
  create_branch "alone-${rule//\//-}"
  echo "and more" >> "$repo/plugins/shop/$rule"
  commit_change "edit $rule"
  expect_verdict fail "$rule changed alone"
  expect_output "the failure names $rule" "plugins/shop/$rule"
done

create_branch accented-path
write_repo_file 'plugins/shop/skills/café/SKILL.md' 'Serve it hot.\n'
commit_change "a rule in a folder with an accent, alone"
expect_verdict fail "a rule in a path with an accent is a rule"

for proof in plugins/shop/evals/totals/case.yaml plugins/shop/tests/totals.test.sh scripts/tests/totals.test.sh; do
  create_branch "with-${proof//\//-}"
  echo "- [ ] §T2 Totals include shipping." >> "$repo/plugins/shop/skills/checkout/references/rounding.md"
  write_repo_file "$proof" 'proof of §T2\n'
  commit_change "rule with $proof"
  expect_verdict pass "a rule with $proof beside it"
done
expect_output "the proof is counted" "rules changed with proof: 1 eval or test file(s)"

create_branch with-script-only
echo "- [ ] §T2 Totals include shipping." >> "$repo/plugins/shop/skills/checkout/references/rounding.md"
write_repo_file plugins/shop/scripts/total.sh 'echo total\n'
commit_change "rule with an untested script"
expect_verdict fail "a script with no test is not proof"

create_branch box-named
echo "- [ ] §T2 Totals include shipping." >> "$repo/plugins/shop/skills/checkout/references/rounding.md"
write_repo_file plugins/shop/evals/totals/graders/shipping.md 'pattern: shipping # proves §T2\n'
commit_change "a box with an eval that names it"
expect_verdict pass "an added box whose id a changed eval names"

create_branch box-unnamed
echo "- [ ] §T2 Totals include shipping." >> "$repo/plugins/shop/skills/checkout/references/rounding.md"
write_repo_file plugins/shop/evals/totals/shipping.md 'pattern: shipping\n'
commit_change "a box with an eval that does not name it"
expect_verdict fail "an added box no changed eval or test names"
expect_output "the failure names the box" "naming them: §T2"
expect_verdict pass "an unnamed box with a stated wording-only reason" 'wording-only: moves an existing rule into a box'

create_branch box-rewritten
write_repo_file plugins/shop/skills/checkout/references/rounding.md 'Round half up.\n\n- [ ] §T1 Totals round half up, per line.\n- [ ] §T12 Refunds round down.\n'
write_repo_file plugins/shop/tests/rounding.test.sh 'grep per-line # §T12\n'
commit_change "a rewritten box; the test names a longer id"
expect_verdict fail "a rewritten box whose id only appears inside a longer one"
expect_output "the failure names the rewritten box alone" "naming them: §T1"
write_repo_file plugins/shop/tests/rounding.test.sh 'grep per-line # §T1, §T12\n'
commit_change "the test names the box"
expect_verdict pass "a rewritten box whose id a changed test names"

create_branch dotted-box
write_repo_file plugins/shop/skills/checkout/references/backfills.md '- [ ] §RL6.1a Backfill in batches.\n- [ ] §RL6.2b Log each batch.\n'
write_repo_file plugins/shop/tests/backfills.test.sh 'grep batch # §RL6.2b\n'
commit_change "two dotted boxes; the test names one"
expect_verdict fail "a dotted box id is its own id, not its prefix"
expect_output "the failure names the dotted box" "naming them: §RL6.1a"

create_branch spaced-path
write_repo_file 'plugins/shop/skills/gift cards/SKILL.md' '- [ ] §T3 A gift card never expires.\n'
write_repo_file plugins/shop/tests/gift-cards.test.sh 'grep expires\n'
commit_change "a box in a folder with a space; the test does not name it"
expect_verdict fail "a box in a path with a space is read"
expect_output "the failure names that box" "naming them: §T3"

create_branch proof-deleted
echo "Include shipping." >> "$repo/plugins/shop/skills/checkout/SKILL.md"
git -C "$repo" rm -q plugins/shop/tests/old.test.sh
commit_change "a rule with a test deleted beside it"
expect_verdict fail "a deleted test is not proof"

create_branch proof-shrunk
echo "Include shipping." >> "$repo/plugins/shop/skills/checkout/SKILL.md"
write_repo_file plugins/shop/tests/old.test.sh 'grep tax\n'
commit_change "a rule with a test that only loses a line"
expect_verdict fail "a test that only loses lines is not proof"

create_branch proof-renamed
echo "- [ ] §T2 Totals include shipping." >> "$repo/plugins/shop/skills/checkout/references/rounding.md"
git -C "$repo" mv plugins/shop/tests/old.test.sh plugins/shop/tests/renamed.test.sh
commit_change "a box with a test naming it that is only renamed"
expect_verdict fail "a test that is only renamed is not proof"

create_branch proof-renamed-and-edited
echo "- [ ] §T2 Totals include shipping." >> "$repo/plugins/shop/skills/checkout/references/rounding.md"
git -C "$repo" mv plugins/shop/tests/old.test.sh plugins/shop/tests/renamed.test.sh
write_repo_file plugins/shop/tests/renamed.test.sh 'grep tax\ngrep total # §T2\ngrep shipping # §T2\n'
commit_change "a box with a renamed test that gains a case naming it"
expect_verdict pass "a renamed test that gains lines naming the box is proof"

create_branch box-dot-after-id
echo "- [ ] §T2. Totals include shipping." >> "$repo/plugins/shop/skills/checkout/references/rounding.md"
write_repo_file plugins/shop/tests/shipping.test.sh 'grep shipping\n'
commit_change "a box whose id a period ends, with a test that does not name it"
expect_verdict fail "a box id followed by a period is still read"
expect_output "the failure names that box" "naming them: §T2"

create_branch box-named-in-fixture
echo "- [ ] §T2 Totals include shipping." >> "$repo/plugins/shop/skills/checkout/references/rounding.md"
write_repo_file plugins/shop/tests/fixtures/data.txt '§T2\n'
commit_change "a box whose id only a fixture names"
expect_verdict fail "an id named only in a fixture is not proof"
write_repo_file plugins/shop/evals/totals/graders/shipping.md 'pattern: shipping # §T2\n'
commit_change "the eval's grader names it"
expect_verdict pass "an id named in an eval grader is proof"

# A lesson is a box: prose a rule file gains is wording only, whatever test changed beside it.
create_branch prose-beside-a-test
echo "Include shipping." >> "$repo/plugins/shop/skills/checkout/SKILL.md"
write_repo_file plugins/shop/tests/totals.test.sh 'grep total\n'
commit_change "prose added to a rule, with an unrelated test"
expect_verdict fail "prose a rule file gains is not proven by an unrelated test"
expect_output "the failure names the file" "plugins/shop/skills/checkout/SKILL.md"
expect_output "the failure says why" "gain lines but no checklist box"
expect_verdict pass "prose with a stated wording-only reason" 'wording-only: says when tax applies, a reminder with no new check'

for boxless in agents/totals-gate.md rules/kc-working-agreement.md; do
  create_branch "prose-in-${boxless//\//-}"
  echo "Check shipping too." >> "$repo/plugins/shop/$boxless"
  write_repo_file plugins/shop/tests/totals.test.sh 'grep shipping\n'
  commit_change "prose added to $boxless, with a test"
  expect_verdict fail "$boxless has no boxes, so what it gains is prose"
done

create_branch prose-here-box-there
echo "Include shipping." >> "$repo/plugins/shop/skills/checkout/SKILL.md"
echo "- [ ] §T2 Totals include shipping." >> "$repo/plugins/shop/skills/checkout/references/rounding.md"
write_repo_file plugins/shop/tests/totals.test.sh 'grep shipping # §T2\n'
commit_change "prose in one rule file, a proven box in another"
expect_verdict fail "a box in one file doesn't cover prose another file gains"
expect_output "the failure names only the file with no box" "       plugins/shop/skills/checkout/SKILL.md"

create_branch prose-with-its-box
printf 'Shipping counts as part of the total.\n\n- [ ] §T2 Totals include shipping.\n' >> "$repo/plugins/shop/skills/checkout/references/rounding.md"
write_repo_file plugins/shop/tests/totals.test.sh 'grep shipping # §T2\n'
commit_change "prose and its proven box in one file"
expect_verdict pass "prose beside the box it explains, proven"

create_branch lines-removed
write_repo_file plugins/shop/skills/checkout/references/rounding.md '- [ ] §T1 Totals round half up.\n- [ ] §T12 Refunds round down.\n'
write_repo_file plugins/shop/tests/totals.test.sh 'grep round\n'
commit_change "a rule file that only loses a line, with a test"
expect_verdict pass "a rule file that only loses lines gains no prose"

create_branch blank-lines-only
printf '\n\n' >> "$repo/plugins/shop/skills/checkout/SKILL.md"
write_repo_file plugins/shop/tests/totals.test.sh 'grep total\n'
commit_change "blank lines added to a rule, with a test"
expect_verdict pass "blank lines are not prose"

create_branch wording
echo "A total includes tax, always." > "$repo/plugins/shop/skills/checkout/SKILL.md"
commit_change "reword"
expect_verdict pass "a stated wording-only reason" $'Rewords the tax rule.\n\nwording-only: the same rule, said plainer'
expect_output "the reason is echoed for the reviewer" "wording only: the same rule, said plainer"
expect_verdict pass "the marker in any case" $'WORDING-ONLY: typo fix'
expect_verdict fail "the marker with no reason" $'wording-only:'
expect_verdict fail "the marker with the placeholder left in" $'wording-only: <why>'
expect_verdict fail "the placeholder with a carriage return, as a web edit leaves it" $'wording-only: <why>\r'
expect_verdict fail "the placeholder with a trailing space" $'wording-only: <why> '
expect_verdict fail "the marker with only spaces after it" $'wording-only:   '
expect_verdict fail "the marker inside a sentence" $'This is not wording-only: it adds a rule.'
expect_verdict fail "a description without the marker" $'Adds a rule about tax.'

expect_exit_2 "an unreadable description exits 2" main --body-file no-such.md
expect_exit_2 "no arguments exit 2"
expect_exit_2 "--body-file with no value exits 2" main --body-file
expect_exit_2 "an unknown flag exits 2" main --unknown

git -C "$repo" checkout -q --orphan unrelated
git -C "$repo" rm -rqf .
write_repo_file README.md 'Another project.\n'
commit_change "a history that shares no commit with main"
expect_exit_2 "a head that shares no commit with the base exits 2" main
if grep -q "share no commit" "$repo/.stderr"; then pass "it says why"; else fail "it says why"; fi

echo "$passes passed, $failures failed"
[ "$failures" -eq 0 ]
