#!/usr/bin/env bash
# PostToolUse hook for Bash: right after a command that merges a pull request, installs what the
# merge brought to this plugin's marketplace (update-marketplace.sh, without its ten-minute wait)
# and states the reload as remind-reload.sh does. Merging installs nothing by itself, and a host
# that reloads plugins on its own reloads only what is installed. A `gh pr merge` written inside a
# heredoc also triggers a look, which is harmless.
#
# Input: the PostToolUse payload on stdin. Output: one PostToolUse JSON object, or nothing. Always
# exits 0. Hook schema: https://code.claude.com/docs/en/hooks
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
reload_statement=""
if [ "$(cat "$installed_plugins_file" 2>/dev/null)" != "$installed_before" ]; then
  # remind-reload.sh holds the words for "the installed plugins changed", per host.
  reload_statement=$(jq -cn '{tool_input: {command: "claude plugin update"}}' | bash "$scripts_dir/remind-reload.sh")
fi

# A partial update both fails and installs: Claude hears both, in one object.
printf '%s\n%s\n' "$update_failure" "$reload_statement" | jq -cs '
  map(.hookSpecificOutput.additionalContext) | select(length > 0)
  | {hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: join(" ")}}' 2>/dev/null
exit 0
