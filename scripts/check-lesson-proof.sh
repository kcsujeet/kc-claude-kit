#!/usr/bin/env bash
# Fails when a change since <base> edits a rule (a skill, a skill reference, an agent or the working
# agreement) without proof that the rule catches something: an eval case or a script test changed in
# the same change. A rule that only moves words says so in the pull request description, on a line
# of its own: `wording-only: <why>`.
#
# CLAUDE.md's Lessons step 4 asks for that proof; a skip has to be stated here, so the reviewer
# reads the reason.
#
# Usage: scripts/check-lesson-proof.sh <base-ref> [--body-file <file>]
#   <base-ref>    the branch the change merges into
#   --body-file   the pull request description, for its `wording-only:` line
set -euo pipefail

usage() { echo "usage: scripts/check-lesson-proof.sh <base-ref> [--body-file <file>]" >&2; exit 2; }
[ "$#" -ge 1 ] || usage
base=$1
shift
body_file=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --body-file) [ "$#" -ge 2 ] || usage; body_file=$2; shift 2 ;;
    *) usage ;;
  esac
done
if [ -n "$body_file" ] && [ ! -r "$body_file" ]; then
  echo "cannot read $body_file" >&2
  exit 2
fi

merge_base=$(git merge-base "$base" HEAD)
changed=$(git diff --name-only "$merge_base" HEAD)

rules=$(printf '%s\n' "$changed" | grep -E '^plugins/[^/]+/(skills/.+\.md|agents/[^/]+\.md|rules/kc-working-agreement\.md)$' || true)
if [ -z "$rules" ]; then
  echo "ok   no rule changed"
  exit 0
fi

proof=$(printf '%s\n' "$changed" | grep -E '^(plugins/[^/]+/(evals|tests)/|scripts/tests/)' || true)
if [ -n "$proof" ]; then
  echo "ok   rules changed with proof: $(printf '%s\n' "$proof" | wc -l | tr -d ' ') eval or test file(s)"
  exit 0
fi

reason=""
[ -z "$body_file" ] || reason=$(sed -nE 's/^[[:space:]]*wording-only:[[:space:]]*(.*)$/\1/Ip' "$body_file" | head -n 1)
if [ -n "$reason" ]; then
  echo "ok   rules changed, wording only: $reason"
  exit 0
fi

echo "FAIL these rules changed with no eval case or script test beside them:"
printf '%s\n' "$rules" | sed 's/^/       /'
echo "     Prove the rule catches its case (an eval under the plugin's evals/, or a script with a test),"
echo "     or, when only the words move, add a line to the pull request description: wording-only: <why>"
exit 1
