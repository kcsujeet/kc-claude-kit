#!/usr/bin/env bash
# Tests scripts/check-lesson-proof.sh in a throwaway repo: a rule changed alone fails, and passes
# with an eval or a script test beside it, or with a `wording-only:` reason in the description.
set -euo pipefail

script="$(cd "$(dirname "$0")/.." && pwd)/check-lesson-proof.sh"
repo=$(mktemp -d)
trap 'rm -rf "$repo"' EXIT
passes=0
failures=0

# Runs the check on the current branch against main, with an optional description.
check() {
  local expectation=$1 label=$2 body=${3:-} actual=pass
  if [ -n "$body" ]; then
    printf '%s\n' "$body" > "$repo/.body"
    (cd "$repo" && bash "$script" main --body-file .body >/dev/null) || actual=fail
  else
    (cd "$repo" && bash "$script" main >/dev/null) || actual=fail
  fi
  if [ "$actual" = "$expectation" ]; then
    echo "ok   $label"
    passes=$((passes + 1))
  else
    echo "FAIL $label (expected $expectation, got $actual)"
    failures=$((failures + 1))
  fi
}

commit() {
  git -C "$repo" add -A
  git -C "$repo" -c user.name=t -c user.email=t@example.test commit -q -m "$1"
}

# Starts a branch named <name> off main.
branch() { git -C "$repo" checkout -q main && git -C "$repo" checkout -q -b "$1"; }

git -C "$repo" init -q -b main
mkdir -p "$repo/plugins/shop/skills/checkout/references" "$repo/plugins/shop/agents" "$repo/plugins/shop/rules" \
  "$repo/plugins/shop/evals/totals" "$repo/plugins/shop/tests" "$repo/plugins/shop/scripts" "$repo/scripts/tests"
echo "A total includes tax." > "$repo/plugins/shop/skills/checkout/SKILL.md"
echo "Round half up." > "$repo/plugins/shop/skills/checkout/references/rounding.md"
echo "Grade totals." > "$repo/plugins/shop/agents/totals-gate.md"
echo "Ask first." > "$repo/plugins/shop/rules/kc-working-agreement.md"
echo "Generated." > "$repo/plugins/shop/rules/kc-checkout.md"
echo "# Changelog" > "$repo/CHANGELOG.md"
commit base

branch nothing
check pass "nothing changed"

branch changelog
echo "- notes" >> "$repo/CHANGELOG.md"
commit "changelog only"
check pass "a change to no rule"

branch generated
echo "Generated again." > "$repo/plugins/shop/rules/kc-checkout.md"
commit "generated rule only"
check pass "a generated rule file alone is not a rule edit"

for rule in skills/checkout/SKILL.md skills/checkout/references/rounding.md agents/totals-gate.md rules/kc-working-agreement.md; do
  branch "alone-${rule//\//-}"
  echo "and more" >> "$repo/plugins/shop/$rule"
  commit "edit $rule"
  check fail "$rule changed alone"
done

branch with-eval
echo "Include shipping." >> "$repo/plugins/shop/skills/checkout/SKILL.md"
echo "case" > "$repo/plugins/shop/evals/totals/eval.yaml"
commit "rule with eval"
check pass "a rule with an eval case beside it"

branch with-plugin-test
echo "Include shipping." >> "$repo/plugins/shop/skills/checkout/SKILL.md"
echo "test" > "$repo/plugins/shop/tests/totals.test.sh"
commit "rule with plugin test"
check pass "a rule with a plugin script test beside it"

branch with-repo-test
echo "Include shipping." >> "$repo/plugins/shop/skills/checkout/SKILL.md"
echo "test" > "$repo/scripts/tests/totals.test.sh"
commit "rule with repo test"
check pass "a rule with a repo script test beside it"

branch with-script-only
echo "Include shipping." >> "$repo/plugins/shop/skills/checkout/SKILL.md"
echo "echo total" > "$repo/plugins/shop/scripts/total.sh"
commit "rule with an untested script"
check fail "a script with no test is not proof"

branch wording
echo "A total includes tax, always." > "$repo/plugins/shop/skills/checkout/SKILL.md"
commit "reword"
check pass "a stated wording-only reason" $'Rewords the tax rule.\n\nwording-only: the same rule, said plainer'
check pass "the marker in any case" $'WORDING-ONLY: typo fix'
check fail "the marker with no reason" $'wording-only:'
check fail "the marker with only spaces after it" $'wording-only:   '
check fail "the marker inside a sentence" $'This is not wording-only: it adds a rule.'
check fail "a description without the marker" $'Adds a rule about tax.'

echo "$passes passed, $failures failed"
[ "$failures" -eq 0 ]
