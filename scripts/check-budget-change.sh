#!/usr/bin/env bash
# Fails when a change raises an always-on budget without saying why. It compares every `--budget-*`
# and `--max-*` flag value on the check-always-on.sh line(s) of .github/workflows/ci.yml at <base-ref>
# with the working tree. A value that went up, or a flag that was removed, fails unless the pull
# request description has a line of its own: `budget-raised: <why>`, with a real reason (not empty,
# not the literal `<why>`). A lowered or unchanged value passes. Each changed flag is printed as
# `flag old -> new`.
#
# CLAUDE.md's Lessons step 3 asks that a kit change not add always-on cost; the budgets in ci.yml are
# what holds that line, so moving them needs a stated reason a reviewer reads.
#
# Usage: scripts/check-budget-change.sh <base-ref> [--description-file <file>]
#   <base-ref>          the branch the change merges into
#   --description-file  the pull request description, for its `budget-raised:` line
set -euo pipefail

usage() { echo "usage: scripts/check-budget-change.sh <base-ref> [--description-file <file>]" >&2; exit 2; }
[ "$#" -ge 1 ] || usage
base=$1
shift
description_file=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --description-file) [ "$#" -ge 2 ] || usage; description_file=$2; shift 2 ;;
    *) usage ;;
  esac
done
if [ -n "$description_file" ] && [ ! -r "$description_file" ]; then
  echo "cannot read $description_file" >&2
  exit 2
fi

workflow=.github/workflows/ci.yml
merge_base=$(git merge-base "$base" HEAD) || {
  echo "$base and HEAD share no commit, so there is no change to check; check the base branch" >&2
  exit 2
}

# Prints "<flag> <value>" for each budget flag on a check-always-on.sh line, read from stdin.
budget_flags() {
  grep 'check-always-on\.sh' | grep -oE -e '--(budget|max)-[a-z-]+[[:space:]]+[0-9]+' | sed -E 's/[[:space:]]+/ /' | sort -u || true
}

old_flags=$(git show "$merge_base:$workflow" 2>/dev/null | budget_flags || true)
new_flags=$(budget_flags < "$workflow" || true)

problems=0
while IFS=' ' read -r flag old_value; do
  [ -n "$flag" ] || continue
  new_value=$(printf '%s\n' "$new_flags" | awk -v f="$flag" '$1 == f { print $2; exit }')
  if [ -z "$new_value" ]; then
    echo "removed  $flag $old_value -> (gone)"
    problems=$((problems + 1))
  elif [ "$new_value" -gt "$old_value" ]; then
    echo "raised   $flag $old_value -> $new_value"
    problems=$((problems + 1))
  elif [ "$new_value" -lt "$old_value" ]; then
    echo "lowered  $flag $old_value -> $new_value"
  fi
done <<< "$old_flags"

if [ "$problems" -eq 0 ]; then
  echo "ok   no always-on budget raised or removed"
  exit 0
fi

reason=""
[ -z "$description_file" ] || reason=$(sed -nE 's/^[[:space:]]*budget-raised:[[:space:]]*(.*)$/\1/Ip' "$description_file" | head -n 1)
reason=$(printf '%s' "$reason" | sed -E 's/[[:space:]]+$//')
if [ -n "$reason" ] && [ "$reason" != "<why>" ]; then
  echo "ok   budget change stated: $reason"
  exit 0
fi

echo "FAIL an always-on budget in $workflow was raised or removed without a reason" >&2
echo "     lower it, or add a line to the pull request description: budget-raised: <why>" >&2
exit 1
