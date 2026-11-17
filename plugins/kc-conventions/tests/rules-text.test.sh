#!/usr/bin/env bash
# Checks that the lessons whose review gates did not grade reliably in an eval stay in their rule text
# and on their checklist box: kc-correctness §B16 (a value is read under the rules it was written
# by) and §B2 (markup patterns on near-misses), kc-structure §S14 (change the dependency, not the
# home) and kc-naming §N4 (a shared helper is named for what it handles).
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
plugin_dir=$(dirname "$tests_dir")
correctness="$plugin_dir/skills/kc-correctness/SKILL.md"
structure="$plugin_dir/skills/kc-structure/SKILL.md"
naming="$plugin_dir/skills/kc-naming/SKILL.md"

failures=0
fail() { echo "FAIL $1"; failures=$((failures + 1)); }

grep -q 'change the dependency, not the home: no wrapper, no second copy' "$structure" || fail "§S14 rule: change the dependency, not the home"
grep -q 'A dependency that keeps code out of its home is changed, not obeyed' "$structure" || fail "§S14 detail: the dependency case missing"
grep -qE '^- \[ \] §S14 .*the dependency changes rather than the home' "$structure" || fail "§S14 box must carry the dependency check"
grep -q "a shared helper named for the first caller's field" "$naming" || fail "§N4 rule: helper named for the first caller's field"
grep -qE "^- \[ \] §N4 .*named for the first caller's field instead of what it handles" "$naming" || fail "§N4 box must carry the shared-helper check"
grep -q 'is read under the same rules at every reader' "$correctness" || fail "§B16 rule: read under the writer's rules at every reader"
grep -qE '^- \[ \] §B16 .*written under narrower rules than the reader applies' "$correctness" || fail "§B16 box must carry the narrower-rules state"
grep -q 'on near-misses that look like one' "$correctness" || fail "§B2 rule: markup patterns on near-misses"
grep -qE '^- \[ \] §B2 .*near-misses such as' "$correctness" || fail "§B2 box must carry the near-miss and blank-line check"

[ "$failures" -eq 0 ] && echo "ok   rules text"
exit "$failures"
