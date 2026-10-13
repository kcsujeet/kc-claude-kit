#!/usr/bin/env bash
# Finds a dependency plugin installed beside autopilot, so the deliver
# workflow can run that plugin's own scripts (code-review's gather step).
#
# Usage: plugin-root.sh <autopilot-root> <plugin-name>
# First, Claude Code's install record,
# ${CLAUDE_CONFIG_DIR:-~/.claude}/plugins/installed_plugins.json
# ({"plugins": {"<name>@<marketplace>": [{scope, projectPath?, installPath}]}}):
# the marketplace is the one whose autopilot entry installed <autopilot-root>,
# and <name>@<that marketplace> wins, preferring the entry for the current
# directory's project, then the user-scope one, then any other. Then, as a
# fallback, in order:
#   <autopilot-root>/../<name>            plugins side by side (a marketplace
#                                         checkout, or --plugin-dir siblings)
#   <autopilot-root>/../../<name>/<ver>   the plugin cache layout,
#                                         ~/.claude/plugins/cache/<marketplace>/<name>/<version>;
#                                         the highest version wins (sort -V)
# A candidate counts only when its .claude-plugin/plugin.json names <name>.
# Plugin layout: https://code.claude.com/docs/en/plugins-reference
# Output: the plugin's absolute root on stdout.
# Exit: 0 found; 1 not found; 2 usage error or jq missing.
set -euo pipefail

command -v jq >/dev/null 2>&1 || { echo "autopilot: jq is required" >&2; exit 2; }
[ "$#" = 2 ] || { echo "usage: plugin-root.sh <autopilot-root> <plugin-name>" >&2; exit 2; }
root=$1
name=$2

names_plugin() {
  [ -f "$1/.claude-plugin/plugin.json" ] && [ "$(jq -r '.name // empty' "$1/.claude-plugin/plugin.json" 2>/dev/null)" = "$name" ]
}

# Prints the install path recorded for <name> in autopilot's marketplace.
from_install_record() {
  local record=${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/installed_plugins.json real_root project
  [ -f "$record" ] || return 1
  real_root=$(cd "$root" && pwd -P) || return 1
  project=$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)
  jq -r --arg root "$real_root" --arg name "$name" --arg project "$project" '
    (.plugins // {}) as $p
    | [$p | to_entries[] | select(.key | startswith("autopilot@"))
       | select(any(.value[]?; .installPath == $root)) | .key | sub("^autopilot@"; "")] as $markets
    | [$markets[] as $m | $p["\($name)@\($m)"] // [] | .[]] as $entries
    | ([$entries[] | select(.projectPath == $project)] + [$entries[] | select(.scope == "user")] + $entries)
    | map(.installPath | strings) | .[]' "$record" 2>/dev/null
}

while IFS= read -r candidate; do
  if [ -n "$candidate" ] && names_plugin "$candidate"; then
    (cd "$candidate" && pwd -P)
    exit 0
  fi
done < <(from_install_record || true)

if names_plugin "$root/../$name"; then
  (cd "$root/../$name" && pwd -P)
  exit 0
fi
if [ -d "$root/../../$name" ]; then
  while IFS= read -r candidate; do
    if names_plugin "$candidate"; then
      (cd "$candidate" && pwd -P)
      exit 0
    fi
  done < <(find "$root/../../$name" -mindepth 1 -maxdepth 1 -type d | sort -rV)
fi
echo "plugin-root: $name not found beside $root" >&2
exit 1
