#!/usr/bin/env bash
# PreToolUse guard for session and agent starts. A forked session or agent starts with the whole
# conversation it came from and re-reads it on every call it makes, so a fork of a long session
# costs that context again on each of its calls. Refuses a fork while the session's context is
# above 100000 tokens: start_session with context "fork", hand_off_to_session (always a fork of
# this conversation), and an Agent call with subagent_type "fork". A fresh start with a full brief
# is allowed, and so is a fork of a short conversation. The context size is the last main-chain
# call's input plus cached tokens in the payload's transcript. Without jq (each jq call then fails
# quietly), a transcript, or a usage line, it allows. Output: the deny JSON or nothing; always exits 0. Hook schema:
# https://code.claude.com/docs/en/hooks.

set -u

readonly MAX_FORK_CONTEXT_TOKENS=100000
readonly TOKENS_PER_K=1000
# The last main-chain usage line sits near the end of the transcript; reading only the tail bounds
# the work on a long session.
readonly TRANSCRIPT_TAIL_LINES=2000

hook_payload=$(cat)

# Succeeds when the call starts a forked session or agent (jq -e: exit 0 on true, non-zero on
# false, a payload that isn't JSON, or no jq).
is_fork_start() {
  printf '%s' "$hook_payload" | jq -e '
    (.tool_name // "") as $tool | (.tool_input // {}) as $args
    | (($tool | endswith("__start_session")) and $args.context == "fork")
      or ($tool | endswith("__hand_off_to_session"))
      or ($tool == "Agent" and $args.subagent_type == "fork")' >/dev/null 2>&1
}

# Prints the last main-chain call's context in tokens, or nothing when it can't be read.
get_context_tokens() {
  local transcript
  transcript=$(printf '%s' "$hook_payload" | jq -r '.transcript_path // empty' 2>/dev/null)
  [ -f "$transcript" ] || return 0
  tail -n "$TRANSCRIPT_TAIL_LINES" "$transcript" | jq -R -r '
    fromjson? | select(type == "object" and (.isSidechain // false) == false)
    | .message.usage? | select(type == "object")
    | (.input_tokens // 0) + (.cache_read_input_tokens // 0) + (.cache_creation_input_tokens // 0)' 2>/dev/null \
    | tail -n 1
}

is_fork_start || exit 0
context_tokens=$(get_context_tokens)
case "$context_tokens" in "" | *[!0-9]*) exit 0 ;; esac
[ "$context_tokens" -gt "$MAX_FORK_CONTEXT_TOKENS" ] || exit 0

context_k=$((context_tokens / TOKENS_PER_K))
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked by the kc-conventions plugin: this forks a session holding %sk tokens of context, and the fork re-reads all of it on every call it makes. Start it fresh instead (start_session with context \\"fresh\\", or a named agent type) with a full brief: the goal, the files or area, what done looks like and what was already ruled out. For work in progress, write the hand-over to a notes file first and point the brief at it. A fork stays allowed while the context is under %sk tokens (kc-conventions:kc-delegate)."}}\n' "$context_k" "$((MAX_FORK_CONTEXT_TOKENS / TOKENS_PER_K))"
