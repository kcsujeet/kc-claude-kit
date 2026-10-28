#!/usr/bin/env bash
# structure §S11: a context, hook, or non-component module sitting in a
# components folder. Runs over every file the diff touches AND, when repo-root
# is a git work tree, every untracked file, since a newly created misplaced file
# is not in `git diff` until it is added.
#
# Usage: misplaced-modules.sh <diff-file|-> [repo-root]
# repo-root defaults to the current directory; files are read from there.
# Prints one hit per line:
#   path:line: <line text>                   a `createContext(` call under components/
#   path:1: hook under components/, belongs with hooks
#   path:1: non-component module under components/, likely a util, type, or context
# Adapt the folder name and extensions to the target repo's layout if it differs.
# Exits 0 with or without hits, 2 on a usage error.
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=../../../scripts/lib/diff-lines.sh
. "$script_dir/../../../scripts/lib/diff-lines.sh"

usage_suffix=' [repo-root]'
if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then kc_require_diff_arg "$(basename "$0")" "" "$usage_suffix"; fi
kc_require_diff_arg "$(basename "$0")" "$1" "$usage_suffix"
repo_root=${2:-.}
if [ ! -d "$repo_root" ]; then
  echo "$(basename "$0"): repo root is not a directory: $repo_root" >&2
  exit 2
fi

untracked_files=""
if git -C "$repo_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  untracked_files=$(git -C "$repo_root" ls-files --others --exclude-standard)
fi

{ kc_changed_files "$1"; printf '%s\n' "$untracked_files"; } | sort -u | while IFS= read -r candidate; do
  [ -n "$candidate" ] || continue
  [ -f "$repo_root/$candidate" ] || continue
  case "$candidate" in
    components/*|*/components/*) ;;
    *) continue ;;
  esac
  CANDIDATE=$candidate awk '/createContext\(/ { printf "%s:%d: %s\n", ENVIRON["CANDIDATE"], NR, $0 }' "$repo_root/$candidate"
  case "$(basename "$candidate")" in
    index.ts|index.js|*.test.*|*.spec.*|*.stories.*) ;;
    use-*|use[A-Z]*) echo "$candidate:1: hook under components/, belongs with hooks" ;;
    *.ts|*.js) echo "$candidate:1: non-component module under components/, likely a util, type, or context" ;;
  esac
done
