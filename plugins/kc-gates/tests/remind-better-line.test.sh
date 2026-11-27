#!/usr/bin/env bash
# Tests scripts/remind-better-line.sh: a Bash command that hands work over (git push, gh pr create,
# gh pr ready) gets one additionalContext line to raise the bar; edits, agents, reads and every other
# command get nothing. It runs in PostToolUse, before the reply, and never in a Stop hook (the person
# would only see it after the reply). Holds step 5 of kc-raise-the-bar.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
hook="$(dirname "$tests_dir")/scripts/remind-better-line.sh"
require_jq

# Runs the hook on one tool call (name, then the input key and value); prints its output.
run_call() {
  jq -cn --arg name "$1" --arg key "$2" --arg value "$3" \
    '{session_id: "s", hook_event_name: "PostToolUse", tool_name: $name, tool_input: {($key): $value}}' \
    | bash "$hook"
}
# Prints reminded or silent for a call.
verdict() {
  if run_call "$@" | grep -q 'raise-the-bar'; then echo reminded; else echo silent; fi
}
expect_hand_off() { expect_eq "$1 is a hand-off, reminded" reminded "$(verdict Bash command "$2")"; }
expect_quiet() { expect_eq "$1 is silent" silent "$(verdict "$2" "$3" "$4")"; }

# Hand-off commands remind.
expect_hand_off "git push" "git push -u origin feature"
expect_hand_off "git push in another directory" "git -C /tmp/repo push"
expect_hand_off "gh pr create" "gh pr create --fill"
expect_hand_off "gh pr ready" "gh pr ready 12"
expect_hand_off "a push after another command" "git status && git push"
expect_hand_off "a push on a later line" $'git fetch\ngit push origin feature'

# Everything else is silent: work that is not a hand-off, reads, and text that merely names a hand-off.
expect_quiet "an Edit" Edit file_path src/orders.rb
expect_quiet "a Write" Write file_path src/orders.rb
expect_quiet "an Agent" Agent prompt "check the orders"
expect_quiet "a Read" Read file_path src/orders.rb
expect_quiet "a test run" Bash command "bundle exec rspec"
expect_quiet "a commit" Bash command "git commit -m done"
expect_quiet "git log" Bash command "git log --oneline"
expect_quiet "gh pr view" Bash command "gh pr view 12"
expect_quiet "gh pr checks" Bash command "gh pr checks 12 --watch"
expect_quiet "an echo that names a push" Bash command "echo git push is next"
# shellcheck disable=SC2016 # literal REPL code, not meant to expand
expect_quiet "a REPL call" REPL code 'await $`ls`.text()'

# The output is additionalContext for PostToolUse, short, and keeps it out of the reply.
out=$(run_call Bash command "git push")
expect_eq "the output is PostToolUse additionalContext" PostToolUse "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.hookEventName')"
context=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext')
expect_contains "it points to the raise-the-bar skill" "kc-conventions:kc-raise-the-bar" "$context"
expect_contains "it keeps the check out of the reply" "out of the reply" "$context"
expect_eq "it is under 40 words ($(printf '%s' "$context" | wc -w | tr -d ' '))" ok "$([ "$(printf '%s' "$context" | wc -w)" -lt 40 ] && echo ok || echo long)"
expect_eq "it blocks nothing" "" "$(printf '%s' "$out" | jq -r '.decision // empty')"

# It speaks on every hand-off, not once per turn, and needs no data folder or session id.
expect_eq "a second push speaks again" reminded "$(verdict Bash command "git push")"
expect_eq "no session id: still reminds" reminded "$(jq -cn '{tool_name: "Bash", tool_input: {command: "git push"}}' | bash "$hook" | grep -q raise-the-bar && echo reminded || echo silent)"
expect_eq "empty input: nothing printed" "" "$(printf '' | bash "$hook")"

finish
