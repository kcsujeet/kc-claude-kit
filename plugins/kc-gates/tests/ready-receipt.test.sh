#!/usr/bin/env bash
# Tests scripts/ready-receipt.sh: a pass's receipt is written only when its
# pass folder shows each round's gate, verification and SCOPE: blocks (real
# gate replies, fences and all, among them); when the fixes reach past round
# 1's diff or bring a kind of risk it didn't have, only with the user's words;
# and only for the history round 1 reviewed. Each case builds a throwaway
# repo: round 1 changes shop/total.sh and adds shop/tax.sh, round 1's fixes
# append a line to total.sh, and the fix check's fixes append one to tax.sh.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
scripts="$(dirname "$tests_dir")/scripts"
export KC_READY_DIR="$work_dir/receipts"

# A 40-character commit id made of <char>, for a commit no clone has.
make_fake_sha() { printf '%040d' 0 | tr 0 "$1"; }
run_git() { git -C "$repo" -c user.name=t -c user.email=t@example.test "$@"; }
commit_all() { run_git add -A && run_git commit -q -m "$1" && run_git rev-parse HEAD; }

# Builds the repo for one case. With `widen`, round 1's fixes also add a file
# round 1 never touched; with `sensitive`, round 1 adds a payments file and
# its fixes edit it; with `deletes-data`, round 1's fixes add a line that
# deletes data, a risk round 1 didn't have; with `accented`, round 1 adds
# shop/café.sh and its fixes edit it; with `ruby`, round 1 also adds a Ruby
# file; with `conventions`, the base holds review conventions.
build_repo() {
  local variant=${1:-plain}
  repo="$work_dir/repo-$RANDOM$RANDOM"
  git init -q -b main "$repo"
  mkdir -p "$repo/shop"
  printf '#!/bin/sh\necho base1\necho base2\n' > "$repo/shop/total.sh"
  if [ "$variant" = conventions ]; then
    mkdir -p "$repo/.claude"
    printf -- '- [ ] §X1 A house rule.\n' > "$repo/.claude/review-conventions.md"
  fi
  base=$(commit_all base)
  # shellcheck disable=SC2016 # the fixture's own $1, written as text.
  printf 'if [ "$1" ]; then\n  echo r1\nfi\n' >> "$repo/shop/total.sh"
  printf '#!/bin/sh\necho tax1\necho tax2\n' > "$repo/shop/tax.sh"
  if [ "$variant" = sensitive ]; then
    mkdir -p "$repo/shop/payments"
    printf '#!/bin/sh\necho charge\n' > "$repo/shop/payments/charge.sh"
  fi
  [ "$variant" != accented ] || printf '#!/bin/sh\necho cafe\n' > "$repo/shop/café.sh"
  [ "$variant" != ruby ] || printf 'class Order; end\n' > "$repo/shop/order.rb"
  round_one=$(commit_all "round 1")
  [ "$variant" != accented ] || printf 'echo latte\n' >> "$repo/shop/café.sh"
  printf 'echo f1\n' >> "$repo/shop/total.sh"
  [ "$variant" != widen ] || printf '#!/bin/sh\necho ship\n' > "$repo/shop/ship.sh"
  [ "$variant" != sensitive ] || printf 'echo refund\n' >> "$repo/shop/payments/charge.sh"
  [ "$variant" != deletes-data ] || printf 'psql -c "DELETE FROM orders"\n' >> "$repo/shop/total.sh"
  fix_check=$(commit_all "round 1 fixes")
  printf 'echo f2\n' >> "$repo/shop/tax.sh"
  round_two=$(commit_all "fix check fixes")
}

# Saves one review's gather-review output: the diff <from>..<to>, its files
# and meta.env naming <to> as the head.
save_review() {
  local from=$2 to=$3 dir=$pass_dir/$1
  mkdir -p "$dir/verdicts"
  run_git diff --src-prefix=a/ --dst-prefix=b/ "$from" "$to" > "$dir/review.diff"
  run_git diff --name-only "$from" "$to" > "$dir/changed-files.txt"
  printf 'HEAD_SHA=%s\nBASE=%s\n' "$to" "$from" > "$dir/meta.env"
}

build_gate_block() {
  printf 'GATE: %s\nSTATUS: PASS\nBOXES:\n- [PASS] §X1: 0 hits, swept shop/\nFINDINGS:\n' "$1"
}

# Writes a block for every gate select-gates.sh lists for the review, and for
# a round the verification block and a SCOPE: block.
save_verdicts() {
  local with_scope=$2 dir=$pass_dir/$1 gates gate
  gates=$(cd "$repo" && bash "$scripts/select-gates.sh" "$dir/review.diff" "$dir/changed-files.txt" | sed -n 's/^GATES=//p')
  for gate in ${gates//,/ }; do
    build_gate_block "$gate" > "$dir/verdicts/$gate.txt"
  done
  if [ "$with_scope" = scope ]; then
    build_gate_block verification > "$dir/verdicts/verification.txt"
    # shellcheck disable=SC2016 # the backticks fence the block, as a pasted reply has them.
    printf '```\nSCOPE:\nBOXES:\n- [N/A] §G1: local diff\n- [PASS] §G2: matches the title\n- [N/A] §G3: no linked issue\n- [N/A] §G4: diff read whole\n%s\n```\n' \
      "- [PASS] §G5: goal: totals; weighed one script; two are needed" > "$dir/verdicts/scope.txt"
  fi
}

# Builds a complete pass folder for the repo: one round, or two with the fix
# check between them.
build_pass() {
  local rounds=$1
  pass_dir="$work_dir/pass-$RANDOM$RANDOM"
  save_review round-1 "$base" "$round_one"
  save_verdicts round-1 scope
  if [ "$rounds" = 2 ]; then
    save_review fix-check "$round_one" "$fix_check"
    save_verdicts fix-check no-scope
    save_review round-2 "$base" "$round_two"
    save_verdicts round-2 scope
  fi
}

# Edits a round's SCOPE: block with a sed script, leaving no backup file
# beside the blocks.
edit_scope() {
  sed "$2" "$pass_dir/$1/verdicts/scope.txt" > "$work_dir/scope.edited"
  mv "$work_dir/scope.edited" "$pass_dir/$1/verdicts/scope.txt"
}

# Runs a write for <sha> and checks the verdict; the output stays in $last_output.
last_output=""
expect_write() {
  local expectation=$1 label=$2 sha=$3 actual=written
  shift 3
  last_output=$(cd "$repo" && bash "$scripts/ready-receipt.sh" write "$sha" "$@" 2>&1) || actual=refused
  expect_eq "$label" "$expectation" "$actual"
}
expect_said() { expect_contains "$1" "$2" "$last_output"; }

# Both kinds of pass, complete, are written.
build_repo
build_pass 2
expect_write written "a full pass with every block is written" "$round_two" --rounds 2 --open 0 --size full --pass "$pass_dir"
expect_contains "the receipt names its pass folder" "pass=$pass_dir" "$(bash "$scripts/ready-receipt.sh" check "$round_two")"
written_pass_head=$round_two
expect_write written "a one-round pass with every block is written" "$round_one" --rounds 1 --open 0 --size small --pass "$pass_dir"
expect_contains "the receipt records the pass's size" "size=small" "$(bash "$scripts/ready-receipt.sh" check "$round_one")"
expect_eq "a one-round pass reads no fix check: it prints only the receipt line" "receipt written: $KC_READY_DIR/$round_one" "$last_output"

# The pass folder must show every gate, verification and SCOPE:.
expect_write refused "no --pass is refused" "$round_two" --rounds 2 --open 0
expect_said "it asks for the pass folder" "--pass <dir> is required"
expect_write refused "a --pass folder that is not there is refused" "$round_two" --rounds 2 --open 0 --pass "$work_dir/no-such-pass"
expect_said "it names the folder" "no pass folder $work_dir/no-such-pass"

build_pass 2
rm "$pass_dir/round-2/verdicts/testing.txt"
expect_write refused "a listed gate with no block is refused" "$round_two" --rounds 2 --open 0 --pass "$pass_dir"
expect_said "it names the round and the gate" "round-2: no GATE: testing block"

build_pass 2
rm "$pass_dir/round-1/verdicts/verification.txt"
expect_write refused "a round with no verification block is refused" "$round_two" --rounds 2 --open 0 --pass "$pass_dir"
expect_said "it names the verification gate" "round-1: no GATE: verification block"

build_pass 2
printf 'GATE: naming\nBOXES:\n- [PASS] §N1: 0 hits\n' > "$pass_dir/round-1/verdicts/naming.txt"
expect_write refused "a block with no STATUS: is refused" "$round_two" --rounds 2 --open 0 --pass "$pass_dir"
expect_said "it names the missing status" "GATE: naming has no STATUS:"

build_pass 2
printf 'GATE: naming\nSTATUS: PASS\nFINDINGS:\n' > "$pass_dir/round-1/verdicts/naming.txt"
expect_write refused "a block with no boxes is refused" "$round_two" --rounds 2 --open 0 --pass "$pass_dir"
expect_said "it names the missing boxes" "GATE: naming has no BOXES: line with a box"

build_pass 2
printf 'GATE: naming\nSTATUS: PASS\nBOXES:\n- [PASS] §N1: 0 hits\n- [PASS] §N2:\n' > "$pass_dir/round-1/verdicts/naming.txt"
expect_write refused "a box with no evidence is refused" "$round_two" --rounds 2 --open 0 --pass "$pass_dir"
expect_said "it counts the bare box" "GATE: naming has 1 box(es) with no verdict or no evidence"

build_pass 2
printf 'GATE: naming\nSTATUS: PASS\nBOXES:\n- [PASS] §N1: 0 hits in shop/total.sh\n  and shop/tax.sh\n\n- [PASS] §N2: 0 hits\nFINDINGS:\n' > "$pass_dir/round-1/verdicts/naming.txt"
expect_write written "a box whose evidence wraps, or a blank line between boxes, is no bad box" "$round_two" --rounds 2 --open 0 --pass "$pass_dir"

build_pass 2
printf 'GATE: naming\nSTATUS: PASS\nBOXES:\n- [PASS] §N1: 0 hits\nFINDINGS:\n- none' > "$pass_dir/round-1/verdicts/a-naming.txt"
rm "$pass_dir/round-1/verdicts/naming.txt"
expect_write written "a block saved with no trailing newline keeps the next file's block" "$round_two" --rounds 2 --open 0 --pass "$pass_dir"

build_pass 2
build_gate_block naming >> "$pass_dir/round-1/verdicts/clarity.txt"
expect_write refused "two blocks for one gate are refused" "$round_two" --rounds 2 --open 0 --pass "$pass_dir"
expect_said "it names the repeated gate" "2 GATE: naming blocks"

build_pass 2
rm "$pass_dir/round-2/verdicts/scope.txt"
expect_write refused "a round with no SCOPE: block is refused" "$round_two" --rounds 2 --open 0 --pass "$pass_dir"
expect_said "it names the missing scope" "round-2: no SCOPE: block"

build_pass 2
edit_scope round-1 '/§G4/d'
expect_write refused "a SCOPE: block missing a box is refused" "$round_two" --rounds 2 --open 0 --pass "$pass_dir"
expect_said "it names the missing box" "SCOPE: has no §G4 box"

build_pass 2
edit_scope round-1 's/^- \[N\/A\] §G4: .*/- [N\/A] §G2: also/'
expect_write refused "a SCOPE: box marked twice is refused" "$round_two" --rounds 2 --open 0 --pass "$pass_dir"
expect_said "it names the twice-marked box" "marks §G2 2 times"

build_pass 2
edit_scope round-1 's/^- \[N\/A\] §G3: .*/- [N\/A] §G3:/'
expect_write refused "a SCOPE: box with no evidence is refused" "$round_two" --rounds 2 --open 0 --pass "$pass_dir"
expect_said "it counts the bare scope box" "SCOPE: has 1 box(es) with no verdict or no evidence"

build_pass 2
edit_scope round-1 's/§G1:/§G1 Stacking:/'
expect_write written "a SCOPE: box id with a title is that box" "$round_two" --rounds 2 --open 0 --pass "$pass_dir"

build_pass 2
# An id with one more digit, built so the rules lint doesn't read it as a citation.
extra_digit=0
edit_scope round-1 "s/§G1:/§G1${extra_digit}:/"
expect_write refused "a longer SCOPE: id is another box" "$round_two" --rounds 2 --open 0 --pass "$pass_dir"
expect_said "it names the missing box" "SCOPE: has no §G1 box"

build_pass 2
rm -r "$pass_dir/fix-check"
expect_write refused "two rounds with no fix check are refused" "$round_two" --rounds 2 --open 0 --pass "$pass_dir"
expect_said "it names the missing review" "fix-check: no fix-check/ folder"

build_pass 2
rm "$pass_dir/fix-check/verdicts/"*
expect_write refused "a review with no verdict blocks is refused" "$round_two" --rounds 2 --open 0 --pass "$pass_dir"
expect_said "it names the empty verdicts folder" "fix-check: no verdict blocks"

build_pass 2
rm "$pass_dir/round-2/meta.env"
expect_write refused "a review with no meta.env is refused" "$round_two" --rounds 2 --open 0 --pass "$pass_dir"
expect_said "it names the missing file" "round-2: no meta.env"

build_pass 2
printf 'HEAD_SHA=%s\n' "$(make_fake_sha d)" > "$pass_dir/round-2/meta.env"
expect_write refused "a review whose head the clone lacks is refused" "$round_two" --rounds 2 --open 0 --pass "$pass_dir"
expect_said "it names the review" "round-2: meta.env names no HEAD_SHA this clone has"

build_pass 2
expect_write refused "a commit the clone lacks is refused" "$(make_fake_sha c)" --rounds 2 --open 0 --pass "$pass_dir"
expect_said "it names the commit" "is not in this clone"

# The gates come from the tree each review read, not from today's checkout.
build_pass 2
mkdir -p "$repo/.claude"
printf -- '- [ ] §X1 A house rule.\n' > "$repo/.claude/review-conventions.md"
expect_write written "a conventions file only in today's checkout adds no gate to the reviews" "$round_two" --rounds 2 --open 0 --pass "$pass_dir"

build_repo conventions
build_pass 2
rm "$pass_dir/round-1/verdicts/project-conventions.txt"
expect_write refused "conventions the repo had at a review's head need their gate" "$round_two" --rounds 2 --open 0 --pass "$pass_dir"
expect_said "it names the conventions gate" "round-1: no GATE: project-conventions block"

# The reviews read one history in order, and a two-round pass ends on round 2's head.
build_repo
build_pass 2
printf 'echo late\n' >> "$repo/shop/total.sh"
expect_write refused "a commit past round 2's head is refused" "$(commit_all "a change after round 2")" --rounds 2 --open 0 --pass "$pass_dir"
expect_said "it names the commit round 2 reviewed" "round-2 reviewed $round_two"

build_repo
build_pass 1
run_git checkout -q -b rebased "$base"
printf 'echo rebased\n' >> "$repo/shop/total.sh"
expect_write refused "a commit that does not descend from round 1's head is refused" "$(commit_all "rebased")" --rounds 1 --open 0 --pass "$pass_dir"
expect_said "it says round 1 reviewed another diff" "does not descend from round 1's head"

# Fixes past round 1's diff, or bringing a risk it didn't have, need the user's words.
build_repo widen
build_pass 2
expect_write refused "fixes adding a file outside round 1's diff are refused" "$round_two" --rounds 2 --open 0 --pass "$pass_dir"
expect_said "it lists the file" "outside round 1: shop/ship.sh"
expect_write refused "an empty approval is refused" "$round_two" --rounds 2 --open 0 --pass "$pass_dir" --scope-approved ""
expect_write written "the user's words let it through" "$round_two" --rounds 2 --open 0 --pass "$pass_dir" --scope-approved "yes, add the shipping script"
expect_contains "the receipt keeps the user's words" "scope_approved=yes, add the shipping script" "$(bash "$scripts/ready-receipt.sh" check "$round_two")"

build_repo sensitive
build_pass 2
expect_write written "a fix to a payments change round 1 already had needs no approval" "$round_two" --rounds 2 --open 0 --pass "$pass_dir"

build_repo deletes-data
build_pass 2
expect_write refused "fixes bringing a risk round 1 didn't have are refused" "$round_two" --rounds 2 --open 0 --pass "$pass_dir"
expect_said "it names the new kind of risk" "new risk: deletes data"
expect_write written "the user's words let a new risk through" "$round_two" --rounds 2 --open 0 --pass "$pass_dir" --scope-approved "go ahead"

# A file round 1 touched, quoted the way gather-review.sh lists it, is inside round 1's diff.
build_repo accented
build_pass 2
expect_write written "a fix to a non-ASCII-named round-1 file needs no approval" "$round_two" --rounds 2 --open 0 --pass "$pass_dir"

# Real gate replies, as a pass saved them: one bare with nested evidence, one
# fenced. They stand in for those gates' blocks; a change in a gate's format
# fails here first.
build_repo
build_pass 1
cp "$tests_dir/fixtures/ready-receipt/real-verdicts/"*.txt "$pass_dir/round-1/verdicts/"
expect_write written "a pass folder with real gate replies is written" "$round_one" --rounds 1 --open 0 --pass "$pass_dir"
summary=$(cat "$tests_dir/fixtures/ready-receipt/real-verdicts/"*.txt | grep -cE '^GATE:')
expect_eq "each real reply holds one block" 2 "$summary"

# The gates come from the change git holds, not from the folder's saved diff.
build_repo ruby
build_pass 1
: > "$pass_dir/round-1/review.diff"
: > "$pass_dir/round-1/changed-files.txt"
rm "$pass_dir/round-1/verdicts/"*
save_verdicts round-1 scope
expect_write refused "a folder whose saved diff leaves a file out still needs that file's gate" "$round_one" --rounds 1 --open 0 --pass "$pass_dir"
expect_said "it names the gate the real change needs" "round-1: no GATE: rails block"

build_pass 1
printf 'HEAD_SHA=%s\n' "$round_one" > "$pass_dir/round-1/meta.env"
expect_write refused "a review with no BASE is refused" "$round_one" --rounds 1 --open 0 --pass "$pass_dir"
expect_said "it names the missing base" "round-1: meta.env names no BASE this clone has"

# The other receipts, the flags and the usage.
build_repo
build_pass 2
expect_write written "a pass to follow is written" "$round_two" --rounds 2 --open 0 --pass "$pass_dir"
pass_head=$round_two
printf 'echo picked\n' >> "$repo/shop/total.sh"
picked_fix=$(commit_all "a fix the user picked")
expect_write refused "--after refuses a pass with no receipt" "$picked_fix" --after "$(make_fake_sha c)"
expect_write written "--after follows a pass with a receipt" "$picked_fix" --after "$pass_head"
expect_write refused "--after refuses a commit that does not descend from the pass" "$base" --after "$pass_head"
expect_said "it says why" "does not descend from $pass_head"
expect_write refused "a third round is refused" "$round_two" --rounds 3 --open 0 --pass "$pass_dir"
expect_write refused "an unknown size is refused" "$round_two" --rounds 2 --open 0 --size tiny --pass "$pass_dir"
expect_write refused "an --open that is no count is refused" "$round_two" --rounds 2 --open some --pass "$pass_dir"
expect_said "it asks for a count" "--open is a count"
expect_write written "--checklist needs no pass folder" "$(make_fake_sha e)" --checklist
expect_contains "--checklist records the walk" "checklist=walked" "$(bash "$scripts/ready-receipt.sh" check "$(make_fake_sha e)")"
expect_write refused "--after refuses a commit with only the checklist's receipt" "$(make_fake_sha 9)" --after "$(make_fake_sha e)"
if bash "$scripts/ready-receipt.sh" check "$(make_fake_sha e)" --pass >/dev/null; then
  record "check --pass refuses a checklist receipt" fail "it passed"
else
  record "check --pass refuses a checklist receipt" ok
fi
expect_contains "check --pass prints a pass receipt" "rounds=2" "$(bash "$scripts/ready-receipt.sh" check "$written_pass_head" --pass)"
check_status=0
bash "$scripts/ready-receipt.sh" check "$(make_fake_sha e)" --other >/dev/null 2>&1 || check_status=$?
expect_eq "check with anything but --pass after the SHA prints the usage" 2 "$check_status"
if bash "$scripts/ready-receipt.sh" check "$(make_fake_sha b)" >/dev/null; then
  record "check fails for a commit without a receipt" fail "check passed"
else
  record "check fails for a commit without a receipt" ok
fi
usage_text=$(bash "$scripts/ready-receipt.sh" 2>&1 || true)
expect_contains "no arguments print the usage" "ready-receipt.sh write <sha> --rounds <n> --open <n> --pass <dir>" "$usage_text"
expect_eq "the usage has the header's lines without their comment marks" 0 "$(printf '%s\n' "$usage_text" | grep -c '^#' || true)"

finish
