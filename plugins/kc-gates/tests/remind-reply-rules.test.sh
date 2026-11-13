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

finish
