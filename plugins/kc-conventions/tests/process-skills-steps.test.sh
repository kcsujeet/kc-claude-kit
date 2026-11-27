#!/usr/bin/env bash
# Checks the shape of every process and review skill: numbered steps, a checklist that carries the
# box ids other files cite, the long wording in references/detail.md, and a SKILL.md small enough to
# load whole (at most 2,100 words). A skill that grows back into prose, or loses a box id, fails here.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
plugins_root=$(cd "$tests_dir/../.." && pwd)

failures=0
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
max_words=2100

# check_skill <plugin> <skill> <box ids>...
check_skill() {
  local plugin=$1 skill=$2 id dir file words
  shift 2
  dir="$plugins_root/$plugin/skills/$skill"
  file="$dir/SKILL.md"
  [ -f "$file" ] || { fail "$skill: no SKILL.md"; return; }
  [ -f "$dir/references/detail.md" ] || fail "$skill: no references/detail.md for the long wording"
  words=$(wc -w < "$file")
  [ "$words" -le "$max_words" ] || fail "$skill: SKILL.md is $words words, over $max_words; move wording to references/detail.md"
  grep -q '^1\. ' "$file" || fail "$skill: no numbered steps"
  grep -qE '^## (Review |Gate |Investigation )?[Cc]hecklist' "$file" || fail "$skill: no checklist section"
  for id in "$@"; do
    grep -qE "^- \[ \] $id( |\$)" "$file" || fail "$skill: box $id is missing from the checklist"
  done
}

ids() { local prefix=$1 count=$2 i; for i in $(seq 1 "$count"); do printf '%s%s ' "$prefix" "$i"; done; }

# shellcheck disable=SC2046 # ids prints one word per box id
{
  check_skill kc-conventions kc-assess $(ids §AS 9)
  check_skill kc-conventions kc-look-back $(ids §LB 8)
  check_skill kc-conventions kc-clean-up $(ids §CU 7)
  check_skill kc-conventions kc-investigate $(ids §INV 9)
  check_skill kc-conventions kc-shape-the-change $(ids §SH 12)
  check_skill kc-conventions kc-raise-the-bar $(ids §RB 5)
  check_skill kc-conventions kc-check-claims $(ids §CL 6)
  check_skill kc-conventions kc-delegate $(ids §D 2)
  check_skill kc-verify kc-ui $(ids §UI 24)
  check_skill kc-verify kc-e2e $(ids §EE 6)
  check_skill kc-verify kc-ux $(ids §UX 13)
  check_skill kc-gates kc-code-review $(ids §G 8)
  check_skill kc-gates kc-ready-for-review $(ids §H 5) §H7
  check_skill kc-gates kc-post-review $(ids §PC 12)
}

verification="$plugins_root/kc-gates/agents/verification-gate.md"
for id in $(ids §V 12); do
  grep -qE "^- \[ \] $id " "$verification" || fail "verification-gate: box $id is missing"
done
[ "$(wc -w < "$verification")" -le 900 ] || fail "verification-gate.md is over 900 words: it keeps the judgment boxes, scripts count the rest"
grep -q 'verify-gate-receipts.sh' "$verification" || fail "verification-gate: does not name the receipts script it relies on"

[ "$failures" -eq 0 ] && echo "ok   process and review skills are steps and a checklist"
exit "$failures"
