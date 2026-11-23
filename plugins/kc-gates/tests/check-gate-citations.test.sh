#!/usr/bin/env bash
# Tests scripts/check-gate-citations.sh: a citation (path:line@sha, path:Lline@sha) must carry a prefix
# of the head sha and name a line that exists in that file at the head.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
check="$(dirname "$tests_dir")/scripts/check-gate-citations.sh"

repo=$work_dir/repo
mkdir -p "$repo/src"
git -C "$repo" init -q
git -C "$repo" config user.email test@example.com
git -C "$repo" config user.name Test
printf 'a\nb\nc\n' > "$repo/src/cart.ts"
git -C "$repo" add -A && git -C "$repo" commit -q -m first
old_sha=$(git -C "$repo" rev-parse HEAD)
printf 'a\nb\nc\nd\n' > "$repo/src/cart.ts"
git -C "$repo" add -A && git -C "$repo" commit -q -m second
head_sha=$(git -C "$repo" rev-parse HEAD)
short=${head_sha:0:7}

# Runs the check on a gate output holding <text>; prints its output, or "clean".
result() {
  local status=0 output
  printf '%s\n' "$1" > "$work_dir/gate.txt"
  output=$(bash "$check" "$head_sha" "$repo" "$work_dir/gate.txt" 2>&1) || status=$?
  if [ "$status" -eq 0 ]; then echo clean; else printf '%s' "$output"; fi
}

expect_eq "§V12: a citation with the head's short sha and a real line is clean" clean "$(result "- 🟠 src/cart.ts:4@$short: total skips the last item")"
expect_eq "the L form is clean too" clean "$(result "- src/cart.ts:L3@$short: ok")"
expect_eq "the full head sha is clean" clean "$(result "- src/cart.ts:1@$head_sha: ok")"
expect_eq "text with no citation is clean" clean "$(result "GATE: naming STATUS: PASS")"
expect_contains "a citation at an older sha is named" "src/cart.ts:3@${old_sha:0:7}: sha ${old_sha:0:7} is not the head" "$(result "- src/cart.ts:3@${old_sha:0:7}: stale")"
expect_contains "a line past the end of the file at the head is named" "line 9 is not in src/cart.ts at the head (it has 4)" "$(result "- src/cart.ts:L9@$short: no such line")"
expect_contains "a file that is not at the head is named" "src/gone.ts does not exist at the head" "$(result "- src/gone.ts:1@$short: gone")"
expect_contains "line 0 is not a line" "line 0 is not in" "$(result "- src/cart.ts:0@$short: zero")"
mixed=$(result "- src/cart.ts:2@$short: ok
- src/cart.ts:2@${old_sha:0:7}: stale")
expect_contains "a bad citation among good ones is still reported" "is not the head" "$mixed"
status=0
printf -- '- src/cart.ts:2@%s\n' "${old_sha:0:7}" > "$work_dir/gate.txt"
bash "$check" "$head_sha" "$repo" "$work_dir/gate.txt" > /dev/null 2>&1 || status=$?
expect_eq "a bad citation exits 1" 1 "$status"
status=0
bash "$check" "$head_sha" > /dev/null 2>&1 || status=$?
expect_eq "missing arguments exit 2" 2 "$status"

finish
