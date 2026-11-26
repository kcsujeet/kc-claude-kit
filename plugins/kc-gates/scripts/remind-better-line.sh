#!/usr/bin/env bash
# PostToolUse hook: on the first work call of a turn (an edit, a write, an agent, or a Bash or REPL
# command that is not plainly read-only: lib/work-call.sh), adds a line to Claude's context: before
# handing the work over, measure it and look for a better, simpler way (kc-conventions:kc-raise-the-bar),
# and keep that out of the reply. The reminder reaches Claude while it is still working and is not
# shown to the person; an end-of-turn hook could only have said it after the reply was read.
#
# Once per turn: the session's marker file (better_line_marker_file) is set here and cleared by
# remind-reply-rules.sh at the next prompt. Without a data folder or a session id there is no marker,
# so it says nothing rather than on every call.
#
# Input: the PostToolUse payload on stdin. Output: PostToolUse JSON with the reminder as
# additionalContext, or nothing. Always exits 0. Hook schema: https://code.claude.com/docs/en/hooks
set -u

# shellcheck source=lib/reply-misses.sh
. "$(dirname "$0")/lib/reply-misses.sh"
# shellcheck source=lib/work-call.sh
. "$(dirname "$0")/lib/work-call.sh"

command -v jq >/dev/null 2>&1 || exit 0
payload=$(cat)
session_id=$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null)
marker_file=$(better_line_marker_file "$session_id") || exit 0
[ -e "$marker_file" ] && exit 0

tool_name=$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null)
tool_input=$(printf '%s' "$payload" | jq -r '.tool_input | (.command // .code // "") | tostring' 2>/dev/null)
is_work_call "$tool_name" "$tool_input" || exit 0

mkdir -p "$(dirname "$marker_file")" && : > "$marker_file"
printf '%s' "Before you hand this over: measure what you did and look for a better, simpler way (kc-conventions:kc-raise-the-bar). Apply it or note what you tried. Keep this out of the reply." \
  | jq -Rsc '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: .}}'
exit 0
