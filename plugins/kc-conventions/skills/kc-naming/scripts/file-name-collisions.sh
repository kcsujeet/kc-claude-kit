#!/usr/bin/env bash
# naming §N7: every file the diff creates, plus every untracked file in the
# repo, whose basename is shared with another file in the repo. Tabs, search
# results and stack traces show a file name without its path, so a shared
# basename sends a reader to the wrong file.
#
# Usage: file-name-collisions.sh <diff-file|-> [repo-root]
# repo-root defaults to the current directory and must be a git work tree; the
# basename count is taken over `git ls-files` plus untracked, non-ignored files.
# Prints `path:1: <basename> shared with N other file(s): <paths>` per hit.
# Framework-mandated names (index, page, layout, route) are still printed; the
# gate dismisses them in writing. A name with no collision still gets the
# generic-name read from the diff itself.
# Exits 0 with or without hits, 2 on a usage error.
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=../../../scripts/lib/diff-lines.sh
. "$script_dir/../../../scripts/lib/diff-lines.sh"

usage_suffix=' [repo-root]'
if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then kc_require_diff_arg "$(basename "$0")" "" "$usage_suffix"; fi
kc_require_diff_arg "$(basename "$0")" "$1" "$usage_suffix"
repo_root=${2:-.}
if ! git -C "$repo_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "$(basename "$0"): not a git work tree: $repo_root" >&2
  exit 2
fi

all_files=$( { git -C "$repo_root" ls-files; git -C "$repo_root" ls-files --others --exclude-standard; } | sort -u)
new_files=$( { kc_added_files "$1"; git -C "$repo_root" ls-files --others --exclude-standard; } | sort -u)

printf '%s\n' "$new_files" | while IFS= read -r new_file; do
  [ -n "$new_file" ] || continue
  base_name=$(basename "$new_file")
  others=$(printf '%s\n' "$all_files" | awk -F/ -v b="$base_name" -v self="$new_file" '$NF == b && $0 != self')
  [ -n "$others" ] || continue
  other_count=$(printf '%s\n' "$others" | wc -l | tr -d ' ')
  other_list=$(printf '%s\n' "$others" | paste -sd ',' - | sed 's/,/, /g')
  echo "$new_file:1: $base_name shared with $other_count other file(s): $other_list"
done
