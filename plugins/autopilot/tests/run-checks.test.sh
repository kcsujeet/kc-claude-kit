#!/usr/bin/env bash
# Tests scripts/run-checks.sh: runs every check, reports each, fails if any fail.
set -euo pipefail
tests_dir=$(cd "$(dirname "$0")" && pwd)
script="$(dirname "$tests_dir")/scripts/run-checks.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
passes=0
failures=0
pass() { echo "ok   $1"; passes=$((passes + 1)); }
fail() { echo "FAIL $1"; echo "     $2"; failures=$((failures + 1)); }

echo '{"checks":["true","echo boom; exit 3","pwd > where.txt"]}' > "$tmp/c.json"
status=0
out=$(bash "$script" "$tmp/c.json" "$tmp" 2>&1) || status=$?
if [ "$status" = 1 ]; then pass "exit 1 on a failure"; else fail "exit 1 on a failure" "status $status"; fi
if printf '%s' "$out" | grep -q '^FAIL echo boom; exit 3$'; then pass "names the failing check"; else fail "names the failing check" "$out"; fi
if printf '%s' "$out" | grep -q '^    boom$'; then pass "shows its output"; else fail "shows its output" "$out"; fi
if printf '%s' "$out" | grep -q '^checks: 2/3 passed$'; then pass "summary line"; else fail "summary line" "$out"; fi
if [ "$(cat "$tmp/where.txt" 2>/dev/null)" = "$tmp" ]; then pass "runs in worktree, after a failure"; else fail "runs in worktree, after a failure" "wrong dir"; fi

echo '{"checks":["true"]}' > "$tmp/ok.json"
if bash "$script" "$tmp/ok.json" "$tmp" >/dev/null 2>&1; then pass "exit 0 when all pass"; else fail "exit 0 when all pass" "non-zero"; fi

echo "run-checks: $passes passed, $failures failed"
[ "$failures" = 0 ]
