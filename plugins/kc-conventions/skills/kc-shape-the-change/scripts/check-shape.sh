#!/usr/bin/env bash
# Checks a shape file (kc-shape-the-change): its eight boxes §SH1 to §SH8 are ticked and answered,
# and the shapes, flag, failure and approval lines have the formats the skill's template shows.
# Usage: check-shape.sh <shape-file.md>
# Prints one line per problem and exits 1 when there is any, 0 when the file passes, 2 on a usage
# error or an unreadable file.
set -euo pipefail

script_name=$(basename "$0")
if [ "$#" -ne 1 ]; then
  echo "usage: $script_name <shape-file.md>" >&2
  exit 2
fi
[ -r "$1" ] || { echo "$script_name: cannot read $1" >&2; exit 2; }

box_count=8
shapes_box=4
rollout_box=6
failures_box=7
approval_box=8
min_words=4
min_shapes=2
min_reason_words=3
min_approval_words=2

awk -v box_count="$box_count" -v shapes_box="$shapes_box" -v rollout_box="$rollout_box" \
  -v failures_box="$failures_box" -v approval_box="$approval_box" -v min_words="$min_words" \
  -v min_shapes="$min_shapes" -v min_reason_words="$min_reason_words" -v min_approval_words="$min_approval_words" '
  function report_problem(text) { print text; problems++ }
  function trim(text) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", text); return text }
  function count_words(text,   parts) { text = trim(text); if (text == "") return 0; return split(text, parts, /[[:space:]]+/) }
  function is_gap_only(reason,   lowered) {
    lowered = tolower(reason)
    if (lowered !~ /backfill|back-fill|migrat|deploy|data gap|existing (rows|records|data)|old (rows|records|data)|release order|ship order|until the data/) return 0
    if (lowered ~ /customer|pilot|beta|opt-in|opt in|staged|gradual|announce|launch|training|(^|[^a-z])products?([^a-z]|$)|rollout to|early access/) return 0
    return 1
  }
  function check_pick_line(line,   picked, picked_label, pick_reason) {
    if (line == "") { report_problem("§SH" shapes_box ": no \"- pick: <label> <why>\" line"); return }
    picked = line; sub(/^[[:space:]]*- pick:[[:space:]]*/, "", picked)
    picked_label = picked; sub(/[^A-Za-z0-9].*$/, "", picked_label)
    if (!(picked_label in shape_labels)) report_problem("§SH" shapes_box ": the pick must start with the label of a shape above (" picked_label " is not one)")
    pick_reason = picked; sub(/^[A-Za-z0-9]+/, "", pick_reason)
    if (count_words(pick_reason) < min_words) report_problem("§SH" shapes_box ": the pick needs its reason, at least " min_words " words")
  }
  function check_flag_line(line,   flag_text, count, parts, change, answer, reason, decider, lowered_decider) {
    flag_text = line
    sub(/^[[:space:]]*- flag:[[:space:]]*/, "", flag_text)
    count = split(flag_text, parts, /\|/)
    change = trim(parts[1]); answer = tolower(trim(parts[2])); reason = trim(parts[3]); decider = trim(parts[4])
    if (count != 4 || change == "" || answer !~ /^(yes|no)$/ || reason !~ /^[Rr]eason:/ || decider !~ /^[Dd]ecided-by:/) {
      report_problem("§SH" rollout_box ": flag line must read \"- flag: <change> | yes|no | reason: <why> | decided-by: <who>\", got: " line)
      return
    }
    sub(/^[Rr]eason:[[:space:]]*/, "", reason)
    sub(/^[Dd]ecided-by:[[:space:]]*/, "", decider)
    lowered_decider = tolower(decider)
    if (count_words(reason) < min_reason_words) report_problem("§SH" rollout_box ": flag \"" change "\" has no reason of at least " min_reason_words " words")
    if (decider == "" || lowered_decider ~ /^(me|i|claude|agent|assistant|ai|model|self|the agent|n\/a|none|tbd)$/) \
      report_problem("§SH" rollout_box ": flag \"" change "\" needs decided-by naming the person who decided, not the agent")
    if (answer == "yes" && is_gap_only(reason)) \
      report_problem("§SH" rollout_box ": flag \"" change "\" is justified by a data or deploy gap only; a flag is a product rollout decision (who sees it, when). Solve a backfill or deploy order with compatibility and order, or state the product reason")
    flag_lines++
  }
  /^[[:space:]]*$/ { next }
  !started {
    started = 1
    if (tolower($0) ~ /^trivial:/) { trivial = 1; trivial_line = $0 }
  }
  /^#/ { current_box = 0; next }
  /^[[:space:]]*- \[[ xX]\] §SH[0-9]+([^0-9]|$)/ {
    id = $0
    sub(/^[[:space:]]*- \[[ xX]\] §SH/, "", id)
    sub(/[^0-9].*$/, "", id)
    id += 0
    current_box = id
    seen[id]++
    ticked[id] = ($0 ~ /^[[:space:]]*- \[[xX]\]/)
    answer_text = $0
    sub(/^[[:space:]]*- \[[ xX]\] §SH[0-9]+[^:]*:?/, "", answer_text)
    box_answers[id] = answer_text
    next
  }
  current_box > 0 {
    box_answers[current_box] = box_answers[current_box] " " $0
    if ($0 ~ /^[[:space:]]*- shape [A-Za-z0-9]+:/) {
      label = $0; sub(/^[[:space:]]*- shape /, "", label); sub(/:.*$/, "", label)
      if (!(label in shape_labels)) { shape_labels[label] = 1; shape_count++ }
    }
    if ($0 ~ /^[[:space:]]*- pick:/) pick_line = $0
    if (current_box == rollout_box && $0 ~ /^[[:space:]]*- flag:/) check_flag_line($0)
    if (current_box == failures_box && $0 ~ /^[[:space:]]*- failure:/) {
      if ($0 ~ /\|[[:space:]]*noticed-by:[[:space:]]*[^[:space:]]/) failure_lines++
      else report_problem("§SH" failures_box ": failure line must read \"- failure: <mode> | noticed-by: <signal>\", got: " $0)
    }
  }
  END {
    if (trivial) {
      trivial_reason_text = tolower(trivial_line)
      ok = 1
      if (trivial_reason_text !~ /no new storage/) { report_problem("trivial: the line must say \"no new storage\""); ok = 0 }
      if (trivial_reason_text !~ /no new unit/) { report_problem("trivial: the line must say \"no new unit\""); ok = 0 }
      if (trivial_reason_text !~ /no behaviour move|no behavior move/) { report_problem("trivial: the line must say \"no behaviour move\""); ok = 0 }
      gsub(/trivial:|no new storage|no new unit|no behaviou?r move/, "", trivial_reason_text)
      gsub(/[,.:;-]/, " ", trivial_reason_text)
      if (ok && count_words(trivial_reason_text) < min_words) report_problem("trivial: give the reason in at least " min_words " words after the three \"no\" phrases")
      exit (problems > 0)
    }
    for (n = 1; n <= box_count; n++) {
      if (!(n in seen)) { report_problem("§SH" n ": missing; copy the box from kc-shape-the-change and fill it"); continue }
      if (seen[n] > 1) report_problem("§SH" n ": listed " seen[n] " times; keep one")
      if (!ticked[n]) { report_problem("§SH" n ": the box is not ticked; fill it, then tick it"); continue }
      if (count_words(box_answers[n]) < min_words) report_problem("§SH" n ": the answer is under " min_words " words")
      if (tolower(box_answers[n]) ~ /(^|[^a-z])(todo|tbd)([^a-z]|$)/ || tolower(box_answers[n]) ~ /fill in/) report_problem("§SH" n ": unfinished (TODO, TBD or fill in)")
    }
    if ((shapes_box in seen) && shape_count < min_shapes) report_problem("§SH" shapes_box ": compare at least " min_shapes " shapes, as lines \"- shape A: ...\" and \"- shape B: ...\"")
    if (shapes_box in seen) check_pick_line(pick_line)
    if ((rollout_box in seen) && flag_lines == 0) report_problem("§SH" rollout_box ": no flag line; one per change, \"- flag: <change> | yes|no | reason: <why> | decided-by: <who>\"")
    if ((failures_box in seen) && failure_lines == 0) report_problem("§SH" failures_box ": no failure line; \"- failure: <mode> | noticed-by: <signal>\"")
    if ((approval_box in seen) && ticked[approval_box]) {
      if (match(box_answers[approval_box], /"[^"]+"/) == 0 || count_words(substr(box_answers[approval_box], RSTART + 1, RLENGTH - 2)) < min_approval_words) \
        report_problem("§SH" approval_box ": quote the approval words of the person verbatim, at least " min_approval_words " words between double quotes")
    }
    exit (problems > 0)
  }
' "$1"
