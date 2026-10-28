#!/usr/bin/env bash
# structure §S5: `if` statements opened inside another `if` or `else` block,
# reported only where the nested `if` is on a line the diff adds.
#
# Nesting is not visible in added lines alone, so this reads each changed file
# from repo-root (the new side of the diff must be checked out there) with an
# indentation-aware pass: an `if` opened while an `if` or `else` block at a lower
# indent is still open is a hit, and `else if` at the same indent is a sibling,
# not nesting. It is a candidate generator: it over-matches code whose
# indentation does not follow its structure and misses a nested `if` on the same
# line as its parent, so still read each changed function's control flow.
#
# Usage: nested-ifs.sh <diff-file|-> [repo-root]
# repo-root defaults to the current directory.
# Prints `path:line: text` per hit. Exits 0 with or without hits, 2 on a usage
# error.
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

# Read the diff once, so stdin works.
added_lines=$(kc_added_lines "$1")
[ -n "$added_lines" ] || exit 0

printf '%s\n' "$added_lines" | cut -f1 | sort -u | while IFS= read -r changed_file; do
  [ -f "$repo_root/$changed_file" ] || continue
  nested_line_numbers=$(awk '
    function indentOf(line) { match(line, /^[ \t]*/); return RLENGTH }
    /^[ \t]*$/ { next }
    {
      ind = indentOf($0)
      isIf = $0 ~ /^[ \t]*(\}[ \t]*)?(else[ \t]+)?if[ \t]*\(/
      isElse = !isIf && $0 ~ /^[ \t]*(\}[ \t]*)?else([^A-Za-z0-9_]|$)/
      for (d in open) if (open[d] && d + 0 >= ind) open[d] = 0
      if (isIf) for (d in open) if (open[d] && d + 0 < ind) { print NR; break }
      if (isIf || isElse) open[ind] = 1
    }' "$repo_root/$changed_file")
  [ -n "$nested_line_numbers" ] || continue
  printf '%s\n' "$added_lines" | NESTED="$nested_line_numbers" FILE="$changed_file" awk -F '\t' '
    BEGIN { n = split(ENVIRON["NESTED"], lines, "\n"); for (i = 1; i <= n; i++) nested[lines[i]] = 1 }
    $1 == ENVIRON["FILE"] && ($2 in nested) {
      text = $0
      sub(/^[^\t]*\t[^\t]*\t/, "", text)
      printf "%s:%s: %s\n", $1, $2, text
    }'
done
