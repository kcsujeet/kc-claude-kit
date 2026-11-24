#!/usr/bin/env bash
# shellcheck disable=SC2016  # the REPL scripts hold JavaScript backtick templates, not shell expansions
# Tests scripts/guard-batched-wait.sh: a Bash or REPL call that starts two CI watches, or one with a
# timeout over 10 minutes, is denied; a single watch with a short timeout and other commands pass.
# Holds kc-delegation §D1.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
guard="$(dirname "$tests_dir")/scripts/guard-batched-wait.sh"
require_jq

# Runs the guard on a <tool> call with <script> and an optional <timeout> parameter; prints deny or allow.
run_call() {
  local tool=$1 script=$2 timeout=${3:-} output
  output=$(jq -cn --arg tool "$tool" --arg script "$script" --arg timeout "$timeout" '
    {hook_event_name: "PreToolUse", tool_name: $tool,
     tool_input: ({(if $tool == "REPL" then "code" else "command" end): $script} + (if $timeout == "" then {} else {timeout: ($timeout | tonumber)} end))}' | bash "$guard")
  printf '%s' "$output" > "$work_dir/last-output"
  if printf '%s' "$output" | grep -q '"permissionDecision":"deny"'; then echo deny; else echo allow; fi
}

expect_eq "§D1: one watch with no timeout set is allowed" allow "$(run_call Bash 'gh pr checks 140 --watch')"
expect_eq "§D1: one watch with a short timeout is allowed" allow "$(run_call Bash 'gh pr checks 140 --watch' 120000)"
expect_eq "§D1: a run watch at the limit is allowed" allow "$(run_call Bash 'gh run watch 123' 600000)"
expect_eq "§D1: two watches chained are denied" deny "$(run_call Bash 'gh pr checks 140 --watch && gh pr checks 141 --watch')"
expect_contains "the denial says to poll each result on its own" "Poll each result on its own with a short timeout" "$(cat "$work_dir/last-output")"
expect_eq "a pr watch and a run watch together are denied" deny "$(run_call Bash 'gh pr checks 140 --watch; gh run watch 123')"
expect_eq "two watches in Promise.all are denied" deny "$(run_call REPL 'await Promise.all([$`gh pr checks 140 --watch`, $`gh pr checks 141 --watch`])')"
expect_eq "one watch in a REPL script with a short timeout is allowed" allow "$(run_call REPL 'await $`gh pr checks 140 --watch`.timeout(120000)')"
expect_eq "a watch past 10 minutes by the call's timeout is denied" deny "$(run_call Bash 'gh pr checks 140 --watch' 1500000)"
expect_contains "the denial names the long timeout" "over 10 minutes" "$(cat "$work_dir/last-output")"
expect_eq "a watch past 10 minutes by .timeout(n) is denied" deny "$(run_call REPL 'await $`gh run watch 123`.timeout(1_500_000)')"
expect_eq "a REPL watch with a call timeout past 10 minutes is denied" deny "$(run_call REPL 'await $`gh run watch 123`' 900000)"
expect_eq "two checks without --watch are allowed" allow "$(run_call Bash 'gh pr checks 140 && gh pr checks 141')"
expect_eq "a long timeout on a non-CI command is allowed" allow "$(run_call Bash 'bundle exec rspec' 1500000)"
expect_eq "two test runs in one script are untouched" allow "$(run_call REPL 'await Promise.all([$`npm test`, $`cargo test`])')"
expect_eq "an empty payload prints nothing" "" "$(printf '{}' | bash "$guard")"

finish
