#!/usr/bin/env bash
# Tests scripts/remind-reply-rules.sh: every turn starts with the reply rules; a miss the Stop hooks
# noted for this session is named once, then removed; another session's misses stay its own.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
hook="$(dirname "$tests_dir")/scripts/remind-reply-rules.sh"
export CLAUDE_PLUGIN_DATA=$work_dir/data

run_hook() { jq -cn --arg id "$1" '{session_id: $id, hook_event_name: "UserPromptSubmit", prompt: "next"}' | bash "$hook"; }
# Notes <miss> for session <id>, as the Stop hooks do.
note_miss() { mkdir -p "$CLAUDE_PLUGIN_DATA/reply-misses"; printf '%s\n' "$2" >> "$CLAUDE_PLUGIN_DATA/reply-misses/$1"; }

reminder_without_misses=$(run_hook s)
expect_contains "a turn with no misses gets the rules" "Reply rules for this turn: answer first, under 180 words" "$reminder_without_misses"
expect_eq "a turn with no misses names none" "" "$(printf '%s\n' "$reminder_without_misses" | grep 'last reply' || true)"

note_miss s "It ran too long."
reminder_with_misses=$(run_hook s)
expect_contains "the next turn names the miss" "- It ran too long." "$reminder_with_misses"
expect_contains "it says not to repeat the last reply" "Don't repeat or rewrite it" "$reminder_with_misses"
expect_eq "the miss is named only once" "" "$(run_hook s | grep 'last reply' || true)"

note_miss other "It ran too long."
expect_eq "another session's miss isn't named here" "" "$(run_hook s | grep 'last reply' || true)"
expect_contains "that session gets its own" "- It ran too long." "$(run_hook other)"

note_miss s "It ran too long."
expect_eq "a payload with no session id names no misses and reports no error" "" \
  "$(printf '{}' | bash "$hook" 2>&1 | grep -v '^Reply rules for this turn' || true)"
expect_contains "without a plugin data folder the rules still print" "Reply rules for this turn" "$(jq -cn '{session_id: "s"}' | CLAUDE_PLUGIN_DATA='' bash "$hook")"

# --- a question gets its own answer first ----------------------------------------------------------
run_prompt() {
  local mode=$1 prompt=$2 no_jq=0
  [ "$mode" = sed ] && no_jq=1
  jq -cn --arg p "$prompt" '{session_id: "q", hook_event_name: "UserPromptSubmit", prompt: $p}' | KC_GUARD_NO_JQ=$no_jq bash "$hook"
}
for mode in jq sed; do
  for question in "When are you thinking of doing the look back?" "why did the build fail" "Is it safe to merge" "does the cache expire on write?" "Do you think this is right" "which branch is this on" "  Can we ship today?  "; do
    expect_contains "[$mode] a question gets the answer-first trigger: $question" "your first sentence answers exactly that question" "$(run_prompt "$mode" "$question")"
  done
  expect_contains "[$mode] the trigger names a time for a when, a cause for a why" 'a "when" gets a time, a "why" the cause' "$(run_prompt "$mode" "when is it done?")"
  expect_contains "[$mode] the trigger says no work starts before the answer" "no tool work or other action starts before it unless answering needs a lookup" "$(run_prompt "$mode" "what changed?")"
  for instruction in "Fix the failing test" "do this now" "Update the changelog and push" "whenever you are ready, start" "next"; do
    expect_eq "[$mode] an instruction gets no answer-first trigger: $instruction" "" "$(run_prompt "$mode" "$instruction" | grep 'answers exactly that question' || true)"
  done
  expect_contains "[$mode] a question still gets the reply rules" "Reply rules for this turn" "$(run_prompt "$mode" "why?")"
done
expect_eq "a payload with no prompt gets no answer-first trigger" "" "$(printf '{}' | bash "$hook" | grep 'answers exactly that question' || true)"

# --- a prompt about status gets one line to read it first -------------------------------------------
for mode in jq sed; do
  for status_prompt in "are we done" "What's left?" "what's next" "Where are we on this" "status" "is it merged" "is the PR approved?" "what now" "what is the current status of the ticket"; do
    expect_contains "[$mode] a status prompt gets the read-first line: $status_prompt" "read the ticket's and PR's current state with a tool before stating it" "$(run_prompt "$mode" "$status_prompt")"
  done
  for other_prompt in "Fix the failing test" "next" "why did the build fail?" "the statuses table needs a column" "update the status page copy please" "merge it"; do
    expect_eq "[$mode] no status line for: $other_prompt" "" "$(run_prompt "$mode" "$other_prompt" | grep 'asks where work stands' || true)"
  done
done
expect_eq "a payload with no prompt gets no status line" "" "$(printf '{}' | bash "$hook" | grep 'asks where work stands' || true)"

# --- a prompt to fix something reported gets the reproduce-first line ------------------------------
for mode in jq sed; do
  for fix_prompt in "address the QA feedback on ABC-1" "the export is broken" "fix the failing build" "checkout crashes on submit" "look at the review comments" "fixing the login redirect" "debugging the checkout redirect" "it fixes the login redirect" "I fixed the login redirect"; do
    expect_contains "[$mode] a fix prompt gets the reproduce-first line: $fix_prompt" "reproduce each one (the running app, a test or the log) before proposing a cause" "$(run_prompt "$mode" "$fix_prompt")"
  done
  for other_prompt in "next" "add a price column" "what's left?" "prefix the ids with shop"; do
    expect_eq "[$mode] no reproduce-first line for: $other_prompt" "" "$(run_prompt "$mode" "$other_prompt" | grep 'Reproduced: line' || true)"
  done
done

finish
