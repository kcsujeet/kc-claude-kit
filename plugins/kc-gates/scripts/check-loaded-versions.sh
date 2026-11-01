#!/usr/bin/env bash
# Tells Claude when this session runs older versions of this marketplace's plugins than are
# installed, so it asks the person to type /reload-plugins instead of working on rules the session
# never loaded. A session loads plugins once, at startup or at the last /reload-plugins, and an
# update on disk doesn't reach it until then
# (https://code.claude.com/docs/en/plugins/loading#check-which-stage-a-plugin-reached); only the
# person can run /reload-plugins.
#
#   check-loaded-versions.sh snapshot   SessionStart: records the installed versions, which are
#                                       the ones the session just loaded
#   check-loaded-versions.sh check      UserPromptSubmit: prints one line when a plugin is newer
#                                       on disk than in the session, once per version, and once
#                                       for a failure update-marketplace.sh recorded
#
# This plugin's own hooks switch to a new version's path on /reload-plugins, so a change in
# CLAUDE_PLUGIN_ROOT means the session reloaded, and the snapshot is taken again. Reads the hook
# payload's session_id from stdin. Without jq or a data directory it stays quiet. Always exits 0.

set -u

mode=${1:-check}
plugin_root=${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
config=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
data=${CLAUDE_PLUGIN_DATA:-}

[ -n "$data" ] && command -v jq >/dev/null 2>&1 || exit 0
session_id=$(jq -r '.session_id // empty' 2>/dev/null)
[ -n "$session_id" ] || exit 0

marketplace_dir=$(dirname "$(dirname "$plugin_root")")
[ "$(basename "$(dirname "$marketplace_dir")")" = cache ] || exit 0
marketplace=$(basename "$marketplace_dir")
loaded_root_version=$(basename "$plugin_root")

# {"<plugin>": "<version>"} for each plugin installed from this marketplace.
installed_versions() {
  jq -c --arg m "$marketplace" '.plugins | with_entries(select(.key | endswith("@" + $m)))
    | with_entries(.key |= sub("@.*$"; "") | .value |= (.[0].version // ""))' \
    "$config/plugins/installed_plugins.json" 2>/dev/null
}

sessions="$data/loaded-versions"
snapshot="$sessions/$session_id.json"
mkdir -p "$sessions"

take_snapshot() {
  local installed
  installed=$(installed_versions)
  [ -n "$installed" ] || exit 0
  jq -n --argjson loaded "$installed" --arg root "$loaded_root_version" \
    '{loaded: $loaded, root: $root, told: {}}' > "$snapshot"
}

if [ "$mode" = snapshot ]; then
  find "$sessions" -name '*.json' -mtime +14 -delete 2>/dev/null
  take_snapshot
  exit 0
fi

# A session that started before this hook existed has no snapshot; what is installed now is the
# best guess at what it loaded.
[ -f "$snapshot" ] || take_snapshot
[ "$(jq -r '.root' "$snapshot")" = "$loaded_root_version" ] || take_snapshot

installed=$(installed_versions)
[ -n "$installed" ] || exit 0
behind=$(jq -r --argjson installed "$installed" '
  . as $s | $installed | to_entries[]
  | select(.value != ($s.loaded[.key] // .value) and .value != ($s.told[.key] // ""))
  | "\(.key) \($s.loaded[.key]) → \(.value)"' "$snapshot")

if [ -n "$behind" ]; then
  echo "This session runs older versions of $marketplace's plugins than are installed: $(printf '%s' "$behind" | paste -sd ',' - | sed 's/,/, /g'). Their newer rules aren't active here until the person types /reload-plugins, which only they can run, or starts a new session. Ask them for it before a review pass or other work these plugins drive."
  jq --argjson installed "$installed" '.told = (.told + $installed)' "$snapshot" > "$snapshot.tmp" \
    && mv "$snapshot.tmp" "$snapshot"
fi

error_file="$data/update-marketplace.error"
if [ -f "$error_file" ] && ! jq -e --arg e "$(cat "$error_file")" '.told_error == $e' "$snapshot" >/dev/null; then
  echo "Updating $marketplace's plugins during this session failed: $(cat "$error_file"). Tell the person; until it's fixed, new rules arrive only with Claude Code's own update at the start of a session."
  jq --arg e "$(cat "$error_file")" '.told_error = $e' "$snapshot" > "$snapshot.tmp" && mv "$snapshot.tmp" "$snapshot"
fi
exit 0
