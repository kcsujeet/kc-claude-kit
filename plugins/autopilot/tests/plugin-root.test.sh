#!/usr/bin/env bash
# Tests scripts/plugin-root.sh: finds a sibling plugin in the side-by-side
# and plugin-cache layouts, and refuses a directory that is not that plugin.
set -euo pipefail
tests_dir=$(cd "$(dirname "$0")" && pwd)
script="$(dirname "$tests_dir")/scripts/plugin-root.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
tmp=$(cd "$tmp" && pwd -P)
passes=0
failures=0
pass() { echo "ok   $1"; passes=$((passes + 1)); }
fail() { echo "FAIL $1"; echo "     $2"; failures=$((failures + 1)); }
plugin() { mkdir -p "$1/.claude-plugin"; printf '{"name":"%s"}\n' "$2" > "$1/.claude-plugin/plugin.json"; }

expect() {
  local label=$1 want_status=$2 want_out=$3 root=$4 out status=0
  out=$(bash "$script" "$root" code-review 2>/dev/null) || status=$?
  if [ "$status" = "$want_status" ] && [ "$out" = "$want_out" ]; then pass "$label"
  else fail "$label" "expected $want_status '$want_out', got $status '$out'"; fi
}

plugin "$tmp/side/autopilot" autopilot
plugin "$tmp/side/code-review" code-review
expect "side by side" 0 "$tmp/side/code-review" "$tmp/side/autopilot"

plugin "$tmp/cache/mkt/autopilot/0.1.0" autopilot
plugin "$tmp/cache/mkt/code-review/2.0.0" code-review
plugin "$tmp/cache/mkt/code-review/2.10.0" code-review
expect "cache layout, highest version" 0 "$tmp/cache/mkt/code-review/2.10.0" "$tmp/cache/mkt/autopilot/0.1.0"

plugin "$tmp/wrong/autopilot" autopilot
plugin "$tmp/wrong/code-review" something-else
expect "a directory naming another plugin is not it" 1 "" "$tmp/wrong/autopilot"

expect "missing" 1 "" "$tmp/nowhere/autopilot"

echo "plugin-root: $passes passed, $failures failed"
[ "$failures" = 0 ]
