#!/usr/bin/env bash
# PostToolUse hook for Bash: right after a command that merges a pull request, installs what the
# merge brought to this plugin's marketplace, so a change merged into it reaches the person's
# sessions now instead of on the next ten-minute look (update-marketplace.sh). Merging installs
# nothing by itself, and a host that reloads plugins on its own (the Claude desktop app) reloads
# only what is installed.
#
# It runs update-marketplace.sh at once (KC_UPDATE_NOW=1), which updates only when the marketplace's
# source has moved, so a merge in any other repository costs one look at the source and nothing
# else. When the installed plugins changed, it tells Claude what remind-reload.sh tells it after
# an install: state the reload plainly (desktop app) or ask for /reload-plugins (elsewhere). An
# update failure is passed on as update-marketplace.sh words it. A `gh pr merge` written inside a
# heredoc also triggers a look, which is harmless.
#
# Input: the PostToolUse payload on stdin. Output: PostToolUse JSON as additionalContext, or
# nothing. Always exits 0. Hook schema: https://code.claude.com/docs/en/hooks
set -u

scripts_dir=$(dirname "$0")
# shellcheck source=lib/hook-input.sh
. "$scripts_dir/lib/hook-input.sh"

input=$(cat)
command=$(extract_field "$input" command)
is_merge=false
while IFS= read -r segment; do
  is_merge_segment "$segment" && is_merge=true
done <<EOF
$(split_segments "$command")
EOF
[ "$is_merge" = true ] || exit 0

installed_plugins_file="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/installed_plugins.json"
installed_before=$(cat "$installed_plugins_file" 2>/dev/null)
update_failure=$(printf '%s' "$input" | KC_UPDATE_NOW=1 KC_HOOK_EVENT=PostToolUse bash "$scripts_dir/update-marketplace.sh")
if [ -n "$update_failure" ]; then
  printf '%s\n' "$update_failure"
  exit 0
fi
[ "$(cat "$installed_plugins_file" 2>/dev/null)" != "$installed_before" ] || exit 0

# remind-reload.sh holds the words for "the installed plugins changed", per host.
jq -cn '{tool_input: {command: "claude plugin update"}}' | bash "$scripts_dir/remind-reload.sh"
exit 0
