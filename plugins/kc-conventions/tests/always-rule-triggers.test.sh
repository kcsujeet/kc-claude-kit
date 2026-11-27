#!/usr/bin/env bash
# Checks that the always-on rule (kc-always.md) stays a short set of reply rules and pointers: every
# skill it names exists in this repo, the answer-first lines are still there, and the skills that
# took over the old working agreement's sections (kc-do-a-task, kc-assess, kc-shape-the-change,
# kc-check-claims, kc-look-back, kc-delegate) still hold their boxes.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
plugin_dir=$(dirname "$tests_dir")
combined_skill() {
  local out
  out=$(mktemp)
  cat "$plugin_dir/skills/$1/SKILL.md" "$plugin_dir/skills/$1/references/detail.md" > "$out"
  echo "$out"
}
plugins_root=$(dirname "$plugin_dir")
always="$plugin_dir/rules/kc-always.md"
assess=$(combined_skill kc-assess)
do_a_task="$plugin_dir/skills/kc-do-a-task/SKILL.md"

failures=0
fail() { echo "FAIL $1"; failures=$((failures + 1)); }

[ -f "$always" ] || { echo "FAIL $always is missing"; exit 1; }
[ ! -e "$plugin_dir/rules/kc-working-agreement.md" ] || fail "kc-working-agreement.md was split into skills and must not come back"
! grep -q '^paths:' "$always" || fail "kc-always.md must load in every session: no paths: frontmatter"
[ "$(wc -w < "$always")" -le 170 ] || fail "kc-always.md is over 170 words: it is an index, put detail in a skill"

while IFS= read -r ref; do
  plugin=${ref%%:*}
  skill=${ref#*:}
  [ -f "$plugins_root/$plugin/skills/$skill/SKILL.md" ] || fail "kc-always.md names $ref, which does not exist"
done < <(grep -oE 'kc-[a-z]+:kc-[a-z-]+' "$always" | sort -u)
for ref in kc-do-a-task kc-check-claims kc-delegate kc-look-back; do
  grep -q "kc-conventions:$ref" "$always" || fail "kc-always.md has no pointer to $ref"
done

grep -q 'answer it first, in its own terms' "$always" || fail "answer-the-question-first trigger missing"
grep -q 'a "when" gets a time, a "why" the cause' "$always" || fail "answer-the-question-first examples missing"

grep -q 'task-claims.sh' "$do_a_task" || fail "kc-do-a-task: overlap check missing"
grep -q 'files made only to hand on' "$do_a_task" || fail "kc-do-a-task: handed-on files cleanup box missing"
grep -q 'removed once the copy that matters is confirmed; files the person asked for stay' "$do_a_task" || fail "kc-do-a-task: handed-on files go, the person's own stay"
grep -q 're-read and the skill each names loaded' "$do_a_task" || fail "kc-do-a-task: hand-off re-read box missing"
grep -q 'list how the codebase already does the same job' "$assess" || fail "kc-assess: existing-code step missing"
grep -q 'Answer what you can before asking' "$assess" || fail "kc-assess: answer-first step missing"
grep -q 'Keep what people have long relied on' "$assess" || fail "kc-assess: long-held behaviour step missing"
grep -q 'Scope not widened' "$assess" || fail "kc-assess: adjacent problems must be offered as a follow-up"
grep -q 'is a bug, never a question: reproduce it and fix it' "$assess" || fail "kc-assess: a differing result is a bug, not a question"
grep -q 'gets its answer and no edit' "$assess" || fail "kc-assess: a question gets no edit in the same turn"

# kc-testing: checks after a mechanical edit, and the full suites of a shared unit's users.
testing=$(combined_skill kc-testing)
grep -q 'run lint and the formatter on every file it touched before committing' "$testing" || fail "kc-testing: lint every file a mechanical edit touched"
grep -q "run the full suites of every package that uses it" "$testing" || fail "kc-testing: full suites of a shared unit's users"

[ "$failures" -eq 0 ] && echo "ok   always-on rule triggers"
exit "$failures"
