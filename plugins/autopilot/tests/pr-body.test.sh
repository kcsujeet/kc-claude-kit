#!/usr/bin/env bash
# Tests scripts/pr-body.sh against a golden body, escaping, and empty lists.
set -euo pipefail
tests_dir=$(cd "$(dirname "$0")" && pwd)
script="$(dirname "$tests_dir")/scripts/pr-body.sh"
fixtures="$tests_dir/fixtures/pr"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
passes=0
failures=0
pass() { echo "ok   $1"; passes=$((passes + 1)); }
fail() { echo "FAIL $1"; echo "     $2"; failures=$((failures + 1)); }

status=0
body=$(bash "$script" "$fixtures/unit-result.json" 2>&1) || status=$?
if [ "$status" = 0 ] && [ "$body" = "$(cat "$fixtures/expected-body.md")" ]; then
  pass "body matches golden"
else
  fail "body matches golden" "status $status; $(diff -u "$fixtures/expected-body.md" <(printf '%s\n' "$body") || true)"
fi

cat > "$tmp/escape.json" <<'JSON'
{"plan_title":"P","unit":{"id":"U1","title":"T"},"rounds":0,
 "criteria":[{"id":"AC1","statement":"a | b\nc","passes":false,"evidence":"x|y"}],
 "staff":{"design":"d","final":"f"},"review":{"fixed":[],"dismissed":[]},"qa":[],"decisions":[]}
JSON
status=0
body=$(bash "$script" "$tmp/escape.json" 2>&1) || status=$?
if printf '%s' "$body" | grep -qF '| AC1 a \| b c | FAIL | x\|y |'; then pass "escapes pipes, flattens newlines"; else fail "escapes pipes, flattens newlines" "status $status: $body"; fi

cat > "$tmp/empty.json" <<'JSON'
{"plan_title":"P","unit":{"id":"U1","title":"T"},"rounds":0,
 "criteria":[],"staff":{"design":"d","final":"f"},
 "review":{"fixed":[],"dismissed":[]},"qa":[],"decisions":[]}
JSON
status=0
body=$(bash "$script" "$tmp/empty.json" 2>&1) || status=$?
if [ "$status" = 0 ]; then pass "empty lists: exit 0"; else fail "empty lists: exit 0" "status $status: $body"; fi
if [ "$(printf '%s' "$body" | grep -c '^- none$')" = 2 ]; then pass "empty lists: none lines"; else fail "empty lists: none lines" "$body"; fi
if printf '%s' "$body" | grep -q '^- no confirmed bugs$'; then pass "empty lists: no confirmed bugs"; else fail "empty lists: no confirmed bugs" "$body"; fi

cat > "$tmp/inject.json" <<'JSON'
{"plan_title":"P","unit":{"id":"U1","title":"T"},"rounds":1,
 "criteria":[],"staff":{"design":"d","final":"f"},
 "review":{"fixed":["a\n</details>\n## injected"],"dismissed":[]},"qa":[],
 "decisions":[{"step":"s","outcome":"</details><b>x","reason":"r"}]}
JSON
status=0
body=$(bash "$script" "$tmp/inject.json" 2>&1) || status=$?
if [ "$status" = 0 ] && [ "$(printf '%s\n' "$body" | grep -c '</details>')" = 1 ] && ! printf '%s\n' "$body" | grep -q '^## injected'; then pass "free text cannot break the page"; else fail "free text cannot break the page" "status $status: $body"; fi
if printf '%s\n' "$body" | grep -q 'in 1 fix round\.'; then pass "singular fix round"; else fail "singular fix round" "$body"; fi

echo "pr-body: $passes passed, $failures failed"
[ "$failures" = 0 ]
