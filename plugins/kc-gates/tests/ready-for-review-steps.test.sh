#!/usr/bin/env bash
# Checks that the ready-for-review pass keeps the three fix-writing habits that no script can run
# for it, each in its step and on its gate checklist box: code a gate calls dead is run against
# every input state before it is removed, a duplication finding is fixed by one shared copy, and
# every comment on the PR (bots included) has a reply, which ready-receipt.sh enforces.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
plugin_dir=$(dirname "$tests_dir")
# The wording moved to references/detail.md; the skill and its detail are read as one text.
skill=$(mktemp)
trap 'rm -f "$skill"' EXIT
cat "$plugin_dir/skills/kc-ready-for-review/SKILL.md" "$plugin_dir/skills/kc-ready-for-review/references/detail.md" > "$skill"

failures=0
fail() { echo "FAIL $1"; failures=$((failures + 1)); }

grep -q 'Code a gate calls dead is proven dead before it goes' "$skill" || fail "step 6: dead-code removal bullet missing"
grep -q 'every input state its type admits (null, undefined, empty, zero)' "$skill" || fail "step 6: dead-code removal must run every input state"
grep -q 'A duplication finding is fixed by consolidating to one copy' "$skill" || fail "step 6: duplication bullet missing"
grep -q 'ready-receipt.sh. refuses while one has no reply from the author' "$skill" || fail "step 9: the receipt refuses while a PR comment is unanswered"
grep -qE '^- \[ \] §H4 .*every input state its type admits \(null, undefined, empty\).*consolidating to one copy' "$skill" || fail "§H4 must carry dead-code and duplication checks"
grep -qE '^- \[ \] §H5 .*every PR comment, bot reviewers included, has a reply' "$skill" || fail "§H5 must carry the every-comment-answered check"

[ "$failures" -eq 0 ] && echo "ok   ready-for-review steps"
exit "$failures"
