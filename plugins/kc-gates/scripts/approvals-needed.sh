#!/usr/bin/env bash
# Lists every phrase the user must type for the steps still ahead on a branch, so a guard that blocks
# asks for all of them in one message instead of one per block. A guard accepts a phrase typed any time
# on the branch, so the steps then run after that one message.
#
# Usage: approvals-needed.sh [--dir <repo>]
#
# Runs, in check-only mode (KC_CHECK_ONLY=1: a guard's block then lists nothing itself), the guards
# that take typed words, each on the command of a step still ahead, in <repo>:
#   - guard-prose-rule.sh on `git commit` (what is staged): "approve prose"
#   - guard-loop-stop.sh on `git commit` and `gh pr create` (the branch from the default branch):
#     "approve rework"
#   - guard-merge.sh on `gh pr merge` (the branch's pull request): "approve merge"; before the pull
#     request exists, the same phrase when HEAD has a review receipt that is not clean.
# A guard that would block only for want of Claude's own work (a pass receipt, a checklist) asks no
# phrase and is not listed.
#
# Prints one phrase per line, each once; nothing when no step needs one. Exits 0; 2 on a usage error.
set -u

scripts_dir=$(dirname "$0")
dir=.
case "${1:-}" in
  --dir) [ "$#" -eq 2 ] || { echo "usage: approvals-needed.sh [--dir <repo>]" >&2; exit 2; }; dir=$2 ;;
  "") ;;
  *) echo "usage: approvals-needed.sh [--dir <repo>]" >&2; exit 2 ;;
esac

# Succeeds when guard $1 blocks the command $2 run in $dir.
guard_blocks() {
  local guard=$1 command=$2 payload
  payload=$(jq -nc --arg cwd "$dir" --arg command "$command" \
    '{hook_event_name: "PreToolUse", tool_name: "Bash", cwd: $cwd, tool_input: {command: $command}}')
  printf '%s' "$payload" | KC_CHECK_ONLY=1 bash "$scripts_dir/$guard" 2>/dev/null | grep -q '"permissionDecision":"deny"'
}

command -v jq >/dev/null 2>&1 || exit 0
git -C "$dir" rev-parse -q --verify HEAD >/dev/null 2>&1 || exit 0

if guard_blocks guard-prose-rule.sh "git commit -m check"; then echo "approve prose"; fi
if guard_blocks guard-loop-stop.sh "git commit -m check" || guard_blocks guard-loop-stop.sh "gh pr create --fill"; then
  echo "approve rework"
fi
head=$(git -C "$dir" rev-parse HEAD)
if guard_blocks guard-merge.sh "gh pr merge --squash"; then
  echo "approve merge"
elif bash "$scripts_dir/ready-receipt.sh" check "$head" --pass >/dev/null 2>&1 \
  && ! bash "$scripts_dir/ready-receipt.sh" check "$head" --clean >/dev/null 2>&1; then
  echo "approve merge"
fi
exit 0
