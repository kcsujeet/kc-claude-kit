#!/usr/bin/env bash
# Tests scripts/review-tally.sh: add records one line per PR (a repeat replaces it), report sums
# per month, and bad counts are refused.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
script="$(dirname "$tests_dir")/scripts/review-tally.sh"
export KC_READY_DIR="$work_dir/ready"

expect_eq "report with nothing tallied" "No reviews tallied yet." "$(bash "$script" report)"

bash "$script" add https://example.com/shop/pull/1 1 2 0
bash "$script" add https://example.com/shop/pull/2 0 1 1
bash "$script" add https://example.com/shop/pull/1 0 2 0
expect_eq "a repeat add replaces the PR's line" 2 "$(wc -l < "$KC_READY_DIR/tally.tsv" | tr -d ' ')"

month=$(date +%Y-%m)
expect_eq "report sums the month" "$(printf '%s\t2\t0\t3\t1' "$month")" "$(bash "$script" report | tail -1)"

status=0
bash "$script" add https://example.com/shop/pull/3 one 0 0 2>/dev/null || status=$?
expect_eq "a non-numeric count is refused" 2 "$status"

# --- reverts: a real history with each way a PR gets merged and reverted ------------------------
repo="$work_dir/shop"
git init -q -b main "$repo"
# Commits a change to a file named after the message, the way a PR changes files.
commit() {
  printf '%s\n' "$2" >> "$repo/$(printf '%s' "$2" | tr -cd '[:lower:]' | cut -c1-20).txt"
  git -C "$repo" add -A
  git -C "$repo" -c user.email=dev@example.com -c user.name=Dev commit -q "$@"
}
commit -m "Initial commit"
commit -m "Add coupon codes (#12)"
squash_sha=$(git -C "$repo" rev-parse HEAD)
commit -m "Show stock badges (#14)"
git -C "$repo" checkout -q -b feature/shipping
commit -m "Free shipping for members"
git -C "$repo" checkout -q main
git -C "$repo" -c user.email=dev@example.com -c user.name=Dev merge -q --no-ff feature/shipping -m "Merge pull request #13 from shop/feature/shipping"
merge_sha=$(git -C "$repo" rev-parse HEAD)
commit -m "Tweak README wording"
local_sha=$(git -C "$repo" rev-parse HEAD)
commit -m "PLA-7: Skip unchanged writes on save (#20)"
# GitHub's Revert button: a revert PR, squash-merged with only its title and number.
printf 'undo\n' >> "$repo/plaskipunchangedwrite.txt"
git -C "$repo" add -A
git -C "$repo" -c user.email=dev@example.com -c user.name=Dev commit -q -m 'Revert "PLA-7: Skip unchanged writes on save" (#21)'
git -C "$repo" -c user.email=dev@example.com -c user.name=Dev revert --no-edit "$squash_sha" >/dev/null
git -C "$repo" -c user.email=dev@example.com -c user.name=Dev revert --no-edit -m 1 "$merge_sha" >/dev/null
git -C "$repo" -c user.email=dev@example.com -c user.name=Dev revert --no-edit "$local_sha" >/dev/null
reverted=$(bash "$script" reverts "$repo")
expect_eq "reverts: one line per reverted PR, a local commit's revert left out" 3 "$(printf '%s\n' "$reverted" | grep -c .)"
expect_contains "reverts: a squash-merged PR is found by its (#n)" "#12" "$reverted"
expect_contains "reverts: a GitHub revert PR names the PR it reverts, not itself" "#20" "$reverted"
expect_eq "reverts: the revert PR itself is not listed as reverted" 0 "$(printf '%s\\n' "$reverted" | grep -c '#21' || true)"
expect_contains "reverts: a merge-commit PR is found by its merge subject" "#13" "$reverted"
expect_eq "reverts: a PR nobody reverted is not listed" 0 "$(printf '%s\n' "$reverted" | grep -c '#14' || true)"

finish
