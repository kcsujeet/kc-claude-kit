#!/usr/bin/env bash
# shape §SH1 to §SH8: checks a shape file before code is written (kc-shape-the-change). Each box is
# ticked (- [x] §SHn) and carries its answer, at least min_words words, with no TODO or TBD left:
# §SH1 requirement, §SH2 where each fact lives, §SH3 which unit owns which job, §SH4 shapes,
# §SH5 how existing behaviour and data move, §SH6 rollout, §SH7 failure modes, §SH8 approval.
#   §SH4 has two or more lines "- shape <label>: <text>" and one "- pick: <label> <why>" naming a
#        shape and giving a reason.
#   §SH6 has one line per change: "- flag: <change> | yes|no | reason: <why> | decided-by: <who>".
#        decided-by names a person (not the agent). A yes whose reason only covers a data or deploy
#        gap (a backfill, a migration, a deploy order) fails: those are solved by compatibility
#        and order, not by a flag. A reason that also names a product rollout (customers, a pilot,
#        a beta, opt-in, a staged launch) passes.
#   §SH7 has one or more lines "- failure: <mode> | noticed-by: <signal>".
#   §SH8 quotes the person's approval words, at least two words between double quotes.
# A change with no new storage, no new unit and no behaviour move is declared in one line, the
# file's first: "trivial: no new storage, no new unit, no behaviour move: <why, 4 words or more>".
#
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

awk -v box_count="$box_count" -v shapes_box="$shapes_box" -v rollout_box="$rollout_box" \
  -v failures_box="$failures_box" -v approval_box="$approval_box" -v min_words="$min_words" \
  -v min_shapes="$min_shapes" '
  function report_problem(text) { print text; problems++ }
  function trim(text) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", text); return text }
  function word_count(text,   parts) { text = trim(text); if (text == "") return 0; return split(text, parts, /[[:space:]]+/) }
  function is_gap_only(reason,   lowered) {
    lowered = tolower(reason)
    if (lowered !~ /backfill|back-fill|migrat|deploy|data gap|existing (rows|records|data)|old (rows|records|data)|release order|ship order|until the data/) return 0
    if (lowered ~ /customer|pilot|beta|opt-in|opt in|staged|gradual|announce|launch|training|product|rollout to|early access/) return 0
    return 1
  }
  function check_flag_line(line,   body, count, parts, change, answer, reason, decider, lowered_decider) {
    body = line
    sub(/^[[:space:]]*- flag:[[:space:]]*/, "", body)
    count = split(body, parts, /\|/)
    change = trim(parts[1]); answer = tolower(trim(parts[2])); reason = trim(parts[3]); decider = trim(parts[4])
    if (count != 4 || change == "" || answer !~ /^(yes|no)$/ || reason !~ /^[Rr]eason:/ || decider !~ /^[Dd]ecided-by:/) {
      report_problem("§SH" rollout_box ": flag line must read \"- flag: <change> | yes|no | reason: <why> | decided-by: <who>\", got: " line)
      return
    }
    sub(/^[Rr]eason:[[:space:]]*/, "", reason)
    sub(/^[Dd]ecided-by:[[:space:]]*/, "", decider)
    lowered_decider = tolower(decider)
    if (word_count(reason) < 3) report_problem("§SH" rollout_box ": flag \"" change "\" has no reason of at least 3 words")
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
  /^#/ { current = 0; next }
  /^[[:space:]]*- \[[ xX]\] §SH[0-9]+([^0-9]|$)/ {
    id = $0
    sub(/^[[:space:]]*- \[[ xX]\] §SH/, "", id)
    sub(/[^0-9].*$/, "", id)
    id += 0
    current = id
    seen[id]++
    ticked[id] = ($0 ~ /^[[:space:]]*- \[[xX]\]/)
    answer_text = $0
    sub(/^[[:space:]]*- \[[ xX]\] §SH[0-9]+[^:]*:?/, "", answer_text)
    body[id] = answer_text
    next
  }
  current > 0 {
    body[current] = body[current] " " $0
    if ($0 ~ /^[[:space:]]*- shape [A-Za-z0-9]+:/) {
      label = $0; sub(/^[[:space:]]*- shape /, "", label); sub(/:.*$/, "", label)
      if (!(label in shape_labels)) { shape_labels[label] = 1; shape_count++ }
    }
    if ($0 ~ /^[[:space:]]*- pick:/) pick_line = $0
    if (current == rollout_box && $0 ~ /^[[:space:]]*- flag:/) check_flag_line($0)
    if (current == failures_box && $0 ~ /^[[:space:]]*- failure:/) {
      if ($0 ~ /\|[[:space:]]*noticed-by:[[:space:]]*[^[:space:]]/) failure_lines++
      else report_problem("§SH" failures_box ": failure line must read \"- failure: <mode> | noticed-by: <signal>\", got: " $0)
    }
  }
  END {
    if (trivial) {
      rest = tolower(trivial_line)
      ok = 1
      if (rest !~ /no new storage/) { report_problem("trivial: the line must say \"no new storage\""); ok = 0 }
      if (rest !~ /no new unit/) { report_problem("trivial: the line must say \"no new unit\""); ok = 0 }
      if (rest !~ /no behaviour move|no behavior move/) { report_problem("trivial: the line must say \"no behaviour move\""); ok = 0 }
      gsub(/trivial:|no new storage|no new unit|no behaviou?r move/, "", rest)
      gsub(/[,.:;-]/, " ", rest)
      if (ok && word_count(rest) < min_words) report_problem("trivial: give the reason in at least " min_words " words after the three \"no\" phrases")
      exit (problems > 0)
    }
    for (n = 1; n <= box_count; n++) {
      if (!(n in seen)) { report_problem("§SH" n ": missing; copy the box from kc-shape-the-change and fill it"); continue }
      if (seen[n] > 1) report_problem("§SH" n ": listed " seen[n] " times; keep one")
      if (!ticked[n]) { report_problem("§SH" n ": the box is not ticked; fill it, then tick it"); continue }
      if (word_count(body[n]) < min_words) report_problem("§SH" n ": the answer is under " min_words " words")
      if (tolower(body[n]) ~ /(^|[^a-z])(todo|tbd)([^a-z]|$)/ || tolower(body[n]) ~ /fill in/) report_problem("§SH" n ": unfinished (TODO, TBD or fill in)")
    }
    if ((shapes_box in seen) && shape_count < min_shapes) report_problem("§SH" shapes_box ": compare at least " min_shapes " shapes, as lines \"- shape A: ...\" and \"- shape B: ...\"")
    if (shapes_box in seen) {
      if (pick_line == "") report_problem("§SH" shapes_box ": no \"- pick: <label> <why>\" line")
      else {
        picked = pick_line; sub(/^[[:space:]]*- pick:[[:space:]]*/, "", picked)
        first = picked; sub(/[^A-Za-z0-9].*$/, "", first)
        if (!(first in shape_labels)) report_problem("§SH" shapes_box ": the pick must start with the label of a shape above (" first " is not one)")
        rest = picked; sub(/^[A-Za-z0-9]+/, "", rest)
        if (word_count(rest) < min_words) report_problem("§SH" shapes_box ": the pick needs its reason, at least " min_words " words")
      }
    }
    if ((rollout_box in seen) && flag_lines == 0) report_problem("§SH" rollout_box ": no flag line; one per change, \"- flag: <change> | yes|no | reason: <why> | decided-by: <who>\"")
    if ((failures_box in seen) && failure_lines == 0) report_problem("§SH" failures_box ": no failure line; \"- failure: <mode> | noticed-by: <signal>\"")
    if ((approval_box in seen) && ticked[approval_box]) {
      if (match(body[approval_box], /"[^"]+"/) == 0 || word_count(substr(body[approval_box], RSTART + 1, RLENGTH - 2)) < 2) \
        report_problem("§SH" approval_box ": quote the approval words of the person verbatim, at least 2 words between double quotes")
    }
    exit (problems > 0)
  }
' "$1"
