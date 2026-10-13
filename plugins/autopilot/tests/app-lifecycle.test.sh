#!/usr/bin/env bash
# Tests boot-app.sh and stop-app.sh with python3's http.server as the app.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
scripts="$(dirname "$tests_dir")/scripts"
tmp=$(mktemp -d)
stale_pid=""
trap '[ -n "$stale_pid" ] && kill "$stale_pid" 2>/dev/null; bash "$scripts/stop-app.sh" "$tmp/state" 3 || true; bash "$scripts/stop-app.sh" "$tmp/state" 0 || true; rm -rf "$tmp"' EXIT
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

# A stale server on the unit's port must not make a failed start look ready.
cat > "$tmp/exits.json" <<'JSON'
{"launch":{"install":"","start":"exit 1 # {port}","ready":"http://127.0.0.1:{port}/","seed":"","ready_timeout_s":20,"ports":{"base":4900,"per_unit":10},"login":null},"checks":["true"]}
JSON
(cd "$tmp/wt" && exec python3 -m http.server 4900 --bind 127.0.0.1) >/dev/null 2>&1 &
stale_pid=$!
for _ in $(seq 1 20); do curl -fsS -o /dev/null http://127.0.0.1:4900/ 2>/dev/null && break; sleep 0.5; done
status=0
err=$(bash "$scripts/boot-app.sh" "$tmp/exits.json" "$tmp/wt" 0 "$tmp/state" 2>&1 >/dev/null) || status=$?
if [ "$status" = 1 ] && printf '%s' "$err" | grep -q 'port 4900 already serves'; then pass "stale server on the port fails"; else fail "stale server on the port fails" "status=$status err=$err"; fi
kill "$stale_pid" 2>/dev/null; wait "$stale_pid" 2>/dev/null || true
stale_pid=""

# A start that exits fails at once instead of waiting out ready_timeout_s.
sleep 1
status=0
started=$SECONDS
err=$(bash "$scripts/boot-app.sh" "$tmp/exits.json" "$tmp/wt" 0 "$tmp/state" 2>&1 >/dev/null) || status=$?
if [ "$status" = 1 ] && printf '%s' "$err" | grep -q 'app exited early' && [ $((SECONDS - started)) -lt 10 ]; then pass "start that exits fails early"; else fail "start that exits fails early" "status=$status after $((SECONDS - started))s err=$err"; fi

# A bad or self-referential pgid file is removed and nothing is killed.
own_pgid=$(ps -o pgid= -p $$ | tr -d ' ')
for bad in "" 0 1 abc "-5" "$own_pgid"; do
  printf '%s\n' "$bad" > "$tmp/state/app-9.pgid"
  bash "$scripts/stop-app.sh" "$tmp/state" 9
  if [ ! -f "$tmp/state/app-9.pgid" ]; then pass "stop ignores pgid '$bad'"; else fail "stop ignores pgid '$bad'" "file kept"; fi
done

echo "app-lifecycle: $passes passed, $failures failed"
[ "$failures" = 0 ]
