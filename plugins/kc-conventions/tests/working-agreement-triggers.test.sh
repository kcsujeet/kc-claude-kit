#!/usr/bin/env bash
# Checks that the always-on working agreement stays a set of short triggers: every skill it names
# exists in this repo, and the ask-before-assuming triggers whose procedure lives in kc-assess
# (answer first, keep long-held behaviour) are still there, with kc-assess holding the steps.
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
agreement="$plugin_dir/rules/kc-working-agreement.md"
assess="$plugin_dir/skills/kc-assess/SKILL.md"

failures=0
fail() { echo "FAIL $1"; failures=$((failures + 1)); }

# shellcheck disable=SC2016 # the backticks are literal: skill references are written in them.
while IFS= read -r ref; do
  plugin=${ref%%:*}
  skill=${ref#*:}
  [ -f "$plugins_root/$plugin/skills/$skill/SKILL.md" ] || fail "working agreement names $ref, which does not exist"
done < <(grep -oE '`kc-[a-z]+:kc-[a-z-]+`' "$agreement" | tr -d '`' | sort -u)

grep -q 'Before asking, answer what you can yourself' "$agreement" || fail "answer-before-asking trigger missing"
grep -q 'Keep what people have long relied on' "$agreement" || fail "keep-long-held-behaviour trigger missing"
grep -q 'offer it as its own follow-up' "$agreement" || fail "adjacent problems must be offered as a follow-up"
grep -q 're-read the open steps and load the skill' "$agreement" || fail "hand-off re-read trigger missing"
grep -q 'answer it first, in its own terms' "$agreement" || fail "answer-the-question-first trigger missing"
grep -q 'a "when" gets a time, a "why" the cause' "$agreement" || fail "answer-the-question-first examples missing"
grep -q 'Files made only to hand on' "$agreement" || fail "handed-on files cleanup trigger missing"
grep -q 'without asking once the copy that matters is confirmed in place; files the person asked for stay' "$agreement" || fail "handed-on files must go without asking, the person's own files stay"
grep -q 'list how the codebase already does the same job' "$assess" || fail "kc-assess: existing-code step missing"
grep -q 'Answer what you can before asking' "$assess" || fail "kc-assess: answer-first step missing"
grep -q 'Keep what people have long relied on' "$assess" || fail "kc-assess: long-held behaviour step missing"
grep -q 'a result unlike what was entered or asked for is a bug, not a question' "$agreement" || fail "bug-not-a-question trigger missing"
grep -q 'and stop (kc-gates flags edits)' "$agreement" || fail "a question gets an answer and no edit (kc-gates flags edits)"
grep -q 'is a bug, never a question: reproduce it and fix it' "$assess" || fail "kc-assess: a differing result is a bug, not a question"
grep -q 'gets its answer and no edit' "$assess" || fail "kc-assess: a question gets no edit in the same turn"

# kc-testing: checks after a mechanical edit, and the full suites of a shared unit's users.
testing=$(combined_skill kc-testing)
grep -q 'run lint and the formatter on every file it touched before committing' "$testing" || fail "kc-testing: lint every file a mechanical edit touched"
grep -q "run the full suites of every package that uses it" "$testing" || fail "kc-testing: full suites of a shared unit's users"

[ "$failures" -eq 0 ] && echo "ok   working agreement triggers"
exit "$failures"
