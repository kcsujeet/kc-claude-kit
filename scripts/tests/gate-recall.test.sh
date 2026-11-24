#!/usr/bin/env bash
# Tests scripts/gate-recall.sh: graders are tried against the gate reports in a trace, not the
# final message, and verdict and not_contains graders are left out.
set -euo pipefail

scripts_dir="$(cd "$(dirname "$0")/.." && pwd)"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
passes=0
failures=0

check() { # <label> <want status> <text the output holds> <args...>
  local label=$1 want=$2 text=$3 output status=0
  shift 3
  output=$(bash "$scripts_dir/gate-recall.sh" "$@" 2>&1) || status=$?
  if [ "$status" -eq "$want" ] && printf '%s' "$output" | grep -qF -- "$text"; then
    echo "ok   $label"
    passes=$((passes + 1))
  else
    echo "FAIL $label (want status $want with: $text; got status $status: $output)"
    failures=$((failures + 1))
  fi
}

case_dir=$work_dir/case
mkdir -p "$case_dir/graders"
printf -- '---\ntype: regex\ntarget: last_message\npattern: "(^|\\\\n)- (🔴|🟠|🟡)[^\\\\n]*cart\\\\.ts[^\\\\n]*(ternar|lookup)"\nflags: i\n---\n' > "$case_dir/graders/flags-cart.md"
printf -- "---\ntype: regex\ntarget: last_message\npattern: 'any\\\\b'\n---\n" > "$case_dir/graders/flags-any.md"
printf -- '---\ntype: regex\ntarget: last_message\npattern: FAILED\n---\n' > "$case_dir/graders/verdict-failed.md"
printf -- '---\ntype: regex\ntarget: last_message\npattern: x\nmatch: not_contains\n---\n' > "$case_dir/graders/no-x.md"

# A trace with one gate report (the second line) and chatter that must not count.
report='GATE: clarity\nSTATUS: FAIL\nFINDINGS:\n- 🟠 src/cart.ts:4: nested ternary. Use a lookup.'
printf '{"subtype":"task_notification","summary":"cart.ts any\\n- 🟠 not a gate report"}\n{"subtype":"task_notification","summary":"%s"}\n' "$report" > "$work_dir/hit.jsonl"
printf '{"subtype":"task_notification","summary":"GATE: naming\\nSTATUS: PASS"}\n' > "$work_dir/miss.jsonl"

check "a finding in a gate report satisfies a double-quoted grader" 0 "flags-cart 1/1" "$case_dir" "$work_dir/hit.jsonl"
check "a pattern the report lacks is a miss" 0 "flags-any 0/1" "$case_dir" "$work_dir/hit.jsonl"
# A report wrapped in a code fence still counts.
# shellcheck disable=SC2016 # backticks in the JSON, not a command substitution.
printf '{"subtype":"task_notification","summary":"```\\nGATE: clarity\\nSTATUS: FAIL\\n- 🟠 src/cart.ts:4: nested ternary. Use a lookup.\\n```"}\n' > "$work_dir/fenced.jsonl"
check "a code-fenced report counts" 0 "flags-cart 1/1" "$case_dir" "$work_dir/fenced.jsonl"
check "text outside a GATE: report does not count" 0 "flags-cart 0/1" "$case_dir" "$work_dir/miss.jsonl"
check "hits are counted over the traces" 0 "TOTAL 1/4" "$case_dir" "$work_dir/hit.jsonl" "$work_dir/miss.jsonl"
for left_out in verdict-failed no-x; do
  if bash "$scripts_dir/gate-recall.sh" "$case_dir" "$work_dir/hit.jsonl" | grep -q "$left_out"; then
    echo "FAIL $left_out is tried as a grader"
    failures=$((failures + 1))
  else
    echo "ok   $left_out is left out"
    passes=$((passes + 1))
  fi
done
# Two topic blocks in one report, three and one boxes.
printf '{"subtype":"task_notification","summary":"GATE: naming\\nSTATUS: PASS\\nBOXES:\\n- [PASS] §N1: a\\n- [N/A] §N2: b\\n- [FAIL] §N3: c\\nGATE: clarity\\nSTATUS: PASS\\nBOXES:\\n- [PASS] §C1: d"}\n' > "$work_dir/boxes.jsonl"
check "boxes are counted per topic" 0 "BOXES naming 3.0 per report over 1 reports" "$case_dir" "$work_dir/boxes.jsonl"
check "a second topic in the same report is counted on its own" 0 "BOXES clarity 1.0 per report over 1 reports" "$case_dir" "$work_dir/boxes.jsonl"
check "no arguments exits 2" 2 "usage"
check "an unreadable trace exits 2" 2 "cannot read" "$case_dir" "$work_dir/none.jsonl"

echo "$passes passed, $failures failed"
[ "$failures" -eq 0 ]
