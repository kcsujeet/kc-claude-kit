#!/usr/bin/env bash
# simplicity §P1: each file the diff adds that shares much of its code with a file already in the
# repo, test helpers and fixtures included, so a near copy is consolidated into one unit instead of
# landing beside the original. Each hit is a pair for the gate to judge, not a finding.
#
# Usage: near-copies.sh <diff-file|-> [repo-root]
# Each line is compared by its shape: trimmed, with names, constants, strings and numbers blanked,
# imports and comments left out. A file in repo-root (default: the current directory; tracked and
# untracked) with the same extension and between half and twice as many such lines that shares at
# least 3 of them, and at least half of the added file's, is a near copy.
# Prints `path:1: near copy of <other> (<shared> of <distinctive> lines)` per pair, at most
# 3 per added file, the closest first.
# Exits 0 with or without hits, 2 on a usage error. Portable to bash 3.2 and BSD awk.
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=../../../scripts/lib/diff-lines.sh
. "$script_dir/../../../scripts/lib/diff-lines.sh"

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then kc_require_diff_arg "$(basename "$0")" "" " [repo-root]"; fi
kc_require_diff_arg "$(basename "$0")" "$1" " [repo-root]"
repo_root=${2:-.}
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
diff_copy="$work_dir/review.diff"
cat "$1" > "$diff_copy"
kc_added_lines "$diff_copy" > "$work_dir/added.tsv"

{ kc_added_files "$diff_copy" | grep -E "$KC_CODE_PATHS" || true; } | while IFS= read -r added_path; do
  [ -f "$repo_root/$added_path" ] || continue
  extension=${added_path##*.}
  { git -C "$repo_root" ls-files -- "*.$extension"; git -C "$repo_root" ls-files --others --exclude-standard -- "*.$extension"; } 2>/dev/null |
    grep -vxF "$added_path" > "$work_dir/candidates" || true
  (cd "$repo_root" && awk -v path="$added_path" -v list="$work_dir/candidates" '
    # Names, constants, strings and numbers are blanked, so a copy that renamed them still matches.
    function shape(line) {
      gsub(/^[ \t]+|[ \t]+$/, "", line)
      gsub(/"[^"]*"|\x27[^\x27]*\x27|\x60[^\x60]*\x60/, "S", line)
      gsub(/[A-Z][A-Z0-9_]+/, "K", line)
      gsub(/[0-9]+/, "0", line)
      if (match(line, /^(export )?(const|let|var|function|def|class) [A-Za-z_$][A-Za-z0-9_$]*/)) {
        line = substr(line, 1, RSTART + RLENGTH - 1)
        sub(/[A-Za-z_$][A-Za-z0-9_$]*$/, "N", line)
        line = line substr($0, 1, 0)
      }
      return line
    }
    function counted(line) {
      if (length(line) < 8) return 0
      if (line ~ /^(import|from|require|export \{|export default|#|\/\/|\/\*|\*)/) return 0
      return line ~ /[A-Za-z]/
    }
    function read_shapes(file, into,    raw, n, s) {
      n = 0
      while ((getline raw < file) > 0) { s = shape(raw); if (counted(s)) { into[s] = 1; n++ } }
      close(file)
      return n
    }
    BEGIN {
      own_count = read_shapes(path, own)
      if (own_count < 3) exit
      while ((getline candidate < list) > 0) {
        split("", other); other_count = read_shapes(candidate, other)
        if (other_count < own_count / 2 || other_count > own_count * 2) continue
        shared = 0
        for (s in own) if (s in other) shared++
        if (shared >= 3 && shared * 2 >= own_count) printf "%d\t%d\t%s\n", shared, own_count, candidate
      }
    }
  ') | sort -t "$(printf '\t')" -k1,1nr -k3,3 | head -n 3 | awk -F '\t' -v path="$added_path" '
    { printf "%s:1: near copy of %s (%d of %d lines)\n", path, $3, $1, $2 }
  '
done
