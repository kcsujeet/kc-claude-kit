#!/usr/bin/env bash
# Creates or removes the git worktree a work unit lives in.
# Git worktrees: https://git-scm.com/docs/git-worktree
#
# Usage:
#   worktree.sh create <repo> <run-id> <unit-id> <base-ref>
#     → {"path": "...", "branch": "autopilot/<run-id>/<unit-id>"}
#     Idempotent: an existing worktree is reused. Copies
#     <repo>/.claude/autopilot.json into it when missing.
#   worktree.sh remove <repo> <path>   (keeps the branch)
#     Refuses when the worktree has uncommitted changes, ignoring the
#     copied autopilot.json.
# Exit: 0 ok; 1 refused (uncommitted changes); other non-zero = git error
# (git's own status); 2 jq missing.
set -euo pipefail

command -v jq >/dev/null 2>&1 || { echo "autopilot: jq is required" >&2; exit 2; }

create() {
  local repo=$1 run_id=$2 unit_id=$3 base_ref=$4 path branch
  repo=$(cd "$repo" && pwd)
  path="$repo/.claude/worktrees/autopilot-$run_id-$unit_id"
  branch="autopilot/$run_id/$unit_id"
  if [ ! -d "$path" ]; then
    mkdir -p "$repo/.claude/worktrees"
    git -C "$repo" worktree add -q -b "$branch" "$path" "$base_ref"
  fi
  if [ -f "$repo/.claude/autopilot.json" ] && [ ! -f "$path/.claude/autopilot.json" ]; then
    mkdir -p "$path/.claude"
    cp "$repo/.claude/autopilot.json" "$path/.claude/autopilot.json"
  fi
  jq -cn --arg path "$path" --arg branch "$branch" '{path: $path, branch: $branch}'
}

remove() {
  local repo=$1 path=$2
  if [ -n "$(git -C "$path" status --porcelain -- . ':!.claude/autopilot.json')" ]; then
    echo "worktree: $path has uncommitted changes" >&2
    exit 1
  fi
  git -C "$repo" worktree remove --force "$path"
}

case "${1:-}" in
  create) shift; create "$@" ;;
  remove) shift; remove "$@" ;;
  *) echo "usage: worktree.sh create <repo> <run-id> <unit-id> <base-ref> | remove <repo> <path>" >&2; exit 1 ;;
esac
