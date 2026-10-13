#!/usr/bin/env bash
# Tests boot-app.sh and stop-app.sh with python3's http.server as the app.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
scripts="$(dirname "$tests_dir")/scripts"
tmp=$(mktemp -d)
trap 'bash "$scripts/stop-app.sh" "$tmp/state" 3 || true; bash "$scripts/stop-app.sh" "$tmp/state" 0 || true; rm -rf "$tmp"' EXIT
passes=0
failures=0
pass() { echo "ok   $1"; passes=$((passes + 1)); }
fail() { echo "FAIL $1"; echo "     $2"; failures=$((failures + 1)); }

mkdir -p "$tmp/wt" "$tmp/state"
echo hello > "$tmp/wt/index.html"
cat > "$tmp/config.json" <<'JSON'
{"launch":{"install":"touch installed.txt","start":"python3 -m http.server {port} --bind 127.0.0.1","ready":"http://127.0.0.1:{port}/","seed":"","ready_timeout_s":20,"ports":{"base":4700,"per_unit":10},"login":null},"checks":["true"]}
JSON

out=$(bash "$scripts/boot-app.sh" "$tmp/config.json" "$tmp/wt" 3 "$tmp/state" 2>/dev/null) || out='{}'
url=$(printf '%s' "$out" | jq -r '.url // "none"') || url="<jq failed>"
if [ "$url" = "http://127.0.0.1:4730/" ]; then pass "port from index"; else fail "port from index" "$url"; fi
if curl -fsS "$url" 2>/dev/null | grep -q hello; then pass "app serves"; else fail "app serves" "no hello"; fi
if [ -f "$tmp/wt/installed.txt" ]; then pass "install ran in worktree"; else fail "install ran in worktree" "missing"; fi

bash "$scripts/stop-app.sh" "$tmp/state" 3 || true
sleep 1
if curl -fsS "$url" >/dev/null 2>&1; then fail "stop frees port" "still serving"; else pass "stop frees port"; fi

cat > "$tmp/never.json" <<'JSON'
{"launch":{"install":"","start":"sleep 30 # {port}","ready":"http://127.0.0.1:{port}/","seed":"","ready_timeout_s":2,"ports":{"base":4800,"per_unit":10},"login":null},"checks":["true"]}
JSON
if bash "$scripts/boot-app.sh" "$tmp/never.json" "$tmp/wt" 0 "$tmp/state" >/dev/null 2>&1; then
  fail "times out" "booted"
else
  pass "times out"
fi

# Dev servers fork: the child must die with the group, and the port must be free.
cat > "$tmp/fork.json" <<'JSON'
{"launch":{"install":"","start":"sh -c 'python3 -m http.server {port} --bind 127.0.0.1' & wait","ready":"http://127.0.0.1:{port}/","seed":"","ready_timeout_s":20,"ports":{"base":4700,"per_unit":10},"login":null},"checks":["true"]}
JSON
fork_url=$(bash "$scripts/boot-app.sh" "$tmp/fork.json" "$tmp/wt" 3 "$tmp/state" 2>/dev/null | jq -r '.url // "none"') || fork_url=none
bash "$scripts/stop-app.sh" "$tmp/state" 3 || true
sleep 1
if [ "$fork_url" != none ] && ! curl -fsS "$fork_url" >/dev/null 2>&1; then pass "stop kills forked children"; else fail "stop kills forked children" "url=$fork_url"; fi

echo "app-lifecycle: $passes passed, $failures failed"
[ "$failures" = 0 ]
