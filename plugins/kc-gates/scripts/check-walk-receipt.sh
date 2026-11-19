#!/usr/bin/env bash
# Checks a review's walk receipt against the `walk-item:` lines select-gates.sh printed, so a
# review that changed behaviour nobody ran cannot be posted or approved on the strength of "I
# looked at the code" (verification-gate §V11).
#
# Usage: check-walk-receipt.sh <select-gates-output> <walk-receipt.tsv>
#
#   <select-gates-output>  select-gates.sh's output saved to a file; only its `walk-item: <path>`
#                          lines are read. None means nothing to walk: the check passes.
#   <walk-receipt.tsv>     one line per item, tab-separated: <path> <what was seen> <evidence>
#                          (kc-code-review saves it as walk-receipt.tsv beside review.diff).
#                          Evidence is an existing screenshot or recording (png, jpg, jpeg, gif,
#                          webp, mp4, mov, webm; a relative path is read from the receipt's
#                          folder), or a request line with its status (`GET /orders/7 200`).
#
# Prints one line per problem (`walk-item <path>: <problem>`): no receipt line, nothing seen, or
# evidence that is neither. Exits 0 when every item has a full line, 1 when any does not, 2 on a
# usage error or an unreadable input.
set -euo pipefail

script_name=$(basename "$0")
[ "$#" -eq 2 ] || { echo "usage: $script_name <select-gates-output> <walk-receipt.tsv>" >&2; exit 2; }
[ -r "$1" ] || { echo "$script_name: cannot read $1" >&2; exit 2; }
select_output=$1
receipt=$2
receipt_dir=$(dirname "$receipt")

items=$(sed -n 's/^walk-item: //p' "$select_output")
[ -n "$items" ] || exit 0

media_pattern='\.(png|jpe?g|gif|webp|mp4|mov|webm)$'
request_pattern='^(GET|HEAD|POST|PUT|PATCH|DELETE)[[:space:]]+[^[:space:]]+.*[[:space:]][1-5][0-9][0-9]([^0-9]|$)'
problems=0
problem() { echo "walk-item $1: $2"; problems=$((problems + 1)); }

while IFS= read -r item; do
  [ -n "$item" ] || continue
  line=""
  if [ -r "$receipt" ]; then
    line=$(awk -F'\t' -v item="$item" '$1 == item { print; exit }' "$receipt")
  fi
  if [ -z "$line" ]; then
    problem "$item" "no receipt line in $receipt: walk it in the running app or at the API, then write <path><TAB><what was seen><TAB><evidence>"
    continue
  fi
  seen=$(printf '%s' "$line" | awk -F'\t' '{ print $2 }')
  evidence=$(printf '%s' "$line" | awk -F'\t' '{ print $3 }')
  if ! printf '%s' "$seen" | grep -q '[^[:space:]]'; then
    problem "$item" "nothing seen: say what the app or the API showed for this file's behaviour"
    continue
  fi
  if printf '%s' "$evidence" | grep -Eiq "$media_pattern"; then
    if [ ! -f "$evidence" ] && [ ! -f "$receipt_dir/$evidence" ]; then
      problem "$item" "evidence file does not exist: $evidence"
    fi
  elif ! printf '%s' "$evidence" | grep -Eq "$request_pattern"; then
    problem "$item" "evidence is neither an existing screenshot or recording nor a request line with its status (GET /path 200): $evidence"
  fi
done <<EOF
$items
EOF

[ "$problems" -eq 0 ]
