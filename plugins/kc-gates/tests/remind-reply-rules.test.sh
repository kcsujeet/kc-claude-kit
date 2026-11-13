#!/usr/bin/env bash
# Tests scripts/remind-reply-rules.sh: every turn starts with the reply rules; a miss the Stop hooks
# noted for this session is named once, then removed; another session's misses stay its own.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
hook="$(dirname "$tests_dir")/scripts/remind-reply-rules.sh"
length_hook="$(dirname "$tests_dir")/scripts/check-reply-length.sh"
export CLAUDE_PLUGIN_DATA=$work_dir/data

run_hook() { jq -cn --arg id "$1" '{session_id: $id, hook_event_name: "UserPromptSubmit", prompt: "next"}' | bash "$hook"; }

first=$(run_hook s)
expect_contains "a turn with no misses gets the rules" "Reply rules for this turn: answer first, under 180 words" "$first"
expect_eq "a turn with no misses names none" "" "$(printf '%s\n' "$first" | grep 'last reply' || true)"

# The length hook notes a 250-word reply; the next turn names it once.
long_reply=$(awk 'BEGIN { for (i = 1; i <= 250; i++) printf "word "; print "" }')
jq -cn --arg reply "$long_reply" '{session_id: "s", hook_event_name: "Stop", last_assistant_message: $reply}' | bash "$length_hook"
second=$(run_hook s)
expect_contains "the next turn names the miss" "- It ran 250 words of prose, past the 180 limit." "$second"
expect_contains "it says not to repeat the last reply" "Don't repeat or rewrite it" "$second"
expect_eq "the miss is named only once" "" "$(run_hook s | grep 'last reply' || true)"

jq -cn --arg reply "$long_reply" '{session_id: "other", hook_event_name: "Stop", last_assistant_message: $reply}' | bash "$length_hook"
expect_eq "another session's miss isn't named here" "" "$(run_hook s | grep 'last reply' || true)"
expect_contains "that session gets its own" "It ran 250 words" "$(run_hook other)"

expect_contains "without a plugin data folder the rules still print" "Reply rules for this turn" "$(jq -cn '{session_id: "s"}' | CLAUDE_PLUGIN_DATA='' bash "$hook")"

finish
