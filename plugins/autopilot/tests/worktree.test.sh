#!/usr/bin/env bash
# Tests scripts/worktree.sh against a throwaway repo.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
script="$(dirname "$tests_dir")/scripts/worktree.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
passes=0
failures=0
pass() { echo "ok   $1"; passes=$((passes + 1)); }
fail() { echo "FAIL $1"; echo "     $2"; failures=$((failures + 1)); }
# check LABEL DETAIL COMMAND… — passes when COMMAND succeeds.
check() {
  local label=$1 detail=$2
  shift 2
  if "$@"; then pass "$label"; else fail "$label" "$detail"; fi
}

repo="$tmp/repo"
git init -q -b main "$repo"
git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
mkdir -p "$repo/.claude"
echo '{"checks":["true"]}' > "$repo/.claude/autopilot.json"

status=0
out=$(bash "$script" create "$repo" r1 U1 main 2>"$tmp/err") || status=$?
[ "$status" = 0 ] || fail "create exits 0" "status $status: $(cat "$tmp/err")"
path=$(printf '%s' "$out" | jq -r .path 2>/dev/null || true)
branch=$(printf '%s' "$out" | jq -r .branch 2>/dev/null || true)
check "branch name" "$branch" [ "$branch" = autopilot/r1/U1 ]
check "worktree path" "$path" [ "$path" = "$repo/.claude/worktrees/autopilot-r1-U1" ]
head=$(git -C "$path" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
check "worktree on branch" "HEAD is '$head'" [ "$head" = autopilot/r1/U1 ]
check "config copied" "missing" [ -f "$path/.claude/autopilot.json" ]

again=$(bash "$script" create "$repo" r1 U1 main 2>/dev/null || true)
if [ -n "$out" ] && [ "$again" = "$out" ]; then
  pass "create is idempotent"
else
  fail "create is idempotent" "$again"
fi

if [ -d "$path" ]; then
  echo dirty > "$path/new-file.txt"
  if bash "$script" remove "$repo" "$path" 2>/dev/null; then
    fail "refuses dirty remove" "removed"
  else
    pass "refuses dirty remove"
  fi
  rm "$path/new-file.txt"
  status=0
  bash "$script" remove "$repo" "$path" 2>"$tmp/err" || status=$?
  [ "$status" = 0 ] || fail "clean remove exits 0" "status $status: $(cat "$tmp/err")"
  check "clean remove" "still there" [ ! -d "$path" ]
else
  fail "worktree exists for remove checks" "no worktree at '$path'"
fi
check "branch kept" "gone" git -C "$repo" show-ref --verify -q refs/heads/autopilot/r1/U1

echo "worktree: $passes passed, $failures failed"
[ "$failures" = 0 ]
