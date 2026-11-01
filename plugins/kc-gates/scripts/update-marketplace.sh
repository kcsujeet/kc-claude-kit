#!/usr/bin/env bash
# UserPromptSubmit hook, run in the background: keeps the marketplace this copy was installed from,
# and the plugins installed from it, current during a session. Claude Code's own auto-update runs
# once, minutes after a session's first message
# (https://code.claude.com/docs/en/plugins/loading#when-auto-update-runs), so a change merged after
# that, from any session or from GitHub, would wait for the next session. This looks at most every
# ten minutes, and updates only when the branch the marketplace's clone follows has moved.
#
# It follows Claude Code's switches: the marketplace's autoUpdate (a settings file's
# extraKnownMarketplaces entry first, then known_marketplaces.json; managed settings aren't read),
# and nothing while DISABLE_UPDATES, DISABLE_AUTOUPDATER or CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC
# is set, unless FORCE_AUTOUPDATE_PLUGINS=1. It updates user-scope installs; a project or local
# install waits for Claude Code's own pass. A failure is told to Claude once, as additionalContext,
# and retried on the next look. The session keeps what it loaded; check-loaded-version.sh says when
# it is behind. Reads the hook payload's cwd from stdin. Always exits 0.

set -u

update_interval_seconds=600

command -v jq >/dev/null 2>&1 || exit 0
loaded_root=${CLAUDE_PLUGIN_ROOT:-}
plugin_data_dir=${CLAUDE_PLUGIN_DATA:-}
[ -n "$loaded_root" ] || exit 0
[ -n "$plugin_data_dir" ] || exit 0
config_dir=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
installed_plugins_file="$config_dir/plugins/installed_plugins.json"
known_marketplaces_file="$config_dir/plugins/known_marketplaces.json"
session_cwd=$(jq -r '.cwd // empty' 2>/dev/null)

is_env_switch_on() { [ -n "${1:-}" ] && [ "$1" != 0 ]; }
if [ "${FORCE_AUTOUPDATE_PLUGINS:-}" != 1 ]; then
  is_env_switch_on "${DISABLE_UPDATES:-}" && exit 0
  is_env_switch_on "${DISABLE_AUTOUPDATER:-}" && exit 0
  is_env_switch_on "${CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:-}" && exit 0
fi

# The marketplace is in the id of the install whose path is this copy. A copy loaded from a clone
# or with --plugin-dir has no install, so no marketplace, and the autoUpdate check below stops it.
plugin_id=$(jq -r --arg root "$loaded_root" \
  '.plugins | to_entries[] | select(any(.value[]; .installPath == $root)) | .key' \
  "$installed_plugins_file" 2>/dev/null)
marketplace=${plugin_id#*@}

# A settings file's entry decides first, local over project over user; then known_marketplaces.json.
get_auto_update() {
  local settings_file auto_update
  for settings_file in "$session_cwd/.claude/settings.local.json" "$session_cwd/.claude/settings.json" \
    "$config_dir/settings.json"; do
    auto_update=$(jq -r --arg m "$marketplace" \
      '(.extraKnownMarketplaces // {})[$m] // {} | if has("autoUpdate") then .autoUpdate else empty end' \
      "$settings_file" 2>/dev/null)
    if [ -n "$auto_update" ]; then
      echo "$auto_update"
      return
    fi
  done
  jq -r --arg m "$marketplace" '.[$m].autoUpdate // false' "$known_marketplaces_file" 2>/dev/null
}
[ "$(get_auto_update)" = true ] || exit 0

clone_dir=$(jq -r --arg m "$marketplace" '.[$m].installLocation // empty' "$known_marketplaces_file" 2>/dev/null)
[ -n "$clone_dir" ] || exit 0
# A clone on a branch follows that branch; one pinned to a tag, or a folder that isn't a git clone,
# follows nothing.
clone_branch=$(git -C "$clone_dir" symbolic-ref -q --short HEAD 2>/dev/null) || exit 0

checked_at_file="$plugin_data_dir/update-marketplace.checked-at"
failure_file="$plugin_data_dir/update-marketplace.failure"
now=$(date +%s)
last_checked_at=$(cat "$checked_at_file" 2>/dev/null)
case "$last_checked_at" in '' | *[!0-9]*) last_checked_at=0 ;; esac
[ $((now - last_checked_at)) -ge "$update_interval_seconds" ] || exit 0
# Stamped before looking: a failed look waits the interval instead of running on every prompt.
mkdir -p "$plugin_data_dir"
echo "$now" > "$checked_at_file"

# Tells Claude about a failure the first time it is seen, and keeps it so the next look retries.
record_update_failure() {
  local failure=$1
  if [ "$(cat "$failure_file" 2>/dev/null)" != "$failure" ]; then
    jq -cn --arg context "Updating $marketplace's plugins during this session failed: $failure. Tell the person; until it's fixed, new versions arrive only with Claude Code's own update when a session starts." \
      '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $context}}'
  fi
  printf '%s\n' "$failure" > "$failure_file"
  exit 0
}

source_head=$(GIT_TERMINAL_PROMPT=0 git -C "$clone_dir" ls-remote origin "refs/heads/$clone_branch" 2>/dev/null | cut -f1)
[ -n "$source_head" ] || record_update_failure "couldn't reach the marketplace's source"
is_clone_current=false
[ "$source_head" = "$(git -C "$clone_dir" rev-parse HEAD)" ] && is_clone_current=true
has_pending_failure=false
[ -f "$failure_file" ] && has_pending_failure=true
if [ "$is_clone_current" = true ] && [ "$has_pending_failure" = false ]; then exit 0; fi

command -v claude >/dev/null 2>&1 || record_update_failure "the claude command isn't on the hook's PATH"
claude plugin marketplace update "$marketplace" >/dev/null 2>&1 \
  || record_update_failure "claude plugin marketplace update $marketplace failed"
failed_plugin_ids=""
for id in $(jq -r --arg m "$marketplace" \
  '.plugins | to_entries[] | select((.key | endswith("@" + $m)) and any(.value[]; .scope == "user")) | .key' \
  "$installed_plugins_file"); do
  claude plugin update "$id" --scope user >/dev/null 2>&1 || failed_plugin_ids="$failed_plugin_ids $id"
done
[ -z "$failed_plugin_ids" ] || record_update_failure "claude plugin update failed for$failed_plugin_ids"
rm -f "$failure_file"
exit 0
