#!/usr/bin/env bash
# naming §N5: every line in the repo's tracked files where <name> appears as a
# whole word, so a bare-word declaration's collisions are listed rather than
# eyeballed. A lookup, not a diff sweep: it takes one identifier, not a diff.
#
# Usage: name-collisions.sh <name> [repo-root]
# repo-root defaults to the current directory and must be a git work tree. The
# match is `git grep -n -w -F`: literal text, bounded by non-word characters
# (letters, digits and `_`), over tracked files only.
# Prints `path:line: text` per hit, paths relative to repo-root, in git's order.
# Exits 0 with or without hits, 2 on a usage error.
set -euo pipefail

script_name=$(basename "$0")
if [ "$#" -lt 1 ] || [ "$#" -gt 2 ] || [ -z "$1" ]; then
  echo "usage: $script_name <name> [repo-root]" >&2
  exit 2
fi
search_name=$1
repo_root=${2:-.}
if ! git -C "$repo_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "$script_name: not a git work tree: $repo_root" >&2
  exit 2
fi

# git grep exits 1 when nothing matches; only a status above 1 is an error.
set +e
hits=$(git -C "$repo_root" grep -n -w -F -I --no-color -e "$search_name" -- .)
grep_status=$?
set -e
if [ "$grep_status" -gt 1 ]; then
  echo "$script_name: git grep failed with status $grep_status" >&2
  exit 2
fi
[ -n "$hits" ] || exit 0

# `path:line:text` becomes `path:line: text`.
printf '%s\n' "$hits" | awk '{
  first = index($0, ":")
  rest = substr($0, first + 1)
  second = index(rest, ":")
  print substr($0, 1, first) substr(rest, 1, second) " " substr(rest, second + 1)
}'
