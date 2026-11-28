#!/usr/bin/env bash
# Checks that kc-do-a-task states the order of work (build, self-correct, the person looks, commit,
# ready for human review, push, look back, clean up) in numbered steps, that its boxes carry the same
# order (§DT4, §DT5, §DT7, §DT11), and that the look-back box naming the hand-off checklist's grader
# uses the current skill name (§LB6). Every other skill stays silent on the order:
# scripts/check-single-order.sh holds that.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
plugins_root=$(cd "$tests_dir/../.." && pwd)
skill="$plugins_root/kc-conventions/skills/kc-do-a-task/SKILL.md"
look_back="$plugins_root/kc-conventions/skills/kc-look-back/references/detail.md"

failures=0
fail() { echo "FAIL $1"; failures=$((failures + 1)); }

# The step numbers of the order list, by the skill each names.
step_of() { grep -nE "^[0-9]+\. .*$1" "$skill" | head -n 1 | cut -d: -f1; }
build=$(step_of '\*\*Build:\*\*')
self_correct=$(step_of 'kc-gates:kc-self-correct')
human_review=$(step_of 'kc-gates:kc-ready-for-human-review')
push=$(step_of '\*\*Push and open the pull request\*\*')
for step in "$build" "$self_correct" "$human_review" "$push"; do
  [ -n "$step" ] || fail "an order step is missing from kc-do-a-task"
done
if [ -n "$build" ] && [ -n "$self_correct" ] && [ -n "$human_review" ] && [ -n "$push" ]; then
  [ "$build" -lt "$self_correct" ] && [ "$self_correct" -lt "$human_review" ] && [ "$human_review" -lt "$push" ] || fail "the order must be build, self-correct, ready for human review, push"
fi
grep -qE '^4\. \*\*Self-correct\*\*.*the person looks.*commit locally' "$skill" || fail "step 4 must hold self-correct, the person looking, then the commit"
grep -qE '^- \[ \] §DT4 Committed locally only after the person looked at the self-corrected change' "$skill" || fail "§DT4 must put the commit after the person looked"
grep -qE '^- \[ \] §DT5 Self-correct ran once on the finished change' "$skill" || fail "§DT5 must be about self-correct"
grep -qE '^- \[ \] §DT7 The pull request was opened .* from the body file the hand-off wrote' "$skill" || fail "§DT7 must open the PR from the hand-off's body file"
grep -qE '^- \[ \] §DT11 Ready for human review confirmed the self-correct record matches the committed content' "$skill" || fail "§DT11 must carry the record match"
grep -q 'This skill is the only place that states the order of work' "$skill" || fail "kc-do-a-task must say it owns the order"
grep -qE '^- \[ \] §LB6 .*graded by kc-ready-for-human-review' "$look_back" || fail "§LB6 must name kc-ready-for-human-review as the checklist's grader"

[ "$failures" -eq 0 ] && echo "ok   kc-do-a-task states the order of work"
exit "$failures"
