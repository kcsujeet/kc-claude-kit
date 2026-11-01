#!/usr/bin/env bash
# UserPromptSubmit hook: tells Claude when this session runs an older version of this plugin than
# is installed, so it asks the person for /reload-plugins instead of working on rules the session
# never loaded. A session loads plugins at startup or at /reload-plugins, and its hooks keep the
# loaded version's path until a reload
# (https://code.claude.com/docs/en/plugins/loading#when-auto-update-runs), so CLAUDE_PLUGIN_ROOT is
# the version this session runs; installed_plugins.json records the installed ones.
#
# Every plugin in the kit runs this file: the others link to kc-gates' copy, and Claude Code copies
# a link within the marketplace into each plugin's cache
# (https://code.claude.com/docs/en/plugins/host-marketplace#share-files-within-a-marketplace-with-symlinks).
# It says so once per session and installed version, reading the hook payload's session_id from
# stdin. Without jq it stays quiet. Always exits 0.

set -u

command -v jq >/dev/null 2>&1 || exit 0
loaded_root=${CLAUDE_PLUGIN_ROOT:-}
plugin_data_dir=${CLAUDE_PLUGIN_DATA:-}
[ -n "$loaded_root" ] || exit 0
[ -n "$plugin_data_dir" ] || exit 0
config_dir=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
session_id=$(jq -r '.session_id // empty' 2>/dev/null)
[ -n "$session_id" ] || exit 0

# Every install of this plugin, at any scope, sits beside the loaded copy in
# cache/<marketplace>/<plugin>/<version>. A copy loaded from a clone or with --plugin-dir has none.
installs=$(jq -c --arg plugin_dir "$(dirname "$loaded_root")/" \
  '[.plugins[][] | select(.installPath | startswith($plugin_dir))]' \
  "$config_dir/plugins/installed_plugins.json" 2>/dev/null)
[ -n "$installs" ] || exit 0
[ "$installs" != "[]" ] || exit 0
is_loaded_copy_installed=$(printf '%s' "$installs" | jq --arg root "$loaded_root" 'any(.[]; .installPath == $root)')
[ "$is_loaded_copy_installed" = false ] || exit 0

installed_versions=$(printf '%s' "$installs" | jq -r 'map(.version) | unique | join(", ")')
told_file="$plugin_data_dir/told-loaded-version/$session_id"
[ "$(cat "$told_file" 2>/dev/null)" != "$installed_versions" ] || exit 0
mkdir -p "$(dirname "$told_file")"
printf '%s\n' "$installed_versions" > "$told_file"

plugin=$(basename "$(dirname "$loaded_root")")
echo "This session runs $plugin $(basename "$loaded_root"), but $installed_versions is installed: its newer rules aren't active here until the person types /reload-plugins or starts a new session. Ask them for it before a review pass or other work $plugin drives."
exit 0
