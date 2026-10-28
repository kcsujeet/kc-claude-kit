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
  out=$(CLAUDE_CONFIG_DIR=${CONFIG_DIR:-$tmp/no-config} bash "$script" "$root" kc-gates 2>/dev/null) || status=$?
  if [ "$status" = "$want_status" ] && [ "$out" = "$want_out" ]; then pass "$label"
  else fail "$label" "expected $want_status '$want_out', got $status '$out'"; fi
}

plugin "$tmp/side/kc-autopilot" kc-autopilot
plugin "$tmp/side/kc-gates" kc-gates
expect "side by side" 0 "$tmp/side/kc-gates" "$tmp/side/kc-autopilot"

plugin "$tmp/cache/mkt/kc-autopilot/0.1.0" kc-autopilot
plugin "$tmp/cache/mkt/kc-gates/2.0.0" kc-gates
plugin "$tmp/cache/mkt/kc-gates/2.10.0" kc-gates
expect "cache layout, highest version" 0 "$tmp/cache/mkt/kc-gates/2.10.0" "$tmp/cache/mkt/kc-autopilot/0.1.0"

plugin "$tmp/wrong/kc-autopilot" kc-autopilot
plugin "$tmp/wrong/kc-gates" something-else
expect "a directory naming another plugin is not it" 1 "" "$tmp/wrong/kc-autopilot"

expect "missing" 1 "" "$tmp/nowhere/kc-autopilot"

# The install record wins over the cache heuristic (which would pick 2.10.0).
mkdir -p "$tmp/config/plugins"
plugin "$tmp/cache2/mkt/kc-autopilot/0.1.0" kc-autopilot
plugin "$tmp/cache2/mkt/kc-gates/2.0.0" kc-gates
plugin "$tmp/cache2/mkt/kc-gates/2.10.0" kc-gates
plugin "$tmp/cache2/other/kc-gates/9.0.0" kc-gates
jq -n --arg ap "$tmp/cache2/mkt/kc-autopilot/0.1.0" --arg cr "$tmp/cache2/mkt/kc-gates/2.0.0" --arg other "$tmp/cache2/other/kc-gates/9.0.0" \
  '{version: 2, plugins: {"kc-autopilot@mkt": [{scope: "user", installPath: $ap}],
    "kc-gates@mkt": [{scope: "project", projectPath: "/elsewhere", installPath: "/missing"}, {scope: "user", installPath: $cr}],
    "kc-gates@other": [{scope: "user", installPath: $other}]}}' > "$tmp/config/plugins/installed_plugins.json"
CONFIG_DIR=$tmp/config expect "install record: this marketplace's user-scope entry" 0 "$tmp/cache2/mkt/kc-gates/2.0.0" "$tmp/cache2/mkt/kc-autopilot/0.1.0"
CONFIG_DIR=$tmp/config expect "install record without kc-autopilot: falls back to the layout" 0 "$tmp/side/kc-gates" "$tmp/side/kc-autopilot"

echo "plugin-root: $passes passed, $failures failed"
[ "$failures" = 0 ]
