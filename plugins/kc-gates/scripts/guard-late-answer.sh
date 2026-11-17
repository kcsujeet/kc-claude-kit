#!/usr/bin/env bash
# PreToolUse hook (every tool): denies the first tool call of a turn whose prompt is a question
# (is_question in lib/reply-misses.sh) when Claude has written no text yet this turn, so the
# answer comes before any tool work. The deny reason says to answer in text first; Claude's next
# message then carries the text and the tool call is allowed. Only the first call is checked:
# once the turn holds any assistant text or an earlier tool call (a denied call is kept in the
# transcript, so a retry is never denied twice), every call passes.
#
# Accepted false positive: a question that really needs a lookup to answer. The first sentence can
# still say what it will check, which is the answer's honest start.
#
# Input: the PreToolUse payload on stdin. Output: the deny JSON, nothing otherwise. Always exits 0,
# and allows without jq or a readable transcript.
# Hook schema: https://code.claude.com/docs/en/hooks
set -u

# shellcheck source=lib/reply-misses.sh
. "$(dirname "$0")/lib/reply-misses.sh"

command -v jq >/dev/null 2>&1 || exit 0
payload=$(cat)
transcript=$(printf '%s' "$payload" | jq -r '.transcript_path // empty')
tool_use_id=$(printf '%s' "$payload" | jq -r '.tool_use_id // empty')
[ -r "$transcript" ] || exit 0
lib_dir="$(dirname "$0")/lib"

prompt=$(jq -L "$lib_dir" -rs 'include "typed-message"; [.[] | select(is_typed_message)] | last | [typed_texts] | join("\n")' "$transcript" 2>/dev/null) || exit 0
is_question "$prompt" || exit 0

# Assistant text blocks, and tool calls other than this one, already in the turn.
started=$(jq -L "$lib_dir" -rs --arg id "$tool_use_id" '
  include "typed-message";
  [turn_entries[] | select(.type == "assistant") | .message.content[]?
   | select((.type == "text" and ((.text | gsub("\\s"; "")) != "")) or (.type == "tool_use" and .id != $id))]
  | length > 0
' "$transcript" 2>/dev/null) || exit 0
[ "$started" = true ] && exit 0

printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked by the kc-gates plugin: the prompt is a question, and this is the turn'"'"'s first action. Answer the question in text first, then use tools."}}\n'
exit 0
