#!/usr/bin/env bash
# One writer: lists the edits in the gates' verdict blocks that may be applied as written, and the
# ones that may not. A gate writes code only for a mechanical fix (a rename, a deleted or moved
# line); every other fix is written by the caller, who has read every finding and the code. Code
# a gate writes for one finding is written blind to the other findings and to the uses of what it
# changes, and applying it as written is how fixes opened new gaps.
#
# An edit is mechanical when it is a DELETE or a MOVE, or an EDIT whose REPLACE side holds at most
# two lines and adds no condition its SEARCH side lacks (`if`, `unless`, `case`, `when`, `switch`,
# `else`, `?`, `&&`, `||`, `??`). A CREATE is never mechanical.
#
# Usage: check-gate-fixes.sh <verdicts-dir>
#   <verdicts-dir>  a review's verdicts/ folder: one `<gate>.txt` block per gate
#
# Prints one line per edit, `apply <gate>: <kind> <path>` or `write <gate>: <kind> <path>: <why>`,
# then `edits: <n> to apply, <n> to write from the finding`. Exits 0, or 2 on a usage error.
set -euo pipefail

[ "$#" -eq 1 ] || { echo "usage: check-gate-fixes.sh <verdicts-dir>" >&2; exit 2; }
[ -d "$1" ] || { echo "check-gate-fixes.sh: not a directory: $1" >&2; exit 2; }

apply_count=0
write_count=0
for block in "$1"/*.txt; do
  [ -f "$block" ] || continue
  gate=$(basename "$block" .txt)
  while IFS= read -r line; do
    case "$line" in
      apply*) apply_count=$((apply_count + 1)) ;;
      write*) write_count=$((write_count + 1)) ;;
    esac
    printf '%s\n' "$line"
  done < <(awk -v gate="$gate" '
    function conditions(text,   found) {
      found = ""
      if (text ~ /(^|[^A-Za-z0-9_])(if|unless|case|when|switch|else|elsif|elif)([^A-Za-z0-9_]|$)/) found = found "branch "
      if (text ~ /&&|\|\||\?\?|[^?.]\?[^.?]/) found = found "operator "
      return found
    }
    function finish_edit(   why) {
      why = ""
      if (replace_lines > 2) why = replace_lines " replacement lines"
      else if (conditions(replace_text) != "" && conditions(search_text) == "") why = "adds a condition"
      if (why == "") printf "apply %s: EDIT %s\n", gate, edit_path
      else printf "write %s: EDIT %s: %s; write the fix from the finding\n", gate, edit_path, why
    }
    state == "" && /^EDIT / { edit_path = substr($0, 6); state = "edit"; next }
    state == "" && /^CREATE / { printf "write %s: CREATE %s: a new file; write the fix from the finding\n", gate, substr($0, 8); state = "create"; next }
    state == "" && /^(DELETE|MOVE) / { printf "apply %s: %s\n", gate, $0; next }
    state == "edit" && /^<<<<<<< SEARCH/ { state = "search"; search_text = ""; next }
    state == "search" && /^======= REPLACE/ { state = "replace"; replace_text = ""; replace_lines = 0; next }
    state == "search" { search_text = search_text "\n" $0; next }
    state == "replace" && /^>>>>>>> END/ { finish_edit(); state = ""; next }
    state == "replace" { replace_text = replace_text "\n" $0; if ($0 ~ /[^ \t]/) replace_lines++; next }
    state == "create" && /^>>>>>>> END/ { state = ""; next }
  ' "$block")
done
echo "edits: $apply_count to apply, $write_count to write from the finding"
