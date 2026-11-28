#!/usr/bin/env bash
# Prints the git tree hash of a change's content, so a review record can be keyed on what was
# reviewed and not on a commit: the same content committed twice, amended or rebased keeps one hash.
#
# Usage: tree-hash.sh [<rev>]
#
#   (no argument)  The working tree as it is now: tracked files as they stand (edits and deletions
#                  included) plus untracked files that are not ignored, hashed through a temporary
#                  index, so the repo's own index, HEAD and files are never touched.
#   <rev>          The tree of that commit (`git rev-parse <rev>^{tree}`).
#
# Exits 0 and prints the 40-character hash; 1 when it cannot be made.
set -euo pipefail

script_name=$(basename "$0")
fail() { echo "$script_name: $1" >&2; exit 1; }

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "not inside a git work tree"
if [ "$#" -gt 1 ]; then
  echo "usage: $script_name [<rev>]" >&2
  exit 2
fi
if [ "$#" -eq 1 ]; then
  git rev-parse --verify --quiet "$1^{tree}" || fail "no tree for $1"
  exit 0
fi

root=$(git rev-parse --show-toplevel)
index_file=$(mktemp "${TMPDIR:-/tmp}/kc-tree-index.XXXXXX")
trap 'rm -f "$index_file"' EXIT
rm -f "$index_file"
export GIT_INDEX_FILE=$index_file
cd "$root"
if git rev-parse --verify --quiet HEAD >/dev/null; then
  git read-tree HEAD
fi
git add -A
git write-tree
