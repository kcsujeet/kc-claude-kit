#!/usr/bin/env bash
# Checks that the always-on working agreement stays a set of short triggers: every skill it names
# exists in this repo, and the ask-before-assuming triggers whose procedure lives in kc-assess
# (answer first, keep long-held behaviour) are still there, with kc-assess holding the steps.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
plugin_dir=$(dirname "$tests_dir")
plugins_root=$(dirname "$plugin_dir")
agreement="$plugin_dir/rules/kc-working-agreement.md"
assess="$plugin_dir/skills/kc-assess/SKILL.md"

failures=0
fail() { echo "FAIL $1"; failures=$((failures + 1)); }

while IFS= read -r ref; do
  plugin=${ref%%:*}
  skill=${ref#*:}
  [ -f "$plugins_root/$plugin/skills/$skill/SKILL.md" ] || fail "working agreement names $ref, which does not exist"
done < <(grep -oE '`kc-[a-z]+:kc-[a-z-]+`' "$agreement" | tr -d '`' | sort -u)

grep -q 'Before asking, answer what you can yourself' "$agreement" || fail "answer-before-asking trigger missing"
grep -q 'Keep what people have long relied on' "$agreement" || fail "keep-long-held-behaviour trigger missing"
grep -q 'offer it as its own follow-up' "$agreement" || fail "adjacent problems must be offered as a follow-up"
grep -q 're-read the open steps and load the skill' "$agreement" || fail "hand-off re-read trigger missing"
grep -q 'list how the codebase already does the same job' "$assess" || fail "kc-assess: existing-code step missing"
grep -q 'Answer what you can before asking' "$assess" || fail "kc-assess: answer-first step missing"
grep -q 'Keep what people have long relied on' "$assess" || fail "kc-assess: long-held behaviour step missing"

[ "$failures" -eq 0 ] && echo "ok   working agreement triggers"
exit "$failures"
