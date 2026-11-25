#!/usr/bin/env bash
# Checks a review report names every finding the gates confirmed, so a confirmed finding never
# vanishes between a gate's block and the report (kc-code-review Step 4 saves each gate block to
# verdicts/<gate>.txt in the review folder; guard-review-walk.sh runs this on a verdict reply).
#
# Usage: check-report-findings.sh <verdicts-dir> <reply-file|->
#
#   <verdicts-dir>  the folder of saved gate blocks (*.txt); a missing or empty one has nothing
#                   to check.
#   <reply-file|->  the review reply; - reads stdin.
#
# Every finding line under FINDINGS: in those blocks that cites a path with a line number
# (`path:line`, `path:Lline`, optionally with `@sha`) must appear in the reply as
# `<basename>:<line>` or `<basename>:L<line>`, or on a line of the reply starting with
# `Dropped:` that names it as `<basename>:<line>`, `<basename>:L<line>` or `<basename> line <N>`
# and gives reason text after it. A Dropped: line that names only the file and line
# (`Dropped: cart.ts:4`), or the file with no line (`Dropped: cart.ts (ran 4 tests)`), does not count.
#
# Prints one line per missing finding. Exits 0 when none is missing, 1 when any is, 2 on a usage
# error or an unreadable reply.
set -euo pipefail

script_name=$(basename "$0")
[ "$#" -eq 2 ] || { echo "usage: $script_name <verdicts-dir> <reply-file|->" >&2; exit 2; }
verdicts_dir=$1
reply_arg=$2
reply_from_stdin=false
[ "$reply_arg" = - ] && reply_from_stdin=true
reply_file_is_unreadable=false
[ ! -r "$reply_arg" ] && reply_file_is_unreadable=true
if ! "$reply_from_stdin" && "$reply_file_is_unreadable"; then
  echo "$script_name: cannot read $reply_arg" >&2
  exit 2
fi

reply=$(cat "$reply_arg")
reported_lines=$(grep -Ev '^[[:space:]]*(-|\*)?[[:space:]]*\**Dropped:' <<<"$reply" || true)
dropped_lines=$(grep -E '^[[:space:]]*(-|\*)?[[:space:]]*\**Dropped:' <<<"$reply" || true)

# True when a Dropped: line names <file> <line> as `file:line`, `file:Lline` or `file line N` and has
# reason text after it (other file:line references on the line are not reason text).
is_dropped_with_reason() {
  local escaped_name=$1 line_number=$2 dropped_line reason
  local name_pattern="(^|[^A-Za-z0-9_.-])$escaped_name(:L?|[[:space:]]+line[[:space:]]+)$line_number([^0-9]|\$)"
  while IFS= read -r dropped_line; do
    [[ $dropped_line =~ $name_pattern ]] || continue
    reason=${dropped_line#*"${BASH_REMATCH[0]}"}
    reason=$(sed -E 's/[A-Za-z0-9_.\/-]+(:L?|[[:space:]]+line[[:space:]]+)[0-9]+//g' <<<"$reason")
    [[ $reason =~ [A-Za-z] ]] && return 0
  done <<<"$dropped_lines"
  return 1
}

# One "basename:line" per cited finding, each once.
findings=$(
  for block in "$verdicts_dir"/*.txt; do
    [ -f "$block" ] || continue
    awk '
      /^[[:space:]]*FINDINGS:/ { in_findings = 1; next }
      /^[[:space:]]*[A-Z][A-Z _-]*:[[:space:]]*$/ { in_findings = 0 }
      in_findings && /^[[:space:]]*(-|\*)/ {
        if (match($0, /[A-Za-z0-9_.\/-]+:L?[0-9]+(@[0-9a-f]+)?/)) {
          cited = substr($0, RSTART, RLENGTH)
          sub(/@[0-9a-f]+$/, "", cited)
          sub(/:L/, ":", cited)
          n = split(cited, parts, "/")
          print parts[n]
        }
      }
    ' "$block"
  done | sort -u
)

has_missing_finding=0
while IFS= read -r finding; do
  [ -n "$finding" ] || continue
  file_name=${finding%:*}
  line_number=${finding##*:}
  escaped_name=$(printf '%s' "$file_name" | sed 's/[][\.^$*+?(){}|/]/\\&/g')
  pattern="(^|[^A-Za-z0-9_.-])$escaped_name:L?$line_number([^0-9]|$)"
  if grep -Eq "$pattern" <<<"$reported_lines"; then continue; fi
  if is_dropped_with_reason "$escaped_name" "$line_number"; then continue; fi
  echo "a gate found $finding and the reply neither reports it nor lists it under Dropped: with a reason"
  has_missing_finding=1
done <<EOF
$findings
EOF
exit "$has_missing_finding"
