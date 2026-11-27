#!/usr/bin/env bash
# Lists cleanup candidates in a repo and deletes nothing: worktrees and local branches merged into the
# default branch (worktrees only when clean), stashes, and local branches whose remote branch is gone.
# Usage: list-cleanup.sh --repo <dir>   (use --repo . for the current repo; no arguments exits 2)
set -euo pipefail

repo=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) repo=${2:?--repo needs a directory}; shift 2 ;;
    *) echo "usage: list-cleanup.sh --repo <dir>" >&2; exit 2 ;;
  esac
done
[ -n "$repo" ] || { echo "usage: list-cleanup.sh --repo <dir>" >&2; exit 2; }
cd "$repo"

git fetch --quiet 2>/dev/null || true

default=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)
if [ -z "$default" ]; then
  for candidate in origin/main origin/master main master; do
    if git rev-parse --verify --quiet "$candidate" >/dev/null; then default=$candidate; break; fi
  done
fi
[ -n "$default" ] || { echo "no default branch found" >&2; exit 1; }
default_local=${default#origin/}
main_worktree=$(git worktree list --porcelain | awk '/^worktree /{print substr($0, 10); exit}')

merged=$(git for-each-ref --merged "$default" --format='%(refname:short)' refs/heads)
is_merged() { printf '%s\n' "$merged" | grep -qxF -- "$1"; }

echo "default branch: $default"
echo "## merged worktrees (clean)"
checked_out=" "
path="" branch=""
while IFS= read -r line; do
  case "$line" in
    "worktree "*) path=${line#worktree }; branch="" ;;
    "branch "*) branch=${line#branch refs/heads/} ;;
    "")
      if [ -n "$path" ] && [ -n "$branch" ]; then
        checked_out="$checked_out$branch "
        if [ "$path" != "$main_worktree" ] && [ "$branch" != "$default_local" ] && is_merged "$branch" \
          && [ -z "$(git -C "$path" status --porcelain)" ]; then
          echo "worktree $path ($branch)"
        fi
      fi
      path="" branch="" ;;
  esac
done < <(git worktree list --porcelain; echo)

echo "## merged local branches"
while IFS= read -r branch; do
  [ "$branch" = "$default_local" ] && continue
  case "$checked_out" in *" $branch "*) continue ;; esac
  echo "branch $branch"
done <<< "$merged"

echo "## stashes"
git stash list --format='%gd %ci %s' | sed 's/^/stash /'

echo "## local branches whose remote branch is gone"
git for-each-ref --format='%(refname:short) %(upstream:track)' refs/heads | awk '$2 == "[gone]" {print "gone " $1}'
