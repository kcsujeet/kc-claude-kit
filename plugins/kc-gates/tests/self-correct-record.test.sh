#!/usr/bin/env bash
# Tests scripts/self-correct-record.sh: the record is keyed on the content's tree hash (never a
# commit), is refused without verdict blocks, without fixes.txt after round 1 or with an open finding,
# and when the last round read other content; it says clean=yes only when nothing is open and the last
# round found nothing; a later commit of the same content still finds it, changed content does not.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
scripts="$(dirname "$tests_dir")/scripts"
export KC_SELF_CORRECT_DIR="$work_dir/records"

repo="$work_dir/repo"
git init -q -b main "$repo"
printf 'one\n' > "$repo/a.txt"
run_git_in "$repo" add -A
run_git_in "$repo" commit -q -m base
printf 'two\n' >> "$repo/a.txt"
printf 'new\n' > "$repo/b.txt"
tree=$(cd "$repo" && bash "$scripts/tree-hash.sh")

# Builds pass folder <name> with <rounds> rounds, each with one gate block listing <findings> findings.
make_pass() {
  local name=$1 rounds=$2 findings=$3 round
  pass="$work_dir/$name"
  for ((round = 1; round <= rounds; round++)); do
    mkdir -p "$pass/round-$round/verdicts"
    printf 'GATE: naming\nSTATUS: PASS\nBOXES:\n- [PASS] §X1: swept\nFINDINGS:\n' > "$pass/round-$round/verdicts/naming.txt"
    printf 'HEAD_SHA=%s\nTREE=%s\n' "$(git -C "$repo" rev-parse HEAD)" "$tree" > "$pass/round-$round/meta.env"
  done
  if [ "$findings" -gt 0 ]; then
    printf -- '- b.txt:1 a finding\n' >> "$pass/round-$rounds/verdicts/naming.txt"
  fi
}
write_record() { (cd "$repo" && bash "$scripts/self-correct-record.sh" write "$@" 2>&1); }
record_status() { (cd "$repo" && bash "$scripts/self-correct-record.sh" "$@" > /dev/null 2>&1) && echo yes || echo no; }

make_pass clean 1 0
output=$(write_record --rounds 1 --open 0 --size full --pass "$pass") && written=yes || written=no
expect_eq "a pass that found nothing is recorded" yes "$written"
expect_contains "it says clean" "clean=yes" "$output"
expect_eq "it is keyed on the working tree's content" yes "$([ -f "$KC_SELF_CORRECT_DIR/$tree" ] && echo yes || echo no)"
expect_contains "the record names the tree" "tree=$tree" "$(cd "$repo" && bash "$scripts/self-correct-record.sh" check "$tree")"
expect_contains "and the pass folder and size" "size=full" "$(cd "$repo" && bash "$scripts/self-correct-record.sh" check "$tree")"
expect_eq "check --clean passes for a clean record" yes "$(record_status check "$tree" --clean)"

# Committing the same content, then amending it, keeps the tree and so the record.
run_git_in "$repo" add -A
run_git_in "$repo" commit -q -m work
run_git_in "$repo" commit -q --amend -m "work, reworded"
expect_eq "the commit's tree is the recorded content" "$tree" "$(git -C "$repo" rev-parse 'HEAD^{tree}')"
expect_eq "a record made before the commit is found for it" yes "$(record_status check "$(git -C "$repo" rev-parse 'HEAD^{tree}')")"

printf 'three\n' >> "$repo/a.txt"
changed_tree=$(cd "$repo" && bash "$scripts/tree-hash.sh")
expect_eq "changed content has no record" no "$(record_status check "$changed_tree")"
output=$(write_record --rounds 1 --open 0 --pass "$pass") && written=yes || written=no
expect_eq "content that changed after the last round is refused" no "$written"
expect_contains "it says the delta needs a round" "review the delta" "$output"
git -C "$repo" checkout -q a.txt

make_pass findings 1 1
output=$(write_record --rounds 1 --open 0 --pass "$pass") && written=yes || written=no
expect_eq "a last round with findings and nothing open is recorded" yes "$written"
expect_contains "but not clean" "clean=no" "$output"
expect_eq "check --clean refuses an unclean record" no "$(record_status check "$tree" --clean)"
output=$(write_record --rounds 1 --open 1 --pass "$pass") && written=yes || written=no
expect_eq "an open finding without fixes.txt is refused" no "$written"
expect_contains "it asks for fixes.txt" "fixes.txt" "$output"
printf 'open\tb.txt:1 a finding\tneeds a decision\n' > "$pass/fixes.txt"
output=$(write_record --rounds 1 --open 1 --pass "$pass") && written=yes || written=no
expect_eq "with fixes.txt it is recorded" yes "$written"
expect_contains "an open finding is never clean" "clean=no" "$output"

make_pass two-rounds 2 0
output=$(write_record --rounds 2 --open 0 --pass "$pass") && written=yes || written=no
expect_eq "rounds after the first need fixes.txt" no "$written"
printf 'mechanical\tb.txt:1 rename\n' > "$pass/fixes.txt"
output=$(write_record --rounds 2 --open 0 --pass "$pass") && written=yes || written=no
expect_eq "two rounds and fixes.txt are recorded" yes "$written"
expect_contains "the last round found nothing: clean" "clean=yes" "$output"

make_pass broken-use 2 0
printf 'mechanical\tb.txt:1 rename\n' > "$pass/fixes.txt"
printf '  b.txt:3: use\tbreaks\n' > "$pass/round-2/uses-verdicts.txt"
output=$(write_record --rounds 2 --open 0 --pass "$pass")
expect_contains "a use marked breaks keeps the record unclean" "clean=no" "$output"

make_pass four 3 0
output=$(write_record --rounds 4 --open 0 --pass "$pass") && written=yes || written=no
expect_eq "a fourth round is refused" no "$written"
mkdir -p "$work_dir/no-verdicts/round-1/verdicts"
output=$(write_record --rounds 1 --open 0 --pass "$work_dir/no-verdicts") && written=yes || written=no
expect_eq "a round with no verdict blocks is refused" no "$written"
expect_contains "it names the round" "round-1: no verdict blocks" "$output"
output=$(write_record --rounds 1 --open x --pass "$pass") && written=yes || written=no
expect_eq "--open must be a count" no "$written"
expect_eq "check with no record for a tree" no "$(record_status check "$(printf 'a%.0s' {1..40})")"
expect_eq "check needs a tree hash" no "$(record_status check not-a-hash)"
expect_contains "help prints the usage" "self-correct-record.sh write" "$(bash "$scripts/self-correct-record.sh" help)"

finish
