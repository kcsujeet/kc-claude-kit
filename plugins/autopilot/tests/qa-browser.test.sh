#!/usr/bin/env bash
# Tests scripts/qa-browser.sh install handling with stub npm/playwright: a
# failed install is never marked ready (for ensure or run), and the install
# runs from the caller's directory so version managers resolve its node.
set -euo pipefail
tests_dir=$(cd "$(dirname "$0")" && pwd)
script="$(dirname "$tests_dir")/scripts/qa-browser.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
tmp=$(cd "$tmp" && pwd -P)
passes=0
failures=0
pass() { echo "ok   $1"; passes=$((passes + 1)); }
fail() { echo "FAIL $1"; echo "     $2"; failures=$((failures + 1)); }
check() { local label=$1; shift; if "$@"; then pass "$label"; else fail "$label" "$*"; fi; }

# A stub npm that installs a stub playwright CLI (or fails when told to) and
# records the directory it ran from.
mkdir -p "$tmp/bin" "$tmp/caller"
cat > "$tmp/bin/npm" <<'STUB'
#!/usr/bin/env bash
pwd > "$NPM_LOG"
[ "${NPM_FAIL:-}" = 1 ] && { echo "npm: no node version" >&2; exit 126; }
prefix=""
while [ $# -gt 0 ]; do [ "$1" = --prefix ] && prefix=$2; shift; done
mkdir -p "$prefix/node_modules/.bin"
printf '#!/usr/bin/env bash\nexit 0\n' > "$prefix/node_modules/.bin/playwright"
chmod +x "$prefix/node_modules/.bin/playwright"
STUB
chmod +x "$tmp/bin/npm"
printf 'console.log("ran")\n' > "$tmp/caller/script.cjs"

qa() { (cd "$tmp/caller" && PATH="$tmp/bin:$PATH" NPM_LOG="$tmp/npm.log" AUTOPILOT_CACHE="$1" bash "$script" "${@:2}"); }

status=0; NPM_FAIL=1 qa "$tmp/c1" ensure >/dev/null 2>&1 || status=$?
check "ensure: failed install exits non-zero" [ "$status" != 0 ]
check "ensure: failed install is not marked ready" [ ! -f "$tmp/c1/playwright-1.64.0/.ready" ]

status=0; NPM_FAIL=1 qa "$tmp/c2" run "$tmp/caller/script.cjs" >/dev/null 2>&1 || status=$?
check "run: failed install exits non-zero" [ "$status" != 0 ]
check "run: failed install is not marked ready" [ ! -f "$tmp/c2/playwright-1.64.0/.ready" ]

status=0; out=$(qa "$tmp/c3" ensure 2>/dev/null) || status=$?
check "ensure: good install exits 0" [ "$status" = 0 ]
check "ensure: good install is marked ready" [ -f "$tmp/c3/playwright-1.64.0/.ready" ]
check "ensure: prints node_modules" [ "$out" = "$tmp/c3/playwright-1.64.0/node_modules" ]
check "install runs from the caller's directory" [ "$(cat "$tmp/npm.log")" = "$tmp/caller" ]

echo "qa-browser: $passes passed, $failures failed"
[ "$failures" = 0 ]
