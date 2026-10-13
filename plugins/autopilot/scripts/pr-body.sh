#!/usr/bin/env bash
# Renders a unit's PR body from the unit result JSON the shipper agent writes.
# Usage: pr-body.sh <unit-result.json>
# Output: PR body markdown on stdout. Missing or empty lists render as
#   "- none" / "- no confirmed bugs"; the "Review receipts incomplete" list
#   (review_receipts_incomplete) and the "Found by QA, not caused by this
#   change" section (qa_preexisting) appear only when they have entries.
# Exit: 0 ok; 2 jq missing; jq's own status on bad input.
set -euo pipefail
command -v jq >/dev/null 2>&1 || { echo "autopilot: jq is required" >&2; exit 2; }
jq -r '
  def clean: tostring | gsub("[\r\n]+"; " ") | gsub("<"; "&lt;");
  def cell: clean | gsub("\\|"; "\\|");
  def bullets(xs; empty_text): if (xs | length) == 0 then "- " + empty_text else (xs | map("- " + clean) | join("\n")) end;
  def plural(n; word): "\(n) \(word)\(if n == 1 then "" else "s" end)";
  "## \(.plan_title | clean): \(.unit.id | clean) \(.unit.title | clean)\n",
  "Delivered by autopilot in \(plural(.rounds; "fix round")). Every criterion below was checked by the verifier, not the author.\n",
  "### Acceptance criteria\n",
  "| Criterion | Result | Evidence |",
  "|---|---|---|",
  ((.criteria // [])[] | "| \(.id | cell) \(.statement | cell) | \(if .passes then "pass" else "FAIL" end) | \(.evidence | cell) |"),
  "",
  "### Staff engineer\n",
  "- Approach: \(.staff.design | clean)",
  "- Final review: \(.staff.final | clean)\n",
  "### Review\n",
  "Fixed:",
  bullets(.review.fixed // []; "none"),
  "\nDismissed:",
  bullets((.review.dismissed // []) | map("\(.finding | clean) (\(.reason | clean))"); "none"),
  (if ((.review_receipts_incomplete // []) | length) == 0 then empty else
    "\nReview receipts incomplete (receipt-only FAILs from the verification gate, left after a recheck; they did not block this PR):",
    bullets(.review_receipts_incomplete; "none") end),
  "\n### QA\n",
  (if ((.qa // []) | length) == 0 then "- no confirmed bugs" else
    ((.qa // [])[] | . as $p | ($p.persona | clean) as $who | if (($p.confirmed // []) | length) == 0 then "- \($who): no confirmed bugs"
      else ($p.confirmed | to_entries | map("- \($who): fixed \"\(.value | clean)\" (\((($p.evidence // [])[.key] // "no artifact") | clean))") | join("\n")) end) end),
  (if ((.qa_preexisting // []) | length) == 0 then empty else
    "\n### Found by QA, not caused by this change\n",
    ((.qa_preexisting // [])[] | "- \(.title | clean): \((.steps // []) | map(clean) | join(" → ")) (\(.evidence | clean))") end),
  "\n<details><summary>Decision log</summary>\n",
  "| Step | Outcome | Reason |",
  "|---|---|---|",
  ((.decisions // [])[] | "| \(.step | cell) | \(.outcome | cell) | \(.reason | cell) |"),
  "\n</details>"
' "$1"
