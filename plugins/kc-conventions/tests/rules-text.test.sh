#!/usr/bin/env bash
# Checks that the lessons whose review gates did not grade reliably in an eval stay in their rule text
# and on their checklist box: kc-correctness §B16 (a value is read under the rules it was written
# by) and §B2 (markup patterns on near-misses), kc-structure §S14 (change the dependency, not the
# home) and kc-naming §N4 (a shared helper is named for what it handles).
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
plugin_dir=$(dirname "$tests_dir")
combined_skill() {
  local out
  out=$(mktemp)
  cat "$plugin_dir/skills/$1/SKILL.md" "$plugin_dir/skills/$1/references/detail.md" > "$out"
  echo "$out"
}
correctness=$(combined_skill kc-correctness)
structure=$(combined_skill kc-structure)
naming=$(combined_skill kc-naming)

failures=0
fail() { echo "FAIL $1"; failures=$((failures + 1)); }

grep -q 'the dependency changes rather than the home (no wrapper or second copy' "$structure" || fail "§S14 rule: change the dependency, not the home"
grep -q 'A dependency that keeps code out of its home is changed, not obeyed' "$structure" || fail "§S14 detail: the dependency case missing"
grep -qE '^- \[ \] §S14 .*the dependency changes rather than the home' "$structure" || fail "§S14 box must carry the dependency check"
grep -q "named for the first caller's field instead of what it handles" "$naming" || fail "§N4 rule: helper named for the first caller's field"
grep -qE "^- \[ \] §N4 .*named for the first caller's field instead of what it handles" "$naming" || fail "§N4 box must carry the shared-helper check"
grep -q 'written under narrower rules than the reader applies' "$correctness" || fail "§B16 rule: read under the writer's rules at every reader"
grep -qE '^- \[ \] §B16 .*written under narrower rules than the reader applies' "$correctness" || fail "§B16 box must carry the narrower-rules state"
grep -q 'also on near-misses such as' "$correctness" || fail "§B2 rule: markup patterns on near-misses"
grep -qE '^- \[ \] §B2 .*near-misses such as' "$correctness" || fail "§B2 box must carry the near-miss and blank-line check"

[ "$failures" -eq 0 ] && echo "ok   rules text"
exit "$failures"
