#!/usr/bin/env bash
# Tests scripts/ready-receipt.sh: a pass's receipt is written only when its
# pass folder shows the one round's gate, verification and SCOPE: blocks (real
# gate replies, fences and all, among them) and a line in fixes.txt for each
# finding, a fix naming a test its commits changed; when the fixes reach past
# round 1's diff or bring a kind of risk it didn't have, only with the user's
# words; and only for the history round 1 reviewed. Each case builds a
# throwaway repo: round 1 changes shop/total.sh and adds shop/tax.sh, and its
# fixes append a line to each and add shop/total.test.sh.
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
  printf 'echo f2\n' >> "$repo/shop/tax.sh"
  # shellcheck disable=SC2016 # the fixture test's own $(...), written as text.
  printf '#!/bin/sh\ntest "$(sh shop/total.sh)" = f1\n' > "$repo/shop/total.test.sh"
  fixed_head=$(commit_all "round 1 fixes")
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

# Builds a complete pass folder for the repo: the round, and the record of its
# fixes (one fix with its test, one rename).
build_pass() {
  pass_dir="$work_dir/pass-$RANDOM$RANDOM"
  save_review round-1 "$base" "$round_one"
  save_verdicts round-1 scope
  printf 'fixed\tshop/total.sh:4 prints nothing for f1\tshop/total.test.sh\nmechanical\tshop/tax.sh:2 unclear name\n' > "$pass_dir/fixes.txt"
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

# A pass with fixes, and one with none, are written.
build_repo
build_pass
expect_write written "a pass with every block and a record of its fixes is written" "$fixed_head" --rounds 1 --open 0 --size full --pass "$pass_dir"
expect_contains "the receipt names its pass folder" "pass=$pass_dir" "$(bash "$scripts/ready-receipt.sh" check "$fixed_head")"
written_pass_head=$fixed_head
rm "$pass_dir/fixes.txt"
expect_write written "a pass that found nothing needs no fixes record" "$round_one" --rounds 1 --open 0 --size small --pass "$pass_dir"
expect_contains "the receipt records the pass's size" "size=small" "$(bash "$scripts/ready-receipt.sh" check "$round_one")"
expect_eq "it prints only the receipt line" "receipt written: $KC_READY_DIR/$round_one" "$last_output"

# One gate round (§H1): a second is refused. The fixes are held by their record: a fix names a
# test its commits changed (§H4), and what is left open says why and numbers --open (§H3).
build_pass
expect_write refused "a second round is refused" "$fixed_head" --rounds 2 --open 0 --pass "$pass_dir"
expect_said "it says the fixes are held by the record" "a pass has one gate round"

rm "$pass_dir/fixes.txt"
expect_write refused "fix commits with no fixes.txt are refused" "$fixed_head" --rounds 1 --open 0 --pass "$pass_dir"
expect_said "it asks for the record" "no fixes.txt in the pass folder"
expect_write refused "an open finding with no fixes.txt is refused" "$round_one" --rounds 1 --open 1 --pass "$pass_dir"

write_fixes() { printf '%b' "$1" > "$pass_dir/fixes.txt"; }
write_fixes 'fixed\tshop/total.sh:4 prints nothing\n'
expect_write refused "a fix with no test is refused" "$fixed_head" --rounds 1 --open 0 --pass "$pass_dir"
expect_said "it asks for the test" "a fix names the test that fails when it is broken"

write_fixes 'fixed\tshop/total.sh:4 prints nothing\tshop/total.sh\n'
expect_write refused "a fix whose proof is not a test file is refused" "$fixed_head" --rounds 1 --open 0 --pass "$pass_dir"
expect_said "it names the file" "shop/total.sh is not a test file"

write_fixes 'fixed\tshop/total.sh:4 prints nothing\tshop/tax.test.sh\n'
expect_write refused "a fix naming a test its commits never touched is refused" "$fixed_head" --rounds 1 --open 0 --pass "$pass_dir"
expect_said "it names the untouched test" "the fix commits don't add or change shop/tax.test.sh"

write_fixes 'skipped\tshop/total.sh:4 prints nothing\n'
expect_write refused "an unknown status is refused" "$fixed_head" --rounds 1 --open 0 --pass "$pass_dir"
expect_said "it names the status" "'skipped' is not fixed, mechanical or open"

write_fixes 'mechanical\n'
expect_write refused "a line with no finding is refused" "$fixed_head" --rounds 1 --open 0 --pass "$pass_dir"
expect_said "it names the line" "fixes.txt line 1: no finding"

write_fixes 'mechanical\tshop/tax.sh:2 unclear name\nopen\tshop/tax.sh:3 refuses a blank rate\tfails safe\n'
expect_write written "an open finding with its reason is written" "$fixed_head" --rounds 1 --open 1 --pass "$pass_dir"
expect_write refused "an --open that differs from the open lines is refused" "$fixed_head" --rounds 1 --open 0 --pass "$pass_dir"
expect_said "it gives both counts" "fixes.txt has 1 open line(s), --open says 0"

write_fixes 'open\tshop/tax.sh:3 refuses a blank rate\tlater\n'
expect_write refused "an open finding with no listed reason is refused" "$fixed_head" --rounds 1 --open 1 --pass "$pass_dir"
expect_said "it lists the reasons" "fails safe, needs a decision or pre-existing"

# The pass folder must show every gate, verification and SCOPE:.
expect_write refused "no --pass is refused" "$fixed_head" --rounds 1 --open 0
expect_said "it asks for the pass folder" "--pass <dir> is required"
expect_write refused "a --pass folder that is not there is refused" "$fixed_head" --rounds 1 --open 0 --pass "$work_dir/no-such-pass"
expect_said "it names the folder" "no pass folder $work_dir/no-such-pass"

build_pass
rm "$pass_dir/round-1/verdicts/testing.txt"
expect_write refused "a listed gate with no block is refused" "$fixed_head" --rounds 1 --open 0 --pass "$pass_dir"
expect_said "it names the round and the gate" "round-1: no GATE: testing block"

build_pass
rm "$pass_dir/round-1/verdicts/verification.txt"
expect_write refused "a round with no verification block is refused" "$fixed_head" --rounds 1 --open 0 --pass "$pass_dir"
expect_said "it names the verification gate" "round-1: no GATE: verification block"

build_pass
printf 'GATE: naming\nBOXES:\n- [PASS] §N1: 0 hits\n' > "$pass_dir/round-1/verdicts/naming.txt"
expect_write refused "a block with no STATUS: is refused" "$fixed_head" --rounds 1 --open 0 --pass "$pass_dir"
expect_said "it names the missing status" "GATE: naming has no STATUS:"

build_pass
printf 'GATE: naming\nSTATUS: PASS\nFINDINGS:\n' > "$pass_dir/round-1/verdicts/naming.txt"
expect_write refused "a block with no boxes is refused" "$fixed_head" --rounds 1 --open 0 --pass "$pass_dir"
expect_said "it names the missing boxes" "GATE: naming has no BOXES: line with a box"

build_pass
printf 'GATE: naming\nSTATUS: PASS\nBOXES:\n- [PASS] §N1: 0 hits\n- [PASS] §N2:\n' > "$pass_dir/round-1/verdicts/naming.txt"
expect_write refused "a box with no evidence is refused" "$fixed_head" --rounds 1 --open 0 --pass "$pass_dir"
expect_said "it counts the bare box and names it" "GATE: naming has 1 box(es) with no verdict or no evidence: §N2"

# What a gate box needs is a verdict, an id and evidence; the layout a gate gave them in is not checked.
build_pass
printf 'GATE: naming\nSTATUS: PASS\nBOXES:\n- [PASS] §N1 Stored values, one row per state:\n\n  | State | Handler |\n  | --- | --- |\n  | missing | shop/total.sh:3 |\n\n- [PASS] §N2: 0 hits\nFINDINGS:\n- none\n' > "$pass_dir/round-1/verdicts/naming.txt"
expect_write written "a box whose evidence is a table after a blank line is no bad box" "$fixed_head" --rounds 1 --open 0 --pass "$pass_dir"

build_pass
printf 'GATE: naming\nSTATUS: PASS\nBOXES:\n- [PASS] §N1 Rows:\n| State | Handler |\n| --- | --- |\n| missing | shop/total.sh:3 |\n- [PASS] §N2: 0 hits\nFINDINGS:\n- none\n' > "$pass_dir/round-1/verdicts/naming.txt"
expect_write written "a box whose evidence is a table at the margin is no bad box" "$fixed_head" --rounds 1 --open 0 --pass "$pass_dir"

build_pass
printf 'GATE: naming\nSTATUS: PASS\nBOXES:\n  - [PASS] §N1 Bare\n  - [PASS] §N2: 0 hits\nFINDINGS:\n- none\n' > "$pass_dir/round-1/verdicts/naming.txt"
expect_write refused "an indented box under a bare box is the next box, not its evidence" "$fixed_head" --rounds 1 --open 0 --pass "$pass_dir"
expect_said "it names the bare one" "GATE: naming has 1 box(es) with no verdict or no evidence: §N1"

build_pass
printf 'GATE: naming\nSTATUS: PASS\nBOXES:\n- [PASS] §N1: 0 hits\n- [PASS] §N2 Bare\n  FINDINGS:\n  - none\n' > "$pass_dir/round-1/verdicts/naming.txt"
expect_write refused "a block header indented under a bare box is not its evidence" "$fixed_head" --rounds 1 --open 0 --pass "$pass_dir"
expect_said "it names the box with only a header under it" "GATE: naming has 1 box(es) with no verdict or no evidence: §N2"

build_pass
printf 'GATE: naming\nSTATUS: PASS\nBOXES:\n- [PASS] §N1 Every new name conforms.\n  - shop/total.sh order_total matches order_tax\n- [PASS] §N2: 0 hits\nFINDINGS:\n- none\n' > "$pass_dir/round-1/verdicts/naming.txt"
expect_write written "a box with no colon after its name and evidence under it is no bad box" "$fixed_head" --rounds 1 --open 0 --pass "$pass_dir"

build_pass
printf 'GATE: naming\nSTATUS: PASS\nBOXES:\n- [PASS] §N1: 0 hits\n- [PASS] §N2 Inline chains.\n\n- [PASS] §N3\nFINDINGS:\n- none\n' > "$pass_dir/round-1/verdicts/naming.txt"
expect_write refused "boxes with no colon and nothing under them are refused" "$fixed_head" --rounds 1 --open 0 --pass "$pass_dir"
expect_said "it names each one" "GATE: naming has 2 box(es) with no verdict or no evidence: §N2, §N3"

build_pass
printf 'GATE: naming\nSTATUS: PASS\nBOXES:\n- [PASS] §N1 Every new name conforms. Each unit, read:\n  - shop/total.sh order_total matches order_tax\n- [PASS] §N2: 0 hits\nFINDINGS:\n- none\n' > "$pass_dir/round-1/verdicts/naming.txt"
expect_write written "a box whose evidence is in bullets under it is no bad box" "$fixed_head" --rounds 1 --open 0 --pass "$pass_dir"

build_pass
printf 'GATE: naming\nSTATUS: PASS\nBOXES:\n- [PASS] §N1 Every new name conforms:\n- [PASS] §N2: 0 hits\nFINDINGS:\n  - none\n' > "$pass_dir/round-1/verdicts/naming.txt"
expect_write refused "a bare box followed by the next box, not bullets, is refused" "$fixed_head" --rounds 1 --open 0 --pass "$pass_dir"
expect_said "it counts the bare box before the next one" "GATE: naming has 1 box(es) with no verdict or no evidence"

build_pass
printf 'GATE: naming\nSTATUS: PASS\nBOXES:\n- [PASS] §N1 Every new name conforms:\n  - [shop/total.sh:3](shop/total.sh) order_total matches order_tax\n- [PASS] §N2: 0 hits\nFINDINGS:\n- none\n' > "$pass_dir/round-1/verdicts/naming.txt"
expect_write written "an evidence bullet that opens with a link counts" "$fixed_head" --rounds 1 --open 0 --pass "$pass_dir"

build_pass
printf 'GATE: naming\nSTATUS: PASS\nBOXES:\n- [MAYBE] §N1 Every new name conforms:\n  - shop/total.sh order_total matches order_tax\n- [PASS] §N2: 0 hits\nFINDINGS:\n- none\n' > "$pass_dir/round-1/verdicts/naming.txt"
expect_write refused "an unknown verdict with bullets under it is refused" "$fixed_head" --rounds 1 --open 0 --pass "$pass_dir"
expect_said "it counts the unknown verdict and names the box" "GATE: naming has 1 box(es) with no verdict or no evidence: §N1"

build_pass
edit_scope round-1 's/^- \[N\/A\] §G3: .*/- [N\/A] §G3:\
  - no linked issue, given under the box/'
expect_write refused "a SCOPE: box with its evidence only in bullets is refused" "$fixed_head" --rounds 1 --open 0 --pass "$pass_dir"
expect_said "it counts the SCOPE box and names it" "SCOPE: has 1 box(es) with no verdict or no evidence: §G3"

build_pass
printf 'GATE: naming\nSTATUS: PASS\nBOXES:\n- [PASS] §N1: 0 hits in shop/total.sh\n  and shop/tax.sh\n\n- [PASS] §N2: 0 hits\nFINDINGS:\n' > "$pass_dir/round-1/verdicts/naming.txt"
expect_write written "a box whose evidence wraps, or a blank line between boxes, is no bad box" "$fixed_head" --rounds 1 --open 0 --pass "$pass_dir"

build_pass
printf 'GATE: naming\nSTATUS: PASS\nBOXES:\n- [PASS] §N1: 0 hits\nFINDINGS:\n- none' > "$pass_dir/round-1/verdicts/a-naming.txt"
rm "$pass_dir/round-1/verdicts/naming.txt"
expect_write written "a block saved with no trailing newline keeps the next file's block" "$fixed_head" --rounds 1 --open 0 --pass "$pass_dir"

build_pass
build_gate_block naming >> "$pass_dir/round-1/verdicts/clarity.txt"
expect_write refused "two blocks for one gate are refused" "$fixed_head" --rounds 1 --open 0 --pass "$pass_dir"
expect_said "it names the repeated gate" "2 GATE: naming blocks"

build_pass
rm "$pass_dir/round-1/verdicts/scope.txt"
expect_write refused "a round with no SCOPE: block is refused" "$fixed_head" --rounds 1 --open 0 --pass "$pass_dir"
expect_said "it names the missing scope" "round-1: no SCOPE: block"

build_pass
edit_scope round-1 '/§G4/d'
expect_write refused "a SCOPE: block missing a box is refused" "$fixed_head" --rounds 1 --open 0 --pass "$pass_dir"
expect_said "it names the missing box" "SCOPE: has no §G4 box"

build_pass
edit_scope round-1 's/^- \[N\/A\] §G4: .*/- [N\/A] §G2: also/'
expect_write refused "a SCOPE: box marked twice is refused" "$fixed_head" --rounds 1 --open 0 --pass "$pass_dir"
expect_said "it names the twice-marked box" "marks §G2 2 times"

build_pass
edit_scope round-1 's/^- \[N\/A\] §G3: .*/- [N\/A] §G3:/'
expect_write refused "a SCOPE: box with no evidence is refused" "$fixed_head" --rounds 1 --open 0 --pass "$pass_dir"
expect_said "it counts the bare scope box" "SCOPE: has 1 box(es) with no verdict or no evidence"

build_pass
edit_scope round-1 's/§G1:/§G1 Stacking:/'
expect_write written "a SCOPE: box id with a title is that box" "$fixed_head" --rounds 1 --open 0 --pass "$pass_dir"

build_pass
# An id with one more digit, built so the rules lint doesn't read it as a citation.
extra_digit=0
edit_scope round-1 "s/§G1:/§G1${extra_digit}:/"
expect_write refused "a longer SCOPE: id is another box" "$fixed_head" --rounds 1 --open 0 --pass "$pass_dir"
expect_said "it names the missing box" "SCOPE: has no §G1 box"

build_pass
rm "$pass_dir/round-1/verdicts/"*
expect_write refused "a review with no verdict blocks is refused" "$fixed_head" --rounds 1 --open 0 --pass "$pass_dir"
expect_said "it names the empty verdicts folder" "round-1: no verdict blocks"

build_pass
rm "$pass_dir/round-1/meta.env"
expect_write refused "a review with no meta.env is refused" "$fixed_head" --rounds 1 --open 0 --pass "$pass_dir"
expect_said "it names the missing file" "round-1: no meta.env"

build_pass
printf 'HEAD_SHA=%s\n' "$(make_fake_sha d)" > "$pass_dir/round-1/meta.env"
expect_write refused "a review whose head the clone lacks is refused" "$fixed_head" --rounds 1 --open 0 --pass "$pass_dir"
expect_said "it names the review" "round-1: meta.env names no HEAD_SHA this clone has"

build_pass
expect_write refused "a commit the clone lacks is refused" "$(make_fake_sha c)" --rounds 1 --open 0 --pass "$pass_dir"
expect_said "it names the commit" "is not in this clone"

# The gates come from the tree each review read, not from today's checkout.
build_pass
mkdir -p "$repo/.claude"
printf -- '- [ ] §X1 A house rule.\n' > "$repo/.claude/review-conventions.md"
expect_write written "a conventions file only in today's checkout adds no gate to the reviews" "$fixed_head" --rounds 1 --open 0 --pass "$pass_dir"

build_repo conventions
build_pass
rm "$pass_dir/round-1/verdicts/project-conventions.txt"
expect_write refused "conventions the repo had at a review's head need their gate" "$fixed_head" --rounds 1 --open 0 --pass "$pass_dir"
expect_said "it names the conventions gate" "round-1: no GATE: project-conventions block"

# The receipt is for the history round 1 reviewed.
build_repo
build_pass
run_git checkout -q -b rebased "$base"
printf 'echo rebased\n' >> "$repo/shop/total.sh"
expect_write refused "a commit that does not descend from round 1's head is refused" "$(commit_all "rebased")" --rounds 1 --open 0 --pass "$pass_dir"
expect_said "it says round 1 reviewed another diff" "does not descend from round 1's head"

# Fixes past round 1's diff, or bringing a risk it didn't have, need the user's words.
build_repo widen
build_pass
expect_write refused "fixes adding a file outside round 1's diff are refused" "$fixed_head" --rounds 1 --open 0 --pass "$pass_dir"
expect_said "it lists the file" "outside round 1: shop/ship.sh"
expect_write refused "an empty approval is refused" "$fixed_head" --rounds 1 --open 0 --pass "$pass_dir" --scope-approved ""
expect_write written "the user's words let it through" "$fixed_head" --rounds 1 --open 0 --pass "$pass_dir" --scope-approved "yes, add the shipping script"
expect_contains "the receipt keeps the user's words" "scope_approved=yes, add the shipping script" "$(bash "$scripts/ready-receipt.sh" check "$fixed_head")"

build_repo sensitive
build_pass
expect_write written "a fix to a payments change round 1 already had needs no approval" "$fixed_head" --rounds 1 --open 0 --pass "$pass_dir"

build_repo deletes-data
build_pass
expect_write refused "fixes bringing a risk round 1 didn't have are refused" "$fixed_head" --rounds 1 --open 0 --pass "$pass_dir"
expect_said "it names the new kind of risk" "new risk: deletes data"
expect_write written "the user's words let a new risk through" "$fixed_head" --rounds 1 --open 0 --pass "$pass_dir" --scope-approved "go ahead"

# A file round 1 touched, quoted the way gather-review.sh lists it, is inside round 1's diff.
build_repo accented
build_pass
expect_write written "a fix to a non-ASCII-named round-1 file needs no approval" "$fixed_head" --rounds 1 --open 0 --pass "$pass_dir"

# Real gate replies, as a pass saved them: one bare with nested evidence, one
# fenced. They stand in for those gates' blocks; a change in a gate's format
# fails here first.
build_repo
build_pass
cp "$tests_dir/fixtures/ready-receipt/real-verdicts/"*.txt "$pass_dir/round-1/verdicts/"
expect_write written "a pass folder with real gate replies is written" "$round_one" --rounds 1 --open 0 --pass "$pass_dir"
summary=$(cat "$tests_dir/fixtures/ready-receipt/real-verdicts/"*.txt | grep -cE '^GATE:')
expect_eq "each real reply holds one block" 2 "$summary"

# The gates come from the change git holds, not from the folder's saved diff.
build_repo ruby
build_pass
: > "$pass_dir/round-1/review.diff"
: > "$pass_dir/round-1/changed-files.txt"
rm "$pass_dir/round-1/verdicts/"*
save_verdicts round-1 scope
expect_write refused "a folder whose saved diff leaves a file out still needs that file's gate" "$round_one" --rounds 1 --open 0 --pass "$pass_dir"
expect_said "it names the gate the real change needs" "round-1: no GATE: rails block"

build_pass
printf 'HEAD_SHA=%s\n' "$round_one" > "$pass_dir/round-1/meta.env"
expect_write refused "a review with no BASE is refused" "$round_one" --rounds 1 --open 0 --pass "$pass_dir"
expect_said "it names the missing base" "round-1: meta.env names no BASE this clone has"

# The other receipts (fixes after the pass go --after, with no round: §H5), the flags and the usage.
build_repo
build_pass
expect_write written "a pass to follow is written" "$fixed_head" --rounds 1 --open 0 --pass "$pass_dir"
pass_head=$fixed_head
printf 'echo picked\n' >> "$repo/shop/total.sh"
picked_fix=$(commit_all "a fix the user picked")
expect_write refused "--after refuses a pass with no receipt" "$picked_fix" --after "$(make_fake_sha c)"
expect_write written "--after follows a pass with a receipt" "$picked_fix" --after "$pass_head"
expect_write refused "--after refuses a commit that does not descend from the pass" "$base" --after "$pass_head"
expect_said "it says why" "does not descend from $pass_head"
expect_write refused "an unknown size is refused" "$fixed_head" --rounds 1 --open 0 --size tiny --pass "$pass_dir"
expect_write refused "an --open that is no count is refused" "$fixed_head" --rounds 1 --open some --pass "$pass_dir"
expect_said "it asks for a count" "--open is a count"
expect_write written "--checklist needs no pass folder" "$(make_fake_sha e)" --checklist
expect_contains "--checklist records the walk" "checklist=walked" "$(bash "$scripts/ready-receipt.sh" check "$(make_fake_sha e)")"
# A checklist with `ledger: true` needs the look-back's ledger, and it must pass.
build_repo
mkdir -p "$repo/.claude"
printf -- '---\nledger: true\n---\n# Hand-off checklist\n' > "$repo/.claude/hand-off-checklist.md"
printf -- '- [ ] §X2 Totals print cents.\n' > "$repo/RULES.md"
lesson_head=$(commit_all "lesson")
run_git update-ref refs/remotes/origin/main "$base"
run_git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
expect_write refused "a checklist asking for the ledger refuses a receipt without one" "$lesson_head" --checklist
expect_said "it asks for the ledger" "pass --ledger <dir>"
ledger_dir=$work_dir/ledger-$RANDOM
mkdir -p "$ledger_dir"
printf 'F1\ttyped\tprint cents\nF2\ttyped\tgo ahead\n' > "$ledger_dir/feedback.tsv"
printf 'F1\tlesson\t§X2\n' > "$ledger_dir/ledger.tsv"
expect_write refused "a ledger with an item left out is refused" "$lesson_head" --checklist --ledger "$ledger_dir"
expect_said "it names the item" "F2: no verdict in the ledger"
printf 'F1\tlesson\t§X3\nF2\tnot-feedback\tthe go-ahead\n' > "$ledger_dir/ledger.tsv"
expect_write refused "a lesson the PR doesn't add is refused" "$lesson_head" --checklist --ledger "$ledger_dir"
printf -- '+- **X3.** From the sibling repo\n' > "$ledger_dir/sibling.diff"
expect_write written "a lesson added by a sibling repo's diff beside the ledger counts" "$lesson_head" --checklist --ledger "$ledger_dir"
rm "$ledger_dir/sibling.diff"
printf 'F1\tlesson\t§X2\nF2\tnot-feedback\tthe go-ahead\n' > "$ledger_dir/ledger.tsv"
expect_write written "a complete ledger whose lessons the PR adds is written" "$lesson_head" --checklist --ledger "$ledger_dir"
# A covered rule must have existed before this PR: the base's rules, or a sibling repo's folder.
printf 'F1\tcovered\t§X2\tadded here, not missed\nF2\tnot-feedback\tthe go-ahead\n' > "$ledger_dir/ledger.tsv"
expect_write refused "a rule this PR adds is not covered" "$lesson_head" --checklist --ledger "$ledger_dir"
expect_said "it says the rule wasn't there" "F1: covered by §X2, which no rule file had"
mkdir -p "$ledger_dir/sibling-rules"
printf -- '- **X2.** In the sibling repo\n' > "$ledger_dir/sibling-rules/rules.md"
expect_write written "a rule from a sibling repo's rules folder counts as covered" "$lesson_head" --checklist --ledger "$ledger_dir"
rm -r "$ledger_dir/sibling-rules"
printf 'F1\tlesson\t§X2\nF2\tnot-feedback\tthe go-ahead\n' > "$ledger_dir/ledger.tsv"
expect_write refused "--ledger without --checklist is a usage error" "$lesson_head" --after "$lesson_head" --ledger "$ledger_dir"
expect_said "it says where --ledger goes" "--ledger goes with --checklist"
expect_write refused "--ledger with no folder is a usage error" "$lesson_head" --checklist --ledger
orphan=$(run_git commit-tree "$(run_git write-tree)" -m orphan)
expect_write refused "a commit with no history in common with the default branch is refused" "$orphan" --checklist --ledger "$ledger_dir"
expect_said "it says so" "shares no commit with origin/main"
run_git symbolic-ref --delete refs/remotes/origin/HEAD
run_git checkout -q --detach
run_git branch -q -f main "$base"
expect_write written "with no origin/HEAD, the default branch is main" "$lesson_head" --checklist --ledger "$ledger_dir"
rm -f "$ledger_dir/ledger.tsv"
expect_write refused "a ledger folder without the ledger is refused" "$lesson_head" --checklist --ledger "$ledger_dir"
expect_said "it names both files" "$ledger_dir needs feedback.tsv and ledger.tsv"
printf 'F1\tlesson\t§X2\n' > "$ledger_dir/ledger.tsv"
rm -f "$ledger_dir/feedback.tsv"
expect_write refused "a ledger folder without the feedback list is refused" "$lesson_head" --checklist --ledger "$ledger_dir"
expect_said "it names both files" "$ledger_dir needs feedback.tsv and ledger.tsv"

# Only `ledger: true` in the checklist's front matter asks for the ledger.
printf -- '---\nname: kit\n---\n# Hand-off checklist\n' > "$repo/.claude/hand-off-checklist.md"
expect_write written "front matter without ledger: true asks for no ledger" "$lesson_head" --checklist
printf -- '---\nname: kit\n---\nledger: true\n' > "$repo/.claude/hand-off-checklist.md"
expect_write written "ledger: true in the body, not the front matter, asks for no ledger" "$lesson_head" --checklist
rm "$repo/.claude/hand-off-checklist.md"
expect_write written "a repo with no checklist asks for no ledger" "$lesson_head" --checklist
expect_eq "and prints nothing else" "receipt written: $KC_READY_DIR/$lesson_head" "$last_output"

expect_write refused "--after refuses a commit with only the checklist's receipt" "$(make_fake_sha 9)" --after "$(make_fake_sha e)"
if bash "$scripts/ready-receipt.sh" check "$(make_fake_sha e)" --pass >/dev/null; then
  record "check --pass refuses a checklist receipt" fail "it passed"
else
  record "check --pass refuses a checklist receipt" ok
fi
expect_contains "check --pass prints a pass receipt" "rounds=1" "$(bash "$scripts/ready-receipt.sh" check "$written_pass_head" --pass)"
check_status=0
bash "$scripts/ready-receipt.sh" check "$(make_fake_sha e)" --other >/dev/null 2>&1 || check_status=$?
expect_eq "check with anything but --pass after the SHA prints the usage" 2 "$check_status"
if bash "$scripts/ready-receipt.sh" check "$(make_fake_sha b)" >/dev/null; then
  record "check fails for a commit without a receipt" fail "check passed"
else
  record "check fails for a commit without a receipt" ok
fi
usage_text=$(bash "$scripts/ready-receipt.sh" 2>&1 || true)
expect_contains "no arguments print the usage" "ready-receipt.sh write <sha> --rounds 1 --open <n> --pass <dir>" "$usage_text"
expect_eq "the usage has the header's lines without their comment marks" 0 "$(printf '%s\n' "$usage_text" | grep -c '^#' || true)"

finish
