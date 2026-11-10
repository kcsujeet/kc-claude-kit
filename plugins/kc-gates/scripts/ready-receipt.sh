#!/usr/bin/env bash
# Writes and checks the receipts of kc-ready-for-review: one file per commit
# the pass ended on, named by its full SHA, under
# ${KC_READY_DIR:-$HOME/.claude/kc-ready-for-review}. guard-hand-off.sh lets a
# PR go to review only when its head commit has one.
#
#   ready-receipt.sh write <sha> --rounds 1 --open <n> --pass <dir>
#                    [--size small|full] [--scope-approved "<the user's words>"]
#       After a pass: its one gate round, the findings it left open for the
#       user, the pass folder, and the size pass-size.sh gave it.
#       Refused unless the pass folder shows the pass ran (see below).
#   ready-receipt.sh write <sha> --after <pass-sha>
#       After commits that only hold fixes to that pass: the ones the user
#       picked from its open list, or a reviewer asked for. Refused unless <pass-sha> has a pass or --after receipt and
#       <sha> descends from it. Run it from the repo root.
#   ready-receipt.sh write <sha> --checklist
#       After walking the repo's hand-off checklist alone, before opening a
#       draft PR in a repo whose checklist applies to drafts.
#   ready-receipt.sh check <sha> [--pass]
#       Exits 0 and prints the receipt when there is one, 1 otherwise. With
#       --pass, a receipt for the checklist alone doesn't count: handing a PR
#       to review needs the pass.
#
# The pass folder holds round-1/, gather-review.sh's --out-dir for the one
# gate round (review.diff, changed-files.txt, meta.env) plus a verdicts/
# folder with the blocks its agents returned, copied verbatim, and the
# orchestrator's SCOPE: block. The review's diff is made again from git,
# BASE...HEAD_SHA as meta.env names them, so the gates it needs come from the
# real change, not from a saved file. When <sha> is past round 1's head, or a
# finding is left open, the folder also holds fixes.txt, one tab-separated line per round-1 finding:
#
#   fixed<TAB><finding><TAB><test file>   a fix, and the test that fails when
#                                         it is broken
#   mechanical<TAB><finding>              a fix that changes no behaviour (a
#                                         rename, deletion, move or comment),
#                                         held by lint and types
#   open<TAB><finding><TAB><why>          left for the user: fails safe, needs
#                                         a decision, or pre-existing
#
# A pass has one gate round: a second one reviews code written while fixing
# the first, finds something in it, and so on. --rounds 2 is refused.
#
# A write after a pass is refused unless:
#   - the round has a well-formed block (GATE:, STATUS:, BOXES: with evidence
#     on every box) for every gate select-gates.sh lists for its diff (the
#     project-conventions gate only when .claude/review-conventions.md was in
#     the repo at that review's head: a pass can add the file midway), and for
#     verification, and a SCOPE: block marking §G1-§G5 each once, PASS, FAIL
#     or N/A, with evidence;
#   - <sha> descends from round 1's head;
#   - when there are fix commits (round 1's head to <sha>), fixes.txt has a
#     well-formed line per finding, each `fixed` line names a test file those
#     commits added or changed, and its `open` lines number --open;
#   - when the fix commits touch a file outside round
#     1's diff that is not a test, or bring a risk pass-size.sh reports that round 1's diff did
#     not have (a new kind: payments, data deletion), --scope-approved carries
#     the user's words approving that.
# It checks presence and shape, not whether the verdicts are true. Run it from
# the repo root; the commits must be in the local clone.
set -euo pipefail

receipts_dir=${KC_READY_DIR:-$HOME/.claude/kc-ready-for-review}
scripts_dir=$(cd "$(dirname "$0")" && pwd)

usage() {
  awk '/^#   ready-receipt.sh/ { show = 1 } show && /^#$/ { exit } show { sub(/^# ?/, ""); print }' "$0" >&2
  exit 2
}

is_full_sha() {
  printf '%s' "$1" | grep -Eqx '[0-9a-f]{40}'
}

problems=()
record_problem() { problems+=("$1"); }

# Prints a review folder's verdict files, each ended by a newline: a file saved
# without one would join its last line to the next file's GATE: line and hide
# that block.
print_verdicts() {
  local file
  for file in "$pass_dir/$1"/verdicts/*; do
    cat "$file"
    echo
  done
}

# Prints one line per block in the verdict text on stdin:
#   block<TAB><GATE name|SCOPE><TAB><status><TAB><boxes with evidence><TAB><malformed boxes>
# and one line per SCOPE box: scope<TAB><id><TAB><verdict><TAB><evidence>.
# Code fences around a pasted block are ignored. A box whose line ends at its
# colon counts when its evidence follows as indented bullets under it.
summarize_blocks() {
  awk '
    function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
    function strip_label(s) { sub(/^[A-Z]+:/, "", s); return trim(s) }
    # A gate name is one word; a label after it ("verification (diff B)") is not part of it.
    function gate_name(s) { s = strip_label(s); sub(/[[:space:](].*$/, "", s); return s }
    function settle_bare_box(has_nested_evidence) {
      if (!awaiting_evidence) return
      if (has_nested_evidence) boxes++
      else bad++
      awaiting_evidence = 0
    }
    function emit_block() {
      settle_bare_box(0)
      if (kind != "") printf "block\t%s\t%s\t%d\t%d\n", name, (status == "" ? "-" : status), boxes, bad
      kind = ""
    }
    /^[[:space:]]*```/ { next }
    /^GATE:/ { emit_block(); kind = "gate"; name = gate_name($0); status = ""; boxes = 0; bad = 0; section = ""; next }
    /^SCOPE:/ { emit_block(); kind = "scope"; name = "SCOPE"; status = "-"; boxes = 0; bad = 0; section = "boxes"; next }
    kind == "" { next }
    /^STATUS:/ { settle_bare_box(0); status = strip_label($0); next }
    /^BOXES:/ { settle_bare_box(0); section = "boxes"; next }
    /^FINDINGS:/ { settle_bare_box(0); section = "findings"; next }
    awaiting_evidence && /^[[:space:]]+- / && !/^[[:space:]]+- \[(PASS|FAIL|N\/A)\]/ { settle_bare_box(1); next }
    section == "boxes" && /^[[:space:]]*- \[/ {
      settle_bare_box(0)
      line = $0
      sub(/^[[:space:]]*- \[/, "", line)
      verdict = substr(line, 1, index(line, "]") - 1)
      rest = substr(line, index(line, "]") + 1)
      colon = index(rest, ":")
      id = ""
      evidence = ""
      if (colon) {
        id = trim(substr(rest, 1, colon - 1))
        evidence = trim(substr(rest, colon + 1))
      }
      is_known_verdict = verdict == "PASS" || verdict == "FAIL" || verdict == "N/A"
      has_id = id != ""
      has_evidence = evidence != ""
      if (is_known_verdict && has_id && has_evidence) {
        boxes++
        if (kind == "scope") printf "scope\t%s\t%s\t%s\n", id, verdict, evidence
      } else if (is_known_verdict && has_id && kind == "gate") {
        awaiting_evidence = 1
      } else {
        bad++
      }
    }
    END { emit_block() }'
}

# Prints the summary's SCOPE rows for <box-id>, the id alone or followed by a
# title (`§G1 Stacking`), never an id with more digits after it.
get_scope_rows() {
  awk -F '\t' -v id="$2" '
    function is_box(field) { return field == id || index(field, id " ") == 1 }
    $1 == "scope" && is_box($2)' <<< "$1"
}

check_gate_block() {
  local review=$1 summary=$2 gate=$3 rows block_count status boxes boxes_missing_evidence
  rows=$(printf '%s\n' "$summary" | awk -F '\t' -v gate="$gate" '$1 == "block" && $2 == gate')
  block_count=$(printf '%s' "$rows" | grep -c . || true)
  if [ "$block_count" -eq 0 ]; then
    record_problem "$review: no GATE: $gate block"
    return
  fi
  if [ "$block_count" -gt 1 ]; then
    record_problem "$review: $block_count GATE: $gate blocks; keep the one the gate returned last"
    return
  fi
  IFS=$'\t' read -r _ _ status boxes boxes_missing_evidence <<< "$rows"
  case "$status" in
    PASS | 'PASS (N/A)' | FAIL) ;;
    *) record_problem "$review: GATE: $gate has no STATUS: PASS, PASS (N/A) or FAIL" ;;
  esac
  [ "$boxes" -gt 0 ] || record_problem "$review: GATE: $gate has no BOXES: line with a box"
  [ "$boxes_missing_evidence" -eq 0 ] || record_problem "$review: GATE: $gate has $boxes_missing_evidence box(es) with no verdict or no evidence"
}

check_scope_block() {
  local review=$1 summary=$2 box_id box_count boxes_missing_evidence
  if ! printf '%s\n' "$summary" | grep -q $'^block\tSCOPE\t'; then
    record_problem "$review: no SCOPE: block"
    return
  fi
  boxes_missing_evidence=$(printf '%s\n' "$summary" | awk -F '\t' '$1 == "block" && $2 == "SCOPE" { print $5 }' | head -n 1)
  [ "$boxes_missing_evidence" -eq 0 ] || record_problem "$review: SCOPE: has $boxes_missing_evidence box(es) with no verdict or no evidence"
  for box_id in §G1 §G2 §G3 §G4 §G5; do
    box_count=$(get_scope_rows "$summary" "$box_id" | grep -c . || true)
    if [ "$box_count" -eq 0 ]; then
      record_problem "$review: SCOPE: has no $box_id box"
    elif [ "$box_count" -gt 1 ]; then
      record_problem "$review: SCOPE: marks $box_id $box_count times; one verdict per box"
    fi
  done
}

get_review_head() {
  sed -nE "s/^HEAD_SHA='?([0-9a-f]{40})'?$/\1/p" "$pass_dir/$1/meta.env" | head -n 1
}

# Prints the commit a review's BASE names: origin's copy of a branch first, as
# gather-review.sh's PR mode names a bare branch the clone may hold stale.
get_review_base_commit() {
  local base
  base=$(sed -nE "s/^BASE='?([^']*)'?$/\1/p" "$pass_dir/$1/meta.env" | head -n 1)
  [ -n "$base" ] || return 0
  git -C "$repo_root" rev-parse -q --verify "origin/$base^{commit}" 2>/dev/null \
    || git -C "$repo_root" rev-parse -q --verify "$base^{commit}" 2>/dev/null \
    || true
}

# The round needs every gate its diff lists, verification and a SCOPE: block. The project-conventions gate is needed only when the repo had
# .claude/review-conventions.md at the review's head.
check_review() {
  local review=$1 dir=$pass_dir/$1 summary gate_report gates gate required head base_commit
  if [ ! -d "$dir" ]; then
    record_problem "$review: no $review/ folder in the pass folder"
    return
  fi
  for required in review.diff changed-files.txt meta.env; do
    [ -f "$dir/$required" ] || { record_problem "$review: no $required (save gather-review.sh's --out-dir there)"; return; }
  done
  if [ -z "$(ls -A "$dir/verdicts" 2>/dev/null)" ]; then
    record_problem "$review: no verdict blocks in $review/verdicts/"
    return
  fi
  head=$(get_review_head "$review")
  if ! git -C "$repo_root" cat-file -e "$head^{commit}" 2>/dev/null; then
    record_problem "$review: meta.env names no HEAD_SHA this clone has"
    return
  fi
  base_commit=$(get_review_base_commit "$review")
  if [ -z "$base_commit" ]; then
    record_problem "$review: meta.env names no BASE this clone has"
    return
  fi
  git -C "$repo_root" diff --no-color --no-ext-diff --src-prefix=a/ --dst-prefix=b/ "$base_commit...$head" > "$regenerated_dir/$review.diff"
  git -C "$repo_root" diff --no-ext-diff --name-only "$base_commit...$head" > "$regenerated_dir/$review.files"
  summary=$(print_verdicts "$review" | summarize_blocks)
  gate_report=$(bash "$scripts_dir/select-gates.sh" "$regenerated_dir/$review.diff" "$regenerated_dir/$review.files" "$repo_root")
  gates=$(printf '%s\n' "$gate_report" | sed -n 's/^GATES=//p')
  if ! git -C "$repo_root" cat-file -e "$head:.claude/review-conventions.md" 2>/dev/null; then
    gates=${gates/,project-conventions/}
  fi
  for gate in ${gates//,/ }; do
    check_gate_block "$review" "$summary" "$gate"
  done
  check_gate_block "$review" "$summary" verification
  check_scope_block "$review" "$summary"
}

# Paths of test files, as the conventions' sweeps read them.
readonly TEST_PATHS='(\.(test|spec)\.[A-Za-z0-9]+$|_(test|spec)\.[A-Za-z0-9]+$|(^|/)test_[^/]*\.py$|(^|/)(test|tests|spec|__tests__|e2e)/)'

# Checks fixes.txt, the record of what became of each round-1 finding, against
# the fix commits (round 1's head to <sha>) and --open.
check_fixes_record() {
  local round_one_head=$1 open=$2 record=$pass_dir/fixes.txt fix_files line_number=0 open_lines=0 status finding detail
  if [ ! -f "$record" ]; then
    record_problem "no fixes.txt in the pass folder: the commits since round 1 hold fixes, and each needs its line (fixed, mechanical or open)"
    return
  fi
  fix_files=$(git -C "$repo_root" -c core.quotePath=false diff --name-only "$round_one_head" "$sha")
  while IFS=$'\t' read -r status finding detail || [ -n "$status" ]; do
    line_number=$((line_number + 1))
    [ -n "$status" ] || continue
    if [ -z "$finding" ]; then
      record_problem "fixes.txt line $line_number: no finding after '$status'"
      continue
    fi
    case "$status" in
      fixed)
        if [ -z "$detail" ]; then
          record_problem "fixes.txt line $line_number: a fix names the test that fails when it is broken"
        elif ! printf '%s\n' "$detail" | grep -Eq "$TEST_PATHS"; then
          record_problem "fixes.txt line $line_number: $detail is not a test file"
        elif ! printf '%s\n' "$fix_files" | grep -qxF "$detail"; then
          record_problem "fixes.txt line $line_number: the fix commits don't add or change $detail"
        fi ;;
      mechanical) ;;
      open)
        open_lines=$((open_lines + 1))
        case "$detail" in
          'fails safe' | 'needs a decision' | 'pre-existing') ;;
          *) record_problem "fixes.txt line $line_number: an open finding says why: fails safe, needs a decision or pre-existing" ;;
        esac ;;
      *) record_problem "fixes.txt line $line_number: '$status' is not fixed, mechanical or open" ;;
    esac
  done < "$record"
  [ "$open_lines" = "$open" ] || record_problem "fixes.txt has $open_lines open line(s), --open says $open"
}

# Prints the kinds of risk pass-size.sh reports for <diff> and <changed-files>,
# one per line, without the path it names (`payments`, not
# `payments (shop/pay.sh)`); `pass-size.sh failed` when it can't run, so the
# user is asked rather than the check skipped.
list_risk_kinds() {
  local report
  # Its stderr (GNU awk's warnings among it) is no part of the receipt's output;
  # a failure still counts as a risk.
  report=$(bash "$scripts_dir/pass-size.sh" "$1" "$2" "$repo_root" 2>/dev/null) || report="risk: pass-size.sh failed"
  printf '%s\n' "$report" | sed -n 's/^risk: //p' | grep -vx none | sed -E 's/ \(.*\)$//' | sort -u
}

# Prints what the fix commits (round 1's head to <sha>) add to round 1's
# footprint: files outside its diff that are not tests (a fix brings its test),
# and kinds of risk its diff didn't have.
# A fix inside an auth or payments change asks nothing new. Paths are quoted as
# gather-review.sh quotes round 1's list.
get_widened_footprint() {
  local round_one_head=$1 round_one_files=$regenerated_dir/round-1.files fix_diff fix_files outside round_one_risks fix_risks new_risks
  fix_diff=$(mktemp)
  fix_files=$(mktemp)
  git -C "$repo_root" diff --no-color --no-ext-diff --src-prefix=a/ --dst-prefix=b/ "$round_one_head" "$sha" > "$fix_diff"
  git -C "$repo_root" diff --name-only "$round_one_head" "$sha" > "$fix_files"
  outside=$(grep -vxF -f "$round_one_files" "$fix_files" | grep -vE "$TEST_PATHS")
  round_one_risks=$(list_risk_kinds "$regenerated_dir/round-1.diff" "$round_one_files")
  fix_risks=$(list_risk_kinds "$fix_diff" "$fix_files")
  new_risks=$(comm -13 <(printf '%s\n' "$round_one_risks") <(printf '%s\n' "$fix_risks"))
  rm -f "$fix_diff" "$fix_files"
  [ -z "$outside" ] || printf 'outside round 1: %s\n' "$outside"
  [ -z "$new_risks" ] || printf 'new risk: %s\n' "$new_risks"
}

write_pass_receipt() {
  local rounds=$1 open=$2 size=$3 scope_approved=$4 line round_one_head
  local widened=""
  [ "$rounds" = 1 ] || { echo "ready-receipt: --rounds is 1: a pass has one gate round, and its fixes are held by fixes.txt, not by another round" >&2; exit 2; }
  printf '%s' "$open" | grep -Eqx '[0-9]+' || { echo "ready-receipt: --open is a count" >&2; exit 2; }
  case "$size" in '' | small | full) ;; *) echo "ready-receipt: --size is small or full" >&2; exit 2 ;; esac
  [ -n "$pass_dir" ] || { echo "ready-receipt: --pass <dir> is required: the folder of the pass's reviews and verdict blocks" >&2; exit 2; }
  [ -d "$pass_dir" ] || { echo "ready-receipt: no pass folder $pass_dir" >&2; exit 2; }
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "ready-receipt: run it from the repo the pass reviewed" >&2; exit 2; }
  regenerated_dir=$(mktemp -d)
  trap 'rm -rf "$regenerated_dir"' EXIT

  check_review round-1
  git -C "$repo_root" cat-file -e "$sha^{commit}" 2>/dev/null || record_problem "commit $sha is not in this clone"
  if [ "${#problems[@]}" -eq 0 ]; then
    round_one_head=$(get_review_head round-1)
    git -C "$repo_root" merge-base --is-ancestor "$round_one_head" "$sha" 2>/dev/null \
      || record_problem "$sha does not descend from round 1's head (a rebase or reset since): round 1 reviewed another diff; run the pass again"
  fi
  if [ "${#problems[@]}" -eq 0 ] && { [ "$round_one_head" != "$sha" ] || [ "$open" != 0 ]; }; then
    check_fixes_record "$round_one_head" "$open"
  fi
  if [ "${#problems[@]}" -eq 0 ]; then
    widened=$(get_widened_footprint "$round_one_head")
    if [ -n "$widened" ] && [ -z "$scope_approved" ]; then
      record_problem "the fixes reach past round 1's diff; show the user these and pass their words as --scope-approved \"<their words>\":"
      while IFS= read -r line; do record_problem "  $line"; done <<< "$widened"
    fi
  fi
  if [ "${#problems[@]}" -gt 0 ]; then
    echo "ready-receipt: refused; the pass folder does not show the pass ran in full:" >&2
    printf '  %s\n' "${problems[@]}" >&2
    exit 1
  fi
  {
    printf 'sha=%s\ndate=%s\nrounds=%s\nopen=%s\npass=%s\n' "$sha" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$rounds" "$open" "$pass_dir"
    [ -z "$size" ] || printf 'size=%s\n' "$size"
    [ -z "$widened" ] || printf 'scope_approved=%s\n' "$scope_approved"
  } > "$receipts_dir/$sha"
}

# Prints <sha>'s receipt, or fails when it has none or, with --pass, when it
# is for the checklist alone.
check_receipt() {
  local receipt=$receipts_dir/$1 pass_only=false
  case "${*:2}" in
    '') ;;
    --pass) pass_only=true ;;
    *) usage ;;
  esac
  [ -f "$receipt" ] || return 1
  if $pass_only && grep -qx 'checklist=walked' "$receipt"; then
    return 1
  fi
  cat "$receipt"
}

write_receipt() {
  local rounds="" open="" after="" size="" scope_approved="" checklist=false
  shift
  pass_dir=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --checklist) checklist=true; shift ;;
      --rounds) rounds=$2; shift 2 ;;
      --open) open=$2; shift 2 ;;
      --size) size=$2; shift 2 ;;
      --after) after=$2; shift 2 ;;
      --pass) pass_dir=$2; shift 2 ;;
      --scope-approved) scope_approved=$2; shift 2 ;;
      *) usage ;;
    esac
  done
  mkdir -p "$receipts_dir"
  if $checklist; then
    printf 'sha=%s\ndate=%s\nchecklist=walked\n' "$sha" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$receipts_dir/$sha"
  elif [ -n "$after" ]; then
    is_full_sha "$after" || { echo "ready-receipt: --after needs a full SHA" >&2; exit 2; }
    if ! check_receipt "$after" --pass >/dev/null; then
      echo "ready-receipt: $after has no pass receipt; run the pass first" >&2
      exit 1
    fi
    if ! git merge-base --is-ancestor "$after" "$sha" 2>/dev/null; then
      echo "ready-receipt: $sha does not descend from $after, so it holds more than fixes to that pass; run the pass on it" >&2
      exit 1
    fi
    printf 'sha=%s\ndate=%s\nafter=%s\n' "$sha" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$after" > "$receipts_dir/$sha"
  else
    write_pass_receipt "$rounds" "$open" "$size" "$scope_approved"
  fi
  echo "receipt written: $receipts_dir/$sha"
}

[ "$#" -ge 2 ] || usage
action=$1
sha=$2
shift 2
is_full_sha "$sha" || { echo "ready-receipt: <sha> must be a full 40-character SHA" >&2; exit 2; }

case "$action" in
  write) write_receipt "$sha" "$@" ;;
  check) check_receipt "$sha" "$@" ;;
  *) usage ;;
esac
