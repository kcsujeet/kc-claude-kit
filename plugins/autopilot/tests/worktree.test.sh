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
repo_phys=$(cd "$repo" && pwd -P)

status=0
out=$(bash "$script" create "$repo" r1 U1 main ENG-1-unit-one 2>"$tmp/err") || status=$?
[ "$status" = 0 ] || fail "create exits 0" "status $status: $(cat "$tmp/err")"
path=$(printf '%s' "$out" | jq -r .path 2>/dev/null || true)
branch=$(printf '%s' "$out" | jq -r .branch 2>/dev/null || true)
check "branch name" "$branch" [ "$branch" = ENG-1-unit-one ]
check "worktree path" "$path" [ "$path" = "$repo_phys/.claude/worktrees/autopilot-r1-U1" ]
head=$(git -C "$path" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
check "worktree on branch" "HEAD is '$head'" [ "$head" = ENG-1-unit-one ]
check "config copied" "missing" [ -f "$path/.claude/autopilot.json" ]

again=$(bash "$script" create "$repo" r1 U1 main ENG-1-unit-one 2>/dev/null || true)
if [ -n "$out" ] && [ "$again" = "$out" ]; then
  pass "create is idempotent"
else
  fail "create is idempotent" "$again"
fi

if [ -d "$path" ]; then
  echo dirty > "$path/new-file.txt"
  status=0
  bash "$script" remove "$repo" "$path" 2>"$tmp/err" || status=$?
  if [ "$status" = 1 ] && grep -qF "has uncommitted changes" "$tmp/err" && [ -d "$path" ]; then
    pass "refuses dirty remove"
  else
    fail "refuses dirty remove" "status $status, stderr: $(cat "$tmp/err"), exists: $([ -d "$path" ] && echo yes || echo no)"
  fi
  rm "$path/new-file.txt"
  ln -s "$tmp" "$path/node_modules"
  status=0
  bash "$script" remove "$repo" "$path" 2>"$tmp/err" || status=$?
  [ "$status" = 0 ] || fail "clean remove exits 0" "status $status: $(cat "$tmp/err")"
  check "clean remove, untracked symlink ignored" "still there" [ ! -d "$path" ]
else
  fail "worktree exists for remove checks" "no worktree at '$path'"
fi
check "branch kept" "gone" git -C "$repo" show-ref --verify -q refs/heads/ENG-1-unit-one

# Recreate after remove: same branch, earlier commit kept.
recreated_path=""
first=$(bash "$script" create "$repo" r3 U3 main ENG-3-unit-three 2>/dev/null || true)
first_path=$(printf '%s' "$first" | jq -r .path 2>/dev/null || true)
if [ -n "$first_path" ] && [ -d "$first_path" ]; then
  git -C "$first_path" -c user.email=t@t -c user.name=t commit -q --allow-empty -m work
  bash "$script" remove "$repo" "$first_path" 2>/dev/null || true
  status=0
  second=$(bash "$script" create "$repo" r3 U3 main ENG-3-unit-three 2>"$tmp/err") || status=$?
  recreated_path=$(printf '%s' "$second" | jq -r .path 2>/dev/null || true)
  if [ "$status" = 0 ] && [ "$recreated_path" = "$first_path" ] \
     && [ "$(git -C "$recreated_path" rev-parse --abbrev-ref HEAD 2>/dev/null || true)" = ENG-3-unit-three ] \
     && [ "$(git -C "$recreated_path" log -1 --format=%s 2>/dev/null || true)" = work ]; then
    pass "recreate after remove keeps branch and commit"
  else
    fail "recreate after remove keeps branch and commit" "status $status: $(cat "$tmp/err")"
  fi
else
  fail "recreate after remove keeps branch and commit" "first create failed"
fi

# A plain directory at the path is not a worktree: refuse, leave it alone.
mkdir -p "$repo/.claude/worktrees/autopilot-r2-U2"
status=0
bash "$script" create "$repo" r2 U2 main ENG-2-unit-two >/dev/null 2>"$tmp/err" || status=$?
if [ "$status" = 1 ] && grep -qF "exists but is not a worktree of" "$tmp/err" \
   && [ -d "$repo/.claude/worktrees/autopilot-r2-U2" ]; then
  pass "refuses plain directory at worktree path"
else
  fail "refuses plain directory at worktree path" "status $status, stderr: $(cat "$tmp/err")"
fi

echo "worktree: $passes passed, $failures failed"
[ "$failures" = 0 ]
