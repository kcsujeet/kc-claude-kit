#!/usr/bin/env bash
# PostToolUse hook: when a Bash command hands work over (`git push`, `gh pr create`, `gh pr ready`),
# adds a line to Claude's context: before the work goes to a reviewer, measure it and look for a
# better, simpler way (kc-conventions:kc-raise-the-bar), and keep that out of the reply. It runs on
# those commands only, so the ordinary calls of a turn cost nothing. The reminder reaches Claude
# while it is still working and is not shown to the person.
#
# Input: the PostToolUse payload on stdin. Output: PostToolUse JSON with the reminder as
# additionalContext, or nothing. Always exits 0. Hook schema: https://code.claude.com/docs/en/hooks
set -u

command -v jq >/dev/null 2>&1 || exit 0
payload=$(cat)
tool_input=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty | tostring' 2>/dev/null)
# A hand-off command at the start of the command or of a segment after ; & | ( or a newline.
readonly HAND_OFF='(^|[;&|(]|&&|\|\|)[[:space:]]*(git[[:space:]]+(-C[[:space:]]+[^[:space:]]+[[:space:]]+)?push|gh[[:space:]]+pr[[:space:]]+(create|ready))([[:space:]]|$)'
printf '%s' "$tool_input" | tr '\n' ';' | grep -Eq "$HAND_OFF" || exit 0

printf '%s' "Before you hand this over: measure what you did and look for a better, simpler way (kc-conventions:kc-raise-the-bar). Apply it or note what you tried. Keep this out of the reply." \
  | jq -Rsc '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: .}}'
exit 0
