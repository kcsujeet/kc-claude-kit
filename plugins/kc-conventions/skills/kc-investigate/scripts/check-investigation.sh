#!/usr/bin/env bash
# investigate §INV1 to §INV9: checks an investigation write-up before its findings are shared or a
# probe or fix is opened. Each box is ticked (`- [x] §INVn`) and carries evidence: a query or
# command in backticks, a link, or a number (a count, a timing, a `path:line`). §INV3 to §INV8 may say `n/a: <why>`
# instead, with the why in at least three words (min_reason_words below). §INV9 is followed by a Markdown table with a
# `cause` column whose rows each end in a verdict cell: `in` or `out` citing at least one of
# §INV1 to §INV8, or `open` naming the probe that would settle it.
#
# Usage: check-investigation.sh <write-up.md>
# Prints one line per problem and exits 1 when there is any, 0 when the write-up passes, 2 on a
# usage error or an unreadable file.
set -euo pipefail

script_name=$(basename "$0")
if [ "$#" -ne 1 ]; then
  echo "usage: $script_name <write-up.md>" >&2
  exit 2
fi
[ -r "$1" ] || { echo "$script_name: cannot read $1" >&2; exit 2; }

# The checklist's size, its first and last box (hops and the cause table, never n/a), and the
# fewest words an n/a reason may have.
box_count=9
hops_box=1
cause_table_box=9
min_reason_words=3

awk -v box_count="$box_count" -v hops_box="$hops_box" -v cause_table_box="$cause_table_box" -v min_reason_words="$min_reason_words" '
  function report_problem(text) { print text; problems++ }
  # A query or command in backticks, a link, or any number (a count, a time, a path:line).
  function has_evidence(text) {
    if (text ~ /`[^`]+`/) return 1
    if (text ~ /https?:\/\//) return 1
    if (text ~ /[0-9]/) return 1
    return 0
  }
  /^[[:space:]]*- \[[ xX]\] §INV[0-9]+([^0-9]|$)/ {
    id = $0
    sub(/^[[:space:]]*- \[[ xX]\] §INV/, "", id)
    sub(/[^0-9].*$/, "", id)
    id += 0
    seen[id]++
    ticked = ($0 ~ /^[[:space:]]*- \[[xX]\]/)
    evidence = $0
    sub(/^[[:space:]]*- \[[ xX]\] §INV[0-9]+/, "", evidence)
    if (!ticked) { report_problem("§INV" id ": the box is not ticked; fill it with its evidence, then tick it"); next }
    is_always_due = (id == hops_box || id == cause_table_box)
    is_cause_table = (id == cause_table_box)
    lowered = tolower(evidence)
    if (lowered ~ /(^|[^a-z])n\/a:/) {
      if (is_always_due) { report_problem("§INV" id ": n/a is not allowed; every problem has hops and causes"); next }
      reason = lowered
      sub(/^.*n\/a:[[:space:]]*/, "", reason)
      if (split(reason, words, /[[:space:]]+/) < min_reason_words) report_problem("§INV" id ": n/a needs a reason of at least " min_reason_words " words")
      next
    }
    if (is_cause_table) { in_causes = 1; next }
    if (!has_evidence(evidence)) report_problem("§INV" id ": no evidence; give a query in backticks, a path:line, a link or a count")
    next
  }
  in_causes && /^[[:space:]]*\|/ {
    line = $0
    sub(/^[[:space:]]*\|/, "", line)
    sub(/\|[[:space:]]*$/, "", line)
    cell_count = split(line, cells, /\|/)
    if (!header_seen) {
      header_seen = 1
      if (tolower(line) !~ /cause/) report_problem("§INV9: the table has no cause column")
      next
    }
    if (line ~ /^[[:space:]:|-]*$/) next
    rows++
    verdict = tolower(cells[cell_count])
    sub(/^[[:space:]]+/, "", verdict)
    cause = cells[1]
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", cause)
    if (verdict ~ /^(in|out)([^a-z]|$)/) {
      ruling = "out"
      if (verdict ~ /^in/) ruling = "in"
      if (verdict !~ /§inv[1-8]([^0-9]|$)/) report_problem("§INV9: cause \"" cause "\" is ruled " ruling " without citing a box from §INV1 to §INV8")
    } else if (verdict ~ /^open([^a-z]|$)/) {
      if (verdict !~ /probe/) report_problem("§INV9: cause \"" cause "\" is open without naming the probe that would settle it")
    } else {
      report_problem("§INV9: cause \"" cause "\" has no verdict (in, out or open) in its last cell")
    }
    next
  }
  END {
    for (n = 1; n <= box_count; n++) {
      if (!(n in seen)) report_problem("§INV" n ": missing; copy the box from kc-investigate and fill it")
      else if (seen[n] > 1) report_problem("§INV" n ": listed " seen[n] " times; keep one")
    }
    has_cause_box = (cause_table_box in seen)
    has_no_rows = (rows == 0)
    if (has_cause_box && has_no_rows) report_problem("§INV9: no cause table with at least one row after the box")
    if (problems > 0) exit 1
  }
' "$1"
