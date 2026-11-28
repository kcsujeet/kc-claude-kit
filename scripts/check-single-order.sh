#!/usr/bin/env bash
# Fails when the order of work is stated outside its one home, or a retired skill name comes back.
#
#   1. Only kc-conventions/skills/kc-do-a-task says when review, commit, push and hand-off happen
#      relative to each other. Every other skill, its reference, the session-start text, the guard
#      messages and the README say what a step does and what it needs, never "on the committed
#      branch", "as soon as the work is committed", "before its first push" and the like. Two
#      places stating the order drift apart, and a session reads the stale one.
#   2. kc-ready-for-review was renamed kc-ready-for-human-review. The old name may stay only in
#      CHANGELOG.md, which records history.
#
# Usage: check-single-order.sh [<repo-root>]   (default: the current directory)
# Prints one line per hit, `<path>:<line>: <text>`, and exits 1 when there is any.
set -euo pipefail

root=${1:-.}
cd "$root"

readonly ORDER_PHRASES='on the committed (local )?branch|as soon as the work is committed|before (its|the|a branch.s) first push|before the (PR|pull request) exists|once the work is committed|after the work is committed|once per PR|run it once, on the committed'
readonly RETIRED_NAME='kc-ready-for-review'
hits=0

# The files that must not state the order: every skill and reference but kc-do-a-task's, the hook
# text and guard messages, the README.
list_order_files() {
  find plugins -type f \( -path '*/skills/*/SKILL.md' -o -path '*/skills/*/references/*.md' \) 2>/dev/null | grep -v '/kc-do-a-task/' || true
  ls plugins/kc-gates/scripts/session-start.sh plugins/kc-gates/scripts/guard-hand-off.sh plugins/kc-gates/scripts/guard-merge.sh README.md 2>/dev/null || true
}

while IFS= read -r path; do
  [ -n "$path" ] || continue
  if matches=$(grep -nEi "$ORDER_PHRASES" "$path"); then
    while IFS= read -r line; do
      printf '%s:%s\n' "$path" "$(printf '%s' "$line" | cut -c1-160)"
      hits=$((hits + 1))
    done <<< "$matches"
  fi
done < <(list_order_files | sort -u)

# The retired name, anywhere but the changelog and this check's own files.
while IFS= read -r line; do
  [ -n "$line" ] || continue
  printf '%s\n' "$(printf '%s' "$line" | cut -c1-160)"
  hits=$((hits + 1))
done < <(grep -rnI --exclude-dir=.git --exclude=CHANGELOG.md --exclude=check-single-order.sh --exclude=check-single-order.test.sh -- "$RETIRED_NAME" . | sed 's#^\./##' || true)

if [ "$hits" -gt 0 ]; then
  echo "check-single-order: $hits hit(s). The order of work lives only in kc-conventions/skills/kc-do-a-task; say what a step does, not when it runs. The skill is kc-ready-for-human-review, not $RETIRED_NAME." >&2
  exit 1
fi
echo "check-single-order: clean"
