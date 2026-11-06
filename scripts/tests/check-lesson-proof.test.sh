#!/usr/bin/env bash
# Tests scripts/check-lesson-proof.sh in a throwaway repo: a rule changed alone fails, and passes
# with an eval or a script test beside it, or with a `wording-only:` reason in the description.
set -euo pipefail

script="$(cd "$(dirname "$0")/.." && pwd)/check-lesson-proof.sh"
repo=$(mktemp -d)
trap 'rm -rf "$repo"' EXIT
passes=0
failures=0

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
  if [ "$actual" = "$expectation" ]; then
    echo "ok   $label"
    passes=$((passes + 1))
  else
    echo "FAIL $label (expected $expectation, got $actual)"
    failures=$((failures + 1))
  fi
}

expect_output() {
  local label=$1 expected_text=$2
  case "$last_output" in
    *"$expected_text"*) echo "ok   $label"; passes=$((passes + 1)) ;;
    *) echo "FAIL $label (no \"$expected_text\" in: $last_output)"; failures=$((failures + 1)) ;;
  esac
}

commit_change() {
  git -C "$repo" add -A
  git -C "$repo" -c user.name=t -c user.email=t@example.test commit -q -m "$1"
}

create_branch() { git -C "$repo" checkout -q main && git -C "$repo" checkout -q -b "$1"; }

git -C "$repo" init -q -b main
mkdir -p "$repo/plugins/shop/skills/checkout/references" "$repo/plugins/shop/agents" "$repo/plugins/shop/rules" \
  "$repo/plugins/shop/evals/totals" "$repo/plugins/shop/tests" "$repo/plugins/shop/scripts" "$repo/scripts/tests"
echo "A total includes tax." > "$repo/plugins/shop/skills/checkout/SKILL.md"
echo "Round half up." > "$repo/plugins/shop/skills/checkout/references/rounding.md"
echo "Grade totals." > "$repo/plugins/shop/agents/totals-gate.md"
echo "Ask first." > "$repo/plugins/shop/rules/kc-working-agreement.md"
echo "Generated." > "$repo/plugins/shop/rules/kc-checkout.md"
echo "# Changelog" > "$repo/CHANGELOG.md"
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

create_branch with-eval
echo "Include shipping." >> "$repo/plugins/shop/skills/checkout/SKILL.md"
echo "case" > "$repo/plugins/shop/evals/totals/eval.yaml"
commit_change "rule with eval"
expect_verdict pass "a rule with an eval case beside it"
expect_output "the proof is counted" "rules changed with proof: 1 eval or test file(s)"

create_branch with-plugin-test
echo "Include shipping." >> "$repo/plugins/shop/skills/checkout/SKILL.md"
echo "test" > "$repo/plugins/shop/tests/totals.test.sh"
commit_change "rule with plugin test"
expect_verdict pass "a rule with a plugin script test beside it"

create_branch with-repo-test
echo "Include shipping." >> "$repo/plugins/shop/skills/checkout/SKILL.md"
echo "test" > "$repo/scripts/tests/totals.test.sh"
commit_change "rule with repo test"
expect_verdict pass "a rule with a repo script test beside it"

create_branch with-script-only
echo "Include shipping." >> "$repo/plugins/shop/skills/checkout/SKILL.md"
echo "echo total" > "$repo/plugins/shop/scripts/total.sh"
commit_change "rule with an untested script"
expect_verdict fail "a script with no test is not proof"

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

status=0
(cd "$repo" && bash "$script" main --body-file no-such.md >/dev/null 2>&1) || status=$?
if [ "$status" -eq 2 ]; then echo "ok   an unreadable description exits 2"; passes=$((passes + 1)); else echo "FAIL an unreadable description exits 2 (got $status)"; failures=$((failures + 1)); fi

echo "$passes passed, $failures failed"
[ "$failures" -eq 0 ]
