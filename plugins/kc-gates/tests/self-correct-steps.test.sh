#!/usr/bin/env bash
# Checks that kc-self-correct keeps the fix-writing habits that no script can run for it, each in its
# step and on its gate checklist box (dead code is run against every input state before it is removed,
# a duplication finding is fixed by one shared copy, QA findings are fixed like code-review ones), and
# that kc-ready-for-human-review keeps the every-comment-answered check, which ready-receipt.sh enforces.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
plugin_dir=$(dirname "$tests_dir")
# The wording lives in references/detail.md; a skill and its detail are read as one text.
self_correct=$(mktemp)
human_review=$(mktemp)
trap 'rm -f "$self_correct" "$human_review"' EXIT
cat "$plugin_dir/skills/kc-self-correct/SKILL.md" "$plugin_dir/skills/kc-self-correct/references/detail.md" > "$self_correct"
cat "$plugin_dir/skills/kc-ready-for-human-review/SKILL.md" "$plugin_dir/skills/kc-ready-for-human-review/references/detail.md" > "$human_review"

failures=0
fail() { echo "FAIL $1"; failures=$((failures + 1)); }

grep -q 'Code a gate calls dead is proven dead before it goes' "$self_correct" || fail "dead-code removal bullet missing"
grep -q 'every input state its type admits (null, undefined, empty, zero)' "$self_correct" || fail "dead-code removal must run every input state"
grep -q 'A duplication finding is fixed by consolidating to one copy' "$self_correct" || fail "duplication bullet missing"
grep -q 'a QA finding is a finding like any other and is fixed in the same rounds' "$self_correct" || fail "QA findings are fixed in the rounds"
grep -qE '^- \[ \] §SC4 .*every input state its type admits \(null, undefined, empty\).*consolidating to one copy' "$self_correct" || fail "§SC4 must carry dead-code and duplication checks"
grep -qE '^- \[ \] §SC3 .*QA findings included' "$self_correct" || fail "§SC3 must name QA findings"
grep -qE '^- \[ \] §SC1 Rounds converge.*at most 3' "$self_correct" || fail "§SC1 must hold the rounds to at most 3"
grep -qE '^- \[ \] §SC2 One writer' "$self_correct" || fail "§SC2 must name the one writer"
grep -qE '^- \[ \] §SC5 The record names the content reviewed \(its tree hash\), not a commit' "$self_correct" || fail "§SC5 must key the record on the tree hash"
grep -qE '^- \[ \] §H11 A .kc-self-correct. record matches the content being handed over' "$human_review" || fail "§H11 must carry the record match"
grep -q 'ready-receipt.sh. refuses while one has no reply from the author' "$human_review" || fail "the receipt refuses while a PR comment is unanswered"
grep -qE '^- \[ \] §H5 .*every PR comment, bot reviewers included, has a reply' "$human_review" || fail "§H5 must carry the every-comment-answered check"

[ "$failures" -eq 0 ] && echo "ok   self-correct and ready-for-human-review steps"
exit "$failures"
