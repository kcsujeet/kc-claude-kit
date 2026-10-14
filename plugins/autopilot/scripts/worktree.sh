#!/usr/bin/env bash
# Creates or removes the git worktree a work unit lives in.
# Git worktrees: https://git-scm.com/docs/git-worktree
#
# Usage:
#   worktree.sh create <repo> <run-id> <unit-id> <base-ref>
#     → {"path": "...", "branch": "autopilot/<run-id>/<unit-id>"}
#     Idempotent: a registered worktree at the path is reused. An existing
#     branch is checked out (not recreated) so a removed unit keeps its
#     commits. Copies <repo>/.claude/autopilot.json into it when missing.
#   worktree.sh remove <repo> <path>   (keeps the branch)
#     Refuses when the worktree has uncommitted changes, ignoring the
#     copied autopilot.json and untracked symlinks.
# Exit: 0 ok; 1 refused (uncommitted changes, or a plain directory sits at
# the path); other non-zero = git error (git's own status); 2 jq missing.
set -euo pipefail

command -v jq >/dev/null 2>&1 || { echo "autopilot: jq is required" >&2; exit 2; }

is_worktree() {
  local list
  list=$(git -C "$1" worktree list --porcelain)
  grep -qxF "worktree $2" <<<"$list"
}

create() {
  local repo=$1 run_id=$2 unit_id=$3 base_ref=$4 path branch
  repo=$(cd "$repo" && pwd -P)
  path="$repo/.claude/worktrees/autopilot-$run_id-$unit_id"
  branch="autopilot/$run_id/$unit_id"
  if ! is_worktree "$repo" "$path"; then
    if [ -e "$path" ]; then
      echo "worktree: $path exists but is not a worktree of $repo" >&2
      exit 1
    fi
    mkdir -p "$repo/.claude/worktrees"
    if git -C "$repo" show-ref --verify -q "refs/heads/$branch"; then
      git -C "$repo" worktree add -q "$path" "$branch"
    else
      git -C "$repo" worktree add -q -b "$branch" "$path" "$base_ref"
    fi
  fi
  if [ -f "$repo/.claude/autopilot.json" ] && [ ! -f "$path/.claude/autopilot.json" ]; then
    mkdir -p "$path/.claude"
    cp "$repo/.claude/autopilot.json" "$path/.claude/autopilot.json"
  fi
  jq -cn --arg path "$path" --arg branch "$branch" '{path: $path, branch: $branch}'
}

remove() {
  local repo=$1 path=$2
  # Untracked symlinks (a linked node_modules, say) hold no work, so they do not count.
  local changes
  changes=$(git -C "$path" status --porcelain -- . ':!.claude/autopilot.json' | while IFS= read -r line; do
    case $line in '?? '*) [ -L "$path/${line#?? }" ] && continue ;; esac
    printf '%s\n' "$line"
  done)
  if [ -n "$changes" ]; then
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
