#!/usr/bin/env bash
# Tests scripts/remind-look-back-prompt.sh: a prompt saying a pull request was merged or approved
# gets the look-back reminder; one that negates it, puts it in the future, or says something else
# gets nothing. Each case runs twice, once with jq and once through the sed fallback.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
hook="$(dirname "$tests_dir")/scripts/remind-look-back-prompt.sh"

# Wraps a prompt in the UserPromptSubmit stdin payload, its quotes and backslashes escaped.
build_payload() {
  local prompt
  prompt=$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')
  printf '{"session_id":"s","hook_event_name":"UserPromptSubmit","prompt":"%s"}' "$prompt"
}

expect_prompt() {
  local expectation=$1 prompt=$2 mode output verdict
  for mode in jq sed; do
    if [ "$mode" = jq ] && ! command -v jq >/dev/null 2>&1; then
      continue
    fi
    if [ "$mode" = sed ]; then
      output=$(build_payload "$prompt" | KC_GUARD_NO_JQ=1 bash "$hook")
    else
      output=$(build_payload "$prompt" | bash "$hook")
    fi
    if [ -z "$output" ]; then
      verdict=quiet
    elif printf '%s' "$output" | grep -q '"hookEventName":"UserPromptSubmit","additionalContext":"kc-gates: the person says a pull request was merged or approved'; then
      verdict=remind
    else
      verdict="unexpected output: $output"
    fi
    expect_eq "[$mode] $expectation: $prompt" "$expectation" "$verdict"
  done
}

# --- the person says it happened -----------------------------------------------------------------
expect_prompt remind "the PR has been merged"
expect_prompt remind "The PR has been merged, please clean up the branch."
expect_prompt remind "PR approved"
expect_prompt remind "pr #12 was approved by Sam"
expect_prompt remind "Pull request 12 is merged now"
expect_prompt remind "merged it"
expect_prompt remind "I merged it just now"
expect_prompt remind "it's approved"
expect_prompt remind "it’s merged"
expect_prompt remind "the review is approved"
expect_prompt remind "they approved the PR this morning"
expect_prompt remind "Thanks. The pull request got merged overnight."
expect_prompt remind "this was merged"

# --- not yet, or not about a pull request --------------------------------------------------------
expect_prompt quiet "the PR is not merged yet"
expect_prompt quiet "the PR isn't approved"
expect_prompt quiet "wait until the PR is merged"
expect_prompt quiet "before it's merged, rebase"
expect_prompt quiet "once the PR is approved, merge it"
expect_prompt quiet "if it's approved we ship"
expect_prompt quiet "when the PR has been merged, tell me"
expect_prompt quiet "after the PR is merged run the look back"
expect_prompt quiet "never merged the PR"
expect_prompt quiet "I approved the plan"
expect_prompt quiet "The design was approved last week"
expect_prompt quiet "note the PR needs a rebase"
expect_prompt quiet "Fix the failing test"
expect_prompt quiet "merge conflicts in the branch"
expect_prompt quiet ""

# --- the reminder's text -------------------------------------------------------------------------
reminder=$(build_payload "the PR has been merged" | bash "$hook")
expect_contains "the reminder points to step 6" "Order of work on a task, step 6" "$reminder"
expect_contains "the reminder says to list the feedback with the ledger" "feedback-ledger.sh list" "$reminder"
expect_contains "the reminder says it stays on the task list until the ledger check passes" "stays on the visible task list until feedback-ledger.sh check passes" "$reminder"
expect_contains "the reminder says an earlier look-back does not cover later feedback" "does not cover feedback that arrived after it" "$reminder"
if command -v jq >/dev/null 2>&1; then
  expect_eq "the reminder is valid JSON with additionalContext" "UserPromptSubmit" "$(printf '%s' "$reminder" | jq -r '.hookSpecificOutput.hookEventName')"
fi

finish
