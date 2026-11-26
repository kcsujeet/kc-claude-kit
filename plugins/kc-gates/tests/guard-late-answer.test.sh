#!/usr/bin/env bash
# Tests scripts/guard-late-answer.sh: the first tool call of a turn whose prompt is a question is
# denied while no assistant text has been written; once text or an earlier tool call is in the
# turn, or when the prompt isn't a question, every call is allowed. Needs jq, no sed fallback.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
hook="$(dirname "$tests_dir")/scripts/guard-late-answer.sh"
transcript=$work_dir/transcript.jsonl

write_typed_message() { jq -cn --arg text "$1" '{type: "user", message: {role: "user", content: [{type: "text", text: $text}]}}'; }
write_text() { jq -cn --arg text "$1" '{type: "assistant", message: {role: "assistant", content: [{type: "text", text: $text}]}}'; }
write_thinking() { jq -cn '{type: "assistant", message: {role: "assistant", content: [{type: "thinking", thinking: "hm"}]}}'; }
write_tool_call() {
  jq -cn --arg id "$1" '{type: "assistant", message: {role: "assistant", content: [{type: "tool_use", id: $id, name: "Bash", input: {command: "ls"}}]}}'
}
write_tool_result() { jq -cn '{type: "user", message: {role: "user", content: [{type: "tool_result", tool_use_id: "t", content: "ok"}]}}'; }

# Runs the hook for the call <id> against the transcript; prints "denied" or "allowed".
run_hook() {
  local output
  output=$(jq -cn --arg path "$transcript" --arg id "${1:-t2}" \
    '{session_id: "s", transcript_path: $path, hook_event_name: "PreToolUse", tool_name: "Bash", tool_use_id: $id, tool_input: {command: "ls"}}' | bash "$hook")
  if [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision // empty')" = deny ]; then
    printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason' > "$work_dir/reason"
    echo denied
  elif [ -z "$output" ]; then echo allowed
  else echo "unexpected output"; fi
}

{ write_typed_message "why did the build fail?"; } > "$transcript"
expect_eq "the first call of a question's turn, no text yet, is denied" denied "$(run_hook)"
expect_contains "the reason says to answer in text first" "Answer the question in text first, then use tools." "$(cat "$work_dir/reason")"

{ write_typed_message "why did the build fail?"; write_tool_call t2; } > "$transcript"
expect_eq "the call itself already in the transcript is still the first" denied "$(run_hook t2)"

{ write_typed_message "why did the build fail?"; write_thinking; write_tool_call t2; } > "$transcript"
expect_eq "a thinking block is not an answer" denied "$(run_hook t2)"

{ write_typed_message "why did the build fail?"; write_text "A missing env var."; write_tool_call t2; } > "$transcript"
expect_eq "text before the call allows it" allowed "$(run_hook t2)"

{ write_typed_message "why did the build fail?"; write_text "  "; write_tool_call t2; } > "$transcript"
expect_eq "blank text is not an answer" denied "$(run_hook t2)"

{ write_typed_message "why did the build fail?"; write_tool_call t1; write_tool_result; write_tool_call t2; } > "$transcript"
expect_eq "a retry after a denied first call is allowed, never denied twice" allowed "$(run_hook t2)"

{ write_typed_message "earlier question?"; write_text "ok"; write_typed_message "fix the build"; } > "$transcript"
expect_eq "an instruction's first call is allowed" allowed "$(run_hook)"

{ write_typed_message "earlier question?"; write_text "ok"; write_typed_message "can you fix the build?"; } > "$transcript"
expect_eq "text from an earlier turn doesn't count" denied "$(run_hook)"

for question in "does it expire on write" "  Can we ship today?  "; do
  { write_typed_message "$question"; } > "$transcript"
  expect_eq "another question shape is denied: $question" denied "$(run_hook)"
done

write_typed_message "why did the build fail?" > "$transcript"
expect_eq "with no transcript it allows" "" "$(jq -cn '{tool_use_id: "t"}' | bash "$hook")"
expect_eq "with an unreadable transcript it allows" "" "$(jq -cn '{transcript_path: "/nonexistent", tool_use_id: "t"}' | bash "$hook")"


# A question about where work stands is answered by a lookup (fetch-status.sh already fetched the
# pull requests): its first call is the read, so it is allowed.
for question in "i think QA has been done?" "can the pr be merged?" "what next?"; do
  { write_typed_message "$question"; } > "$transcript"
  expect_eq "a status question's first call, a lookup, is allowed: $question" allowed "$(run_hook)"
done

finish
