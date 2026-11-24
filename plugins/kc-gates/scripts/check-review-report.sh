#!/usr/bin/env bash
# Checks a code review's report leads with whether the change works and what it can break, and
# marks style findings non-blocking, so its reader sees effectiveness and blast radius first and
# nits last (kc-code-review §G6).
#
# Usage: check-review-report.sh <report-file|->
#
#   <report-file|->  the report as kc-code-review's Output format writes it; - reads stdin.
#
# What it requires:
#   - a `**Does it work / what can it break**` section, before the gate status table;
#   - in it, what was measured with numbers (a line with a digit and "before", "after" or "->",
#     e.g. `Checkout query: before 420 ms -> after 38 ms (1,000 orders)`), or a line
#     `not measured: <why>`;
#   - in it, a `Uses:` or `Blast radius:` line with the trace-uses.sh count and which of those
#     uses were run or checked (e.g. `Uses: 4 traced, 3 run in orders_spec, 1 read`);
#   - every finding under the `**Naming:**` and `**Clarity:**` headings (the style gates) ends with
#     `(non-blocking)`, before an optional `(fails safe)`. The label orders the author's
#     attention only: such a finding still fails its gate and the review.
#
# Prints one line per problem. Exits 0 when there is none, 1 when there is any, 2 on a usage
# error or an unreadable file.
set -euo pipefail

script_name=$(basename "$0")
[ "$#" -eq 1 ] || { echo "usage: $script_name <report-file|->" >&2; exit 2; }
is_stdin=false
is_readable=false
[ "$1" = - ] && is_stdin=true
[ -r "$1" ] && is_readable=true
if ! "$is_stdin" && ! "$is_readable"; then
  echo "$script_name: cannot read $1" >&2
  exit 2
fi

problems=$(awk -v finding_preview_chars=100 '
  function is_heading(line,   is_markdown_heading, is_table_line, is_gate_heading) {
    is_markdown_heading = line ~ /^#+ /
    is_table_line = line ~ /^\|/
    is_gate_heading = line ~ /^\*\*[^*]+:\*\*/
    return is_markdown_heading || is_table_line || is_gate_heading
  }
  /^\*\*Does it work \/ what can it break\*\*/ { section = NR; in_section = 1; style = 0; next }
  /^\| *Gate *\|/ { if (!table) table = NR }
  is_heading($0) {
    in_section = 0
    style = ($0 ~ /^\*\*(Naming|Clarity):\*\*/)
  }
  in_section {
    if ($0 ~ /^[[:space:]]*(-|\*)?[[:space:]]*not measured:/ ) measured = 1
    has_digit = ($0 ~ /[0-9]/)
    has_before_after = (tolower($0) ~ /(before|after|->|→)/)
    is_uses_label = (tolower($0) ~ /^[[:space:]]*(-|\*)?[[:space:]]*(uses|blast radius):/)
    if (has_digit && has_before_after) measured = 1
    if (is_uses_label && has_digit) uses = 1
  }
  style && /^[[:space:]]*(-|\*) *(🔴|🟠|🟡)/ {
    if ($0 !~ /\(non-blocking\)( \(fails safe\))?\.?[[:space:]]*$/) unlabeled[++n] = $0
  }
  END {
    if (!section) print "no `**Does it work / what can it break**` section: lead the report with what was measured and the blast radius"
    else {
      section_after_table = (table && section > table)
      if (section_after_table) print "the `Does it work / what can it break` section comes after the gate table: move it above the table"
      if (!measured) print "the `Does it work / what can it break` section has no measurement (a line with a number and before, after or ->) and no `not measured: <why>` line"
      if (!uses) print "the `Does it work / what can it break` section has no `Uses:` line with the trace-uses.sh count and which uses were run or checked"
    }
    for (i = 1; i <= n; i++) { line = unlabeled[i]; sub(/^[[:space:]]+/, "", line); print "style finding without (non-blocking) at its end: " substr(line, 1, finding_preview_chars) }
  }
' "$1")
[ -z "$problems" ] || { printf '%s\n' "$problems"; exit 1; }
