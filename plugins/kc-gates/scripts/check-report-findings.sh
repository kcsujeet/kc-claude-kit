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
# `Dropped:` (matched by file basename and line number, in either spelling) that gives the reason.
#
# Prints one line per missing finding. Exits 0 when none is missing, 1 when any is, 2 on a usage
# error or an unreadable reply.
set -euo pipefail

script_name=$(basename "$0")
[ "$#" -eq 2 ] || { echo "usage: $script_name <verdicts-dir> <reply-file|->" >&2; exit 2; }
verdicts_dir=$1
reply_arg=$2
if [ "$reply_arg" != - ] && [ ! -r "$reply_arg" ]; then
  echo "$script_name: cannot read $reply_arg" >&2
  exit 2
fi
[ -d "$verdicts_dir" ] || exit 0

reply=$(cat "$reply_arg")
dropped_lines=$(printf '%s\n' "$reply" | grep -E '^[[:space:]]*(-|\*)?[[:space:]]*\**Dropped:' || true)

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

missing=0
while IFS= read -r finding; do
  [ -n "$finding" ] || continue
  file_name=${finding%:*}
  line_number=${finding##*:}
  pattern="(^|[^A-Za-z0-9_.-])$(printf '%s' "$file_name" | sed 's/[][\.^$*+?(){}|/]/\\&/g'):L?$line_number([^0-9]|$)"
  if printf '%s\n' "$reply" | grep -Eq "$pattern"; then continue; fi
  # A Dropped: line may give the file and the line apart ("cart.ts line 4").
  escaped_name=$(printf '%s' "$file_name" | sed 's/[][\.^$*+?(){}|/]/\\&/g')
  if printf '%s\n' "$dropped_lines" | grep -E "(^|[^A-Za-z0-9_.-])$escaped_name([^A-Za-z0-9_.-]|$)" | grep -Eq "(^|[^0-9])L?$line_number([^0-9]|$)"; then continue; fi
  echo "a gate found $finding and the reply neither reports it nor lists it under Dropped: with a reason"
  missing=1
done <<EOF
$findings
EOF
exit "$missing"
