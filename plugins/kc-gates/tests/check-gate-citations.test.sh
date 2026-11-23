#!/usr/bin/env bash
# Tests scripts/check-gate-citations.sh: a citation (path:line@sha, path:Lline@sha) must carry a prefix
# of the head sha and name a line that exists in that file at the head.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
citations_script="$(dirname "$tests_dir")/scripts/check-gate-citations.sh"
short_sha_chars=7

repo=$work_dir/repo
mkdir -p "$repo/src"
git -C "$repo" init -q
git -C "$repo" config user.email test@example.com
git -C "$repo" config user.name Test
printf 'a\nb\nc\n' > "$repo/src/cart.ts"
git -C "$repo" add -A && git -C "$repo" commit -q -m first
old_sha=$(git -C "$repo" rev-parse HEAD)
old_short=${old_sha:0:short_sha_chars}
printf 'a\nb\nc\nd\n' > "$repo/src/cart.ts"
git -C "$repo" add -A && git -C "$repo" commit -q -m second
head_sha=$(git -C "$repo" rev-parse HEAD)
short=${head_sha:0:short_sha_chars}

# Runs the check on a gate output holding <text>; prints its output, or "clean".
run_citation_check() {
  local status=0 output
  printf '%s\n' "$1" > "$work_dir/gate.txt"
  output=$(bash "$citations_script" "$head_sha" "$repo" "$work_dir/gate.txt" 2>&1) || status=$?
  if [ "$status" -eq 0 ]; then echo clean; else printf '%s' "$output"; fi
}

expect_eq "§V12: a citation with the head's short sha and a real line is clean" clean "$(run_citation_check "- 🟠 src/cart.ts:4@$short: total skips the last item")"
expect_eq "the L form is clean too" clean "$(run_citation_check "- src/cart.ts:L3@$short: ok")"
expect_eq "the full head sha is clean" clean "$(run_citation_check "- src/cart.ts:1@$head_sha: ok")"
expect_eq "text with no citation is clean" clean "$(run_citation_check "GATE: naming STATUS: PASS")"
expect_contains "a citation at an older sha is named" "src/cart.ts:3@$old_short: sha $old_short is not the head" "$(run_citation_check "- src/cart.ts:3@$old_short: stale")"
expect_contains "a line past the end of the file at the head is named" "line 9 is not in src/cart.ts at the head (it has 4)" "$(run_citation_check "- src/cart.ts:L9@$short: no such line")"
expect_contains "a file that is not at the head is named" "src/gone.ts does not exist at the head" "$(run_citation_check "- src/gone.ts:1@$short: gone")"
expect_contains "line 0 is not a line" "line 0 is not in" "$(run_citation_check "- src/cart.ts:0@$short: zero")"
mixed=$(run_citation_check "- src/cart.ts:2@$short: ok
- src/cart.ts:2@$old_short: stale")
expect_contains "a bad citation among good ones is still reported" "is not the head" "$mixed"
# No citation at all: the loop reads no empty one, so nothing is checked and nothing is printed.
expect_eq "text with no citation prints nothing at all, on stderr too" "" "$(printf 'GATE: naming\n' > "$work_dir/none.txt"; bash "$citations_script" "$head_sha" "$repo" "$work_dir/none.txt" 2>&1)"

status=0
printf -- '- src/cart.ts:2@%s\n' "$old_short" > "$work_dir/gate.txt"
bash "$citations_script" "$head_sha" "$repo" "$work_dir/gate.txt" > /dev/null 2>&1 || status=$?
expect_eq "a bad citation exits 1" 1 "$status"
status=0
bash "$citations_script" "$head_sha" > /dev/null 2>&1 || status=$?
expect_eq "missing arguments exit 2" 2 "$status"

# A file whose last line has no newline still has that line.
printf 'a\nb' > "$repo/src/tail.ts"
git -C "$repo" add -A && git -C "$repo" commit -q -m third
head_sha=$(git -C "$repo" rev-parse HEAD)
short=${head_sha:0:short_sha_chars}
expect_eq "a citation of the last line of a file with no final newline is clean" clean "$(run_citation_check "- src/tail.ts:2@$short: last line")"

status=0
bash "$citations_script" 0000000000000000000000000000000000000000 "$repo" "$work_dir/gate.txt" > /dev/null 2>&1 || status=$?
expect_eq "a head that is not a commit exits 2" 2 "$status"
status=0
bash "$citations_script" "$head_sha" "$repo" "$work_dir/missing.txt" > /dev/null 2>&1 || status=$?
expect_eq "an unreadable gate output exits 2" 2 "$status"

finish
