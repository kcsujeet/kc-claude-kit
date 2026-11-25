#!/usr/bin/env bash
# The mechanical half of the verification gate, as a script: reads one review round's saved verdict
# blocks and fails with one line per problem, so a round is not sent back to an agent, three
# times, for things a script counts. It does not re-grade the diff or judge a finding.
#
# Usage: verify-gate-blocks.sh [--later-round] <round-dir> <repo-root>
#
#   <round-dir>   A round folder of a pass: verdicts/ (one file per gate block, the `SCOPE:` block,
#                 and for a later round `checklist.txt`), review.diff, changed-files.txt, meta.env.
#   <repo-root>   The repo the round reviewed; its history holds the head the blocks cite.
#   --later-round The round reviews only the fixes since the round before: no `SCOPE:` block is
#                 needed, and the lines `<n> fixes re-checked`, `<n> rewrites checked` and
#                 `<n> rename-only lines kept` (the last equal to what rename-only-lines.sh lists
#                 for review.diff) must be in verdicts/ (`checklist.txt`), and each `walk-item:`
#                 path select-gates.sh prints must be on a `Walk:` line there.
#
# What it checks, each problem one line `<file>: <problem>`:
#   - a gate select-gates.sh lists for the round has no `GATE:` block;
#   - every citation `path:line@sha` resolves at the head (check-gate-citations.sh; a path that is
#     only a file's name is told where the file is);
#   - a sweep receipt `grepped <what>: <n> hits` is followed, in its box, by at least n distinct
#     `path:line` verdicts;
#   - a PASS or N/A box that asserts a rendered layout or visual result by reasoning ("estimated",
#     "by calculation", "should render", "would fit") with no screenshot or recording path and no
#     `measured <number>` value: the gate measures it in the running app and cites the capture;
#   - a box marked FAIL whose text opens with PASS or N/A, or marked PASS or N/A whose text opens
#     with FAIL;
#   - a gate's STATUS that its boxes contradict (PASS with a FAIL box, FAIL with none, PASS (N/A)
#     with a box that is not N/A), or no STATUS;
#   - no `SCOPE:` block marking §G1 to §G5 once each (round 1);
#   - the later-round lines above.
# A verification block that carries `SOURCE: verify-gate-blocks.sh` is this script's own output and
# is not read back as a gate block.
#
# Prints the problems and exits 1; when there are none, prints a `GATE: verification` block in the
# shape ready-receipt.sh reads, with what it checked as evidence, and exits 0. Exits 2 on a usage
# error. What it leaves to a reader (is each trigger group's receipt there, is a library claim
# cited, was a finding defended with a run) is in the block's SOURCE line.
set -euo pipefail

script_name=$(basename "$0")
scripts_dir=$(cd "$(dirname "$0")" && pwd)
usage() {
  echo "usage: $script_name [--later-round] <round-dir> <repo-root>" >&2
  exit 2
}

is_later_round=false
if [ "${1:-}" = --later-round ]; then
  is_later_round=true
  shift
fi
[ "$#" -eq 2 ] || usage
round_dir=$1
repo_root=$2
[ -d "$round_dir/verdicts" ] || { echo "$script_name: no $round_dir/verdicts" >&2; exit 2; }
for required in review.diff changed-files.txt meta.env; do
  [ -f "$round_dir/$required" ] || { echo "$script_name: no $round_dir/$required" >&2; exit 2; }
done
head_sha=$(sed -nE "s/^HEAD_SHA='?([0-9a-f]{40})'?$/\1/p" "$round_dir/meta.env" | head -n 1)
[ -n "$head_sha" ] || { echo "$script_name: $round_dir/meta.env names no HEAD_SHA" >&2; exit 2; }
git -C "$repo_root" cat-file -e "$head_sha^{commit}" 2>/dev/null || { echo "$script_name: $head_sha is not a commit in $repo_root" >&2; exit 2; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
problems=$work/problems.txt
facts=$work/facts.txt
: > "$problems"
: > "$facts"
problem() { printf '%s\n' "$1" >> "$problems"; }

# The files to read: every verdict file but this script's own earlier output.
files=()
for verdict_file in "$round_dir"/verdicts/*; do
  [ -f "$verdict_file" ] || continue
  grep -q '^SOURCE: verify-gate-blocks.sh' "$verdict_file" && continue
  files+=("$verdict_file")
done
[ "${#files[@]}" -gt 0 ] || { problem "verdicts/: no verdict blocks"; }

# Per file: block, box and sweep checks. Prints `P<TAB>problem`, `G<TAB>gate` (a block seen),
# `B<TAB>id` (a SCOPE box), `K<TAB>kind` (SCOPE block seen, a box, a sweep, a gate block checked).
read_blocks() {
  awk -v file="$(basename "$1")" '
    function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
    function say(text) { printf "P\t%s: %s\n", file, text }
    function count_locations(text,   rest, seen, total, location) {
      rest = text; total = 0
      while (match(rest, "([A-Za-z0-9_./-]+\\.[A-Za-z0-9]+|[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)+):L?[0-9]+")) {
        location = substr(rest, RSTART, RLENGTH)
        rest = substr(rest, RSTART + RLENGTH)
        if (!(location in seen)) { seen[location] = 1; total++ }
      }
      return total
    }
    function check_sweeps(id, text,   rest, hit, count, after, next_sweep, segment, shown) {
      rest = text
      while (match(rest, "grepped [^:]+:[[:space:]]*[0-9]+ hits?")) {
        hit = substr(rest, RSTART, RLENGTH)
        after = substr(rest, RSTART + RLENGTH)
        count = hit; sub(/^.*:[[:space:]]*/, "", count); count = count + 0
        next_sweep = match(after, "grepped ") ? RSTART : length(after) + 1
        segment = substr(after, 1, next_sweep - 1)
        printf "K\tsweep\n"
        if (count > 0) {
          shown = count_locations(segment)
          if (shown < count) say(name ": " id ": \"" hit "\" has " shown " per-hit verdict(s) with a path:line; every hit gets its own, in the box")
        }
        rest = substr(after, next_sweep)
      }
    }
    # True when text claims how something renders from reasoning, with no capture path and no
    # "measured <number>" beside it. The phrase found is left in reasoning_phrase.
    function reasons_about_layout(text,   lower) {
      lower = tolower(text)
      if (lower ~ /[A-Za-z0-9_\/-]+\.(png|jpe?g|gif|webp|mp4|mov|webm)([^A-Za-z0-9]|$)/) return 0
      if (lower ~ /measured[^0-9]{0,30}[0-9]/) return 0
      if (match(lower, /(should|will|would|shouldn.t|wouldn.t) (still )?(render|fit|look|display|wrap|align|overflow|not overflow|not clip)|by (my )?calculation|calculated by hand|computed by hand|on paper|in theory/)) { reasoning_phrase = substr(lower, RSTART, RLENGTH); return 1 }
      if (lower ~ /(layout|width|height|viewport|[0-9]px|overflow|clip|align|spacing|margin|padding|breakpoint|column|screen|responsive|visual|pixel)/ && match(lower, /(^|[^a-z])(estimated|estimate|estimating)([^a-z]|$)/)) { reasoning_phrase = "estimated"; return 1 }
      return 0
    }
    function flush_box(   lead) {
      if (!in_box) return
      in_box = 0
      printf "K\tbox\n"
      lead = trim(box_text)
      if (box_verdict == "FAIL") { fails++; fail_ids = fail_ids (fail_ids == "" ? "" : ", ") box_id }
      if (box_verdict == "PASS") passes++
      if (box_verdict == "N/A") nas++
      if (box_verdict == "FAIL" && lead ~ /^(PASS|passes|N\/A)([^A-Za-z]|$)/) say(name ": " box_id " is marked FAIL but its text says " substr(lead, 1, 12))
      if (box_verdict != "FAIL" && lead ~ /^(FAIL|fails)([^A-Za-z]|$)/) say(name ": " box_id " is marked " box_verdict " but its text says " substr(lead, 1, 12))
      if (box_verdict != "FAIL" && reasons_about_layout(box_text)) say(name ": " box_id " asserts a rendered layout by reasoning (\"" reasoning_phrase "\"): measure it in the running app (kc-verify:kc-ui) and cite the screenshot or recording path, or write the measured value (measured 412px wide at 1920)")
      if (kind == "scope") printf "B\t%s\n", box_id
      check_sweeps(box_id, box_text)
    }
    function flush_block() {
      flush_box()
      if (kind == "") return
      if (kind == "gate") {
        printf "G\t%s\n", name
        printf "K\tblock\n"
        if (status == "") say("GATE: " name " has no STATUS: line")
        else if (status == "PASS" && fails > 0) say("GATE: " name " says STATUS: PASS but " fails " box(es) are FAIL (" fail_ids ")")
        else if (status == "FAIL" && fails == 0) say("GATE: " name " says STATUS: FAIL but no box is FAIL")
        else if (status == "PASS (N/A)" && passes + fails > 0) say("GATE: " name " says STATUS: PASS (N/A) but a box is not N/A")
      } else printf "K\tscope\n"
      kind = ""
    }
    /^[[:space:]]*```/ { next }
    /^GATE:/ { flush_block(); kind = "gate"; name = trim(substr($0, 6)); sub(/[[:space:]]*\([^()]*\)$/, "", name); status = ""; fails = 0; passes = 0; nas = 0; fail_ids = ""; in_boxes = 0; next }
    /^SCOPE:/ { flush_block(); kind = "scope"; name = "SCOPE"; status = "-"; fails = 0; passes = 0; nas = 0; fail_ids = ""; in_boxes = 1; next }
    kind == "" { next }
    /^STATUS:/ { flush_box(); status = trim(substr($0, 8)); next }
    /^BOXES:/ { flush_box(); in_boxes = 1; next }
    /^FINDINGS:/ { flush_box(); in_boxes = 0; next }
    in_boxes && /^[[:space:]]*- \[(PASS|FAIL|N\/A)\]/ {
      flush_box()
      line = $0
      sub(/^[[:space:]]*- \[/, "", line)
      box_verdict = substr(line, 1, index(line, "]") - 1)
      rest = substr(line, index(line, "]") + 1)
      colon = index(rest, ":")
      if (colon) { box_id = trim(substr(rest, 1, colon - 1)); box_text = trim(substr(rest, colon + 1)) }
      else { box_id = trim(rest); box_text = "" }
      in_box = 1
      next
    }
    in_box && (/^[[:space:]]+[^[:space:]]/ || /^\|/) { box_text = box_text " " trim($0); next }
    END { flush_block() }
  ' "$1"
}

for verdict_file in "${files[@]+"${files[@]}"}"; do
  read_blocks "$verdict_file" >> "$work/awk.txt"
done
[ ! -f "$work/awk.txt" ] || sed -n 's/^P\t//p' "$work/awk.txt" >> "$problems"
count_kind() { { grep -c "^K	$1$" "$work/awk.txt" 2>/dev/null || true; } | head -n 1; }
block_count=$(count_kind block)
box_count=$(count_kind box)
sweep_count=$(count_kind sweep)
: "${block_count:=0}" "${box_count:=0}" "${sweep_count:=0}"

# The gates select-gates.sh lists for this round each have a block.
select_args=()
$is_later_round && select_args+=(--later-round)
gate_report=$(bash "$scripts_dir/select-gates.sh" "${select_args[@]+"${select_args[@]}"}" "$round_dir/review.diff" "$round_dir/changed-files.txt" "$repo_root")
gates=$(printf '%s\n' "$gate_report" | sed -n 's/^GATES=//p')
git -C "$repo_root" cat-file -e "$head_sha:.claude/review-conventions.md" 2>/dev/null || gates=${gates/,project-conventions/}
for gate in ${gates//,/ }; do
  if ! { [ -f "$work/awk.txt" ] && grep -q "^G	$gate$" "$work/awk.txt"; }; then
    problem "verdicts/: no GATE: $gate block"
  fi
done

# Citations resolve at the head. A path that is only a file's name is told where the file is.
citation_count=0
if [ "${#files[@]}" -gt 0 ]; then
  citation_count=$(grep -hEo '[A-Za-z0-9_./-]+:L?[0-9]+@[0-9a-fA-F]{4,40}' "${files[@]}" | sort -u | grep -c . || true)
  citation_out=$work/citations.txt
  if ! bash "$scripts_dir/check-gate-citations.sh" "$head_sha" "$repo_root" "${files[@]}" > "$citation_out" 2>"$work/citations.err"; then
    if [ -s "$citation_out" ]; then
      while IFS= read -r citation_line; do
        cited=$(printf '%s' "$citation_line" | sed -E 's/^[^:]*: ([^:]+):L?[0-9]+@.*$/\1/')
        hint=""
        case "$cited" in
          */*) ;;
          *) match=$(git -C "$repo_root" ls-tree -r --name-only "$head_sha" | awk -v base="$cited" '{ n = split($0, p, "/") } p[n] == base' | head -n 3 | paste -sd ' ' -)
             [ -z "$match" ] || hint=" (cite the repo path: $match)" ;;
        esac
        problem "$citation_line$hint"
      done < "$citation_out"
    else
      problem "check-gate-citations.sh failed: $(head -n 1 "$work/citations.err")"
    fi
  fi
fi

# Round 1 has a SCOPE: block marking each of §G1 to §G5 once.
if ! $is_later_round; then
  if [ ! -f "$work/awk.txt" ] || ! grep -q '^K	scope$' "$work/awk.txt"; then
    problem "verdicts/: no SCOPE: block"
  else
    for scope_box in §G1 §G2 §G3 §G4 §G5; do
      scope_hits=$(awk -F '\t' -v id="$scope_box" '$1 == "B" && ($2 == id || index($2, id " ") == 1) { n++ } END { print n + 0 }' "$work/awk.txt")
      [ "$scope_hits" -eq 1 ] || problem "verdicts/: SCOPE: marks $scope_box $scope_hits time(s); one verdict per box"
    done
  fi
fi

# A later round's receipt lines, and its walk-items.
rename_count=0
if $is_later_round; then
  receipt_text=""
  [ "${#files[@]}" -eq 0 ] || receipt_text=$(cat "${files[@]}")
  for receipt_line in "fixes re-checked" "rewrites checked" "rename-only lines kept"; do
    printf '%s\n' "$receipt_text" | grep -Eq "(^|[^0-9])[0-9]+ $receipt_line" \
      || problem "verdicts/: no \"<n> $receipt_line\" line (write it in verdicts/checklist.txt, 0 when none)"
  done
  rename_count=$(bash "$scripts_dir/rename-only-lines.sh" "$round_dir/review.diff" | grep -c . || true)
  claimed=$(printf '%s\n' "$receipt_text" | sed -nE 's/.*(^|[^0-9])([0-9]+) rename-only lines kept.*/\2/p' | head -n 1)
  if [ -n "$claimed" ] && [ "$claimed" -ne "$rename_count" ]; then
    problem "verdicts/: \"$claimed rename-only lines kept\" but rename-only-lines.sh lists $rename_count for this round's diff"
  fi
  walk_count=0
  while IFS= read -r walk_path; do
    [ -n "$walk_path" ] || continue
    walk_count=$((walk_count + 1))
    printf '%s\n' "$receipt_text" | grep -F "$walk_path" | grep -q 'Walk:' \
      || problem "verdicts/: walk-item $walk_path has no \"Walk:\" line naming it"
  done < <(printf '%s\n' "$gate_report" | sed -n 's/^walk-item: //p')
fi

if [ -s "$problems" ]; then
  cat "$problems"
  exit 1
fi

short_head=${head_sha:0:7}
{
  echo "GATE: verification"
  echo "STATUS: PASS"
  echo "BOXES:"
  echo "- [PASS] §V3: $block_count gate block(s), $box_count box(es): each STATUS matches its boxes, no box contradicts its verdict, $sweep_count sweep receipt(s) each followed by its per-hit path:line verdicts, a block for every gate select-gates.sh lists ($gates)"
  echo "- [PASS] §V12: $citation_count citation(s) path:line@sha, every one resolves at head $short_head"
  if $is_later_round; then
    echo "- [PASS] §V8: the round's \"fixes re-checked\" and \"rewrites checked\" lines are in verdicts/"
    echo "- [PASS] §V9: $rename_count rename-only lines kept, as rename-only-lines.sh lists for the round's diff; $walk_count walk-item(s) each on a Walk: line"
  else
    echo "- [PASS] §V7: SCOPE: block marks §G1 to §G5 once each, each with evidence"
  fi
  echo "FINDINGS:"
  echo "- none"
  echo "SOURCE: verify-gate-blocks.sh (mechanical receipts only; whether each trigger group's receipt is there, §V4 cited library claims, §V5 renamed-is-not-fixed and §V6 defended findings are not judged by a script)"
}
