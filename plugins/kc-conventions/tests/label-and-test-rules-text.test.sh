#!/usr/bin/env bash
# Checks the text of the translation and test-setup lessons stays in the rules and on their
# checklist boxes: i18n §I6 (a fixed label is a plain key; a plural message is read with a real
# count, never a literal one), i18n §I9 (no grammar attached to a placeholder) and testing §T4
# (a render of the same component in 2+ tests is setup) and i18n §I10 (one term, one spelling, on
# every screen; the term-spellings.sh lookup reads the whole tree, tested by tests/run-lookups.sh). The sweeps that enumerate them are tested
# by tests/run-sweeps.sh, and each is wired into its skill's Sweeps section here.
# shellcheck disable=SC2016  # the patterns hold literal backticks and a literal CLAUDE_PLUGIN_ROOT variable
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
plugin_dir=$(dirname "$tests_dir")
i18n="$plugin_dir/skills/kc-i18n/SKILL.md"
testing="$plugin_dir/skills/kc-testing/SKILL.md"

failures=0
fail() { echo "FAIL $1"; failures=$((failures + 1)); }

grep -qE '^- \[ \] §I6 A fixed label, heading, column or nav item is a plain string key' "$i18n" || fail "§I6 box must say a fixed label is a plain string key"
grep -qE '^- \[ \] §I6 .*A literal count \(`count: 0`, `1`, `2`\) passed to get a word form FAILS' "$i18n" || fail "§I6 box must fail a literal count"
grep -qE '^- \[ \] §I6 .*literal-plural-count\.sh' "$i18n" || fail "§I6 box must name the literal-plural-count.sh sweep"
grep -q 'Never pass a literal count' "$i18n" || fail "i18n rule: never pass a literal count"
grep -q 'Mastodon' "$i18n" || fail "§I6 detail must carry the short why (Mastodon keeps labels plain)"
grep -q 'CLDR plural form' "$i18n" || fail "§I6 detail must carry the short why (CLDR forms)"
grep -qE 'Every countable noun is an ICU plural' "$i18n" && fail "i18n must not say every countable noun is an ICU plural"
grep -qE '^- \[ \] §I9 No grammar attached to a placeholder' "$i18n" || fail "§I9 box missing"
grep -qE '^- \[ \] §I9 .*placeholder-grammar\.sh' "$i18n" || fail "§I9 box must name the placeholder-grammar.sh sweep"
grep -q '^### §I9\. No grammar attached to a placeholder' "$i18n" || fail "§I9 detail heading missing"
grep -qE '^- \[ \] §I10 One term, one spelling' "$i18n" || fail "§I10 box missing"
grep -qE '^- \[ \] §I10 .*whether or not the diff touched that line' "$i18n" || fail "§I10 box must fail a stale spelling the diff did not touch"
grep -qE '^- \[ \] §I10 .*term-spellings\.sh' "$i18n" || fail "§I10 box must name the term-spellings.sh lookup"
grep -q '^### §I10\. One term, one spelling, on every screen' "$i18n" || fail "§I10 detail heading missing"
grep -q 'bash "${CLAUDE_PLUGIN_ROOT}/skills/kc-i18n/scripts/term-spellings.sh"' "$i18n" || fail "term-spellings.sh not wired into the i18n Sweeps"
grep -q 'bash "${CLAUDE_PLUGIN_ROOT}/skills/kc-i18n/scripts/literal-plural-count.sh"' "$i18n" || fail "literal-plural-count.sh not wired into the i18n Sweeps"
grep -q 'bash "${CLAUDE_PLUGIN_ROOT}/skills/kc-i18n/scripts/placeholder-grammar.sh"' "$i18n" || fail "placeholder-grammar.sh not wired into the i18n Sweeps"
grep -qE '^- \[ \] §T4 .*A render or mount of the same component .* in 2\+ tests is setup even when each is one call' "$testing" || fail "§T4 box must call a repeated render setup"
grep -qE '^- \[ \] §T4 .*repeated-render\.sh' "$testing" || fail "§T4 box must name the repeated-render.sh sweep"
grep -q 'bash "${CLAUDE_PLUGIN_ROOT}/skills/kc-testing/scripts/repeated-render.sh"' "$testing" || fail "repeated-render.sh not wired into the testing Sweeps"

post_review="$plugin_dir/../kc-gates/skills/kc-post-review/SKILL.md"
grep -q 'a fixed label is a plain key' "$post_review" || fail "kc-post-review translation example must carry the plain-label why"
grep -q 'countable nouns are ICU plurals' "$post_review" && fail "kc-post-review must not say countable nouns are ICU plurals"

[ "$failures" -eq 0 ] && echo "ok   label and test rules text"
exit "$failures"
