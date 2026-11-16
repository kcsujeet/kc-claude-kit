#!/usr/bin/env bash
# Tests scripts/check-budget-change.sh in a throwaway repo: unchanged and lowered budgets pass, a
# raised or removed one fails unless the description has a `budget-raised:` line with a real reason
# (an empty or placeholder reason fails), and a change that leaves ci.yml alone passes.
set -euo pipefail

script="$(cd "$(dirname "$0")/.." && pwd)/check-budget-change.sh"
repo=$(mktemp -d)
trap 'rm -rf "$repo"' EXIT
passes=0
failures=0

pass() { echo "ok   $1"; passes=$((passes + 1)); }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }

last_output=""
expect_verdict() {
  local expectation=$1 label=$2 body=${3:-} actual=pass
  if [ -n "$body" ]; then
    printf '%s\n' "$body" > "$repo/.body"
    last_output=$(cd "$repo" && bash "$script" main --description-file .body 2>&1) || actual=fail
  else
    last_output=$(cd "$repo" && bash "$script" main 2>&1) || actual=fail
  fi
  if [ "$actual" = "$expectation" ]; then pass "$label"; else fail "$label (expected $expectation, got $actual)"; fi
}

expect_output() {
  local label=$1 expected_text=$2
  case "$last_output" in
    *"$expected_text"*) pass "$label" ;;
    *) fail "$label (no \"$expected_text\" in: $last_output)" ;;
  esac
}

write_ci() {
  mkdir -p "$repo/.github/workflows"
  cat > "$repo/.github/workflows/ci.yml" <<YAML
      # (--budget-rules, --max-description) mentioned in a comment: never a flag line
      - name: Always-on size report
        run: bash scripts/check-always-on.sh --budget-rules $1 --max-description $2 --budget-hooks 1000
YAML
}

# Resets the repo to main with ci.yml at 10000 / 320, then branches.
start_branch() {
  git -C "$repo" checkout -q main
  git -C "$repo" branch -q -D work 2>/dev/null || true
  git -C "$repo" checkout -q -b work
}

commit_change() {
  git -C "$repo" add -A
  git -C "$repo" -c user.name=t -c user.email=t@example.test commit -q --allow-empty -m "$1"
}

git -C "$repo" init -q -b main
write_ci 10000 320
echo base > "$repo/README.md"
commit_change base

start_branch
expect_verdict pass "no ci.yml change passes"

start_branch
echo more >> "$repo/README.md"
commit_change "readme only"
expect_verdict pass "a change that leaves ci.yml alone passes"

start_branch
write_ci 10000 320
commit_change "same"
expect_verdict pass "unchanged budgets pass"

start_branch
write_ci 9000 300
commit_change "lower"
expect_verdict pass "lowered budgets pass"
expect_output "lowered flag is printed old to new" "lowered  --budget-rules 10000 -> 9000"

start_branch
write_ci 12000 320
commit_change "raise"
expect_verdict fail "raised without a reason line fails"
expect_output "raised flag is printed old to new" "raised   --budget-rules 10000 -> 12000"
expect_verdict pass "raised with a budget-raised line passes" "budget-raised: new skill needs the room"
expect_verdict fail "placeholder reason fails" "budget-raised: <why>"
expect_verdict fail "empty reason fails" "budget-raised:   "
expect_verdict fail "a description with no such line fails" "just a normal description"

start_branch
cat > "$repo/.github/workflows/ci.yml" <<'YAML'
      - name: Always-on size report
        run: bash scripts/check-always-on.sh --budget-rules 10000 --budget-hooks 1000
YAML
commit_change "remove a flag"
expect_verdict fail "a removed flag fails"
expect_output "removed flag is printed" "removed  --max-description 320 -> (gone)"
expect_verdict pass "a removed flag passes with a reason" "budget-raised: dropped the cap, see PR"

echo
echo "$passes passed, $failures failed"
[ "$failures" -eq 0 ]
