#!/usr/bin/env bash
# Tests scripts/guard-ask-product-only.sh: an AskUserQuestion is denied when its text, header or an
# option holds code or review jargon, or when its question does not begin with the kind of decision
# it is; a plain product, scope, irreversible or intent question passes. Needs jq.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
hook="$(dirname "$tests_dir")/scripts/guard-ask-product-only.sh"

# ask <question> [option label] [option description] [header]: runs the hook; prints denied or allowed.
ask() {
  local output
  output=$(jq -cn --arg q "$1" --arg l "${2:-Yes}" --arg d "${3:-Keeps the current behaviour}" --arg h "${4:-Decision}" \
    '{hook_event_name: "PreToolUse", tool_name: "AskUserQuestion", tool_input: {questions: [{question: $q, header: $h, multiSelect: false, options: [{label: $l, description: $d}, {label: "No", description: "Changes it"}]}]}}' | bash "$hook")
  if [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision // empty')" = deny ]; then
    printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason' > "$work_dir/reason"
    echo denied
  elif [ -z "$output" ]; then echo allowed
  else echo "unexpected output"; fi
}

expect_eq "a plain product question passes" allowed "$(ask "Product: should the closed storefront of a shop still list its orders?")"
expect_eq "a scope question passes" allowed "$(ask "Scope: the fix also changes the receipt page you did not mention. Include it?")"
expect_eq "an irreversible question passes" allowed "$(ask "Irreversible: delete the 40 archived orders now?")"
expect_eq "an intent question passes" allowed "$(ask "Intent: by 'refund' do you mean money back or store credit?")"
expect_eq "the kind is matched in any case" allowed "$(ask "product: should guests see prices?")"

expect_eq "a question with no kind is denied" denied "$(ask "Should guests see prices?")"
expect_contains "the no-kind reason names the kinds and the way out" "fewest moving parts" "$(cat "$work_dir/reason")"
expect_eq "a kind word not at the start is denied" denied "$(ask "Should guests see prices? Product call.")"

expect_eq "a backtick in the question is denied" denied "$(ask "Product: keep \`MAX_ITEMS\` at 50?")"
expect_contains "the jargon reason says the choice is the agent's" "is yours" "$(cat "$work_dir/reason")"
expect_eq "a file path is denied" denied "$(ask "Scope: move the helper to app/orders/totals.rb?")"
expect_eq "a bare file name is denied" denied "$(ask "Scope: should the spec live in totals.test.ts?")"
expect_eq "a section id is denied" denied "$(ask "Product: does §G5 apply to the receipt?")"
expect_eq "a skill name is denied" denied "$(ask "Product: kc-code-review wants a different label. Change it?")"
expect_eq "the word gate is denied" denied "$(ask "Product: the naming gate and the clarity gate disagree. Which wins?")"
expect_eq "the word finding is denied" denied "$(ask "Product: the finding about the deleted order: fix it?")"
expect_eq "a round number is denied" denied "$(ask "Scope: round 2 raised a new point. Apply it?")"
expect_eq "jargon in an option label is denied" denied "$(ask "Product: should guests see prices?" "Apply the checklist box")"
expect_eq "jargon in an option description is denied" denied "$(ask "Product: should guests see prices?" "Yes" "Matches src/prices.ts")"
expect_eq "jargon in the header is denied" denied "$(ask "Product: should guests see prices?" "Yes" "Shows prices" "Verdict")"
expect_eq "a plain word like fine or gateway is not jargon" allowed "$(ask "Product: should the payment gateway name show on the receipt?")"

# Other tools and a payload without questions are untouched.
output=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"ls"}}' | bash "$hook")
expect_eq "another tool is ignored" "" "$output"
output=$(printf '%s' '{"tool_name":"AskUserQuestion","tool_input":{}}' | bash "$hook")
expect_eq "a payload with no questions is ignored" "" "$output"

# Two questions: the second one's jargon denies the call.
output=$(jq -cn '{tool_name: "AskUserQuestion", tool_input: {questions: [{question: "Product: show prices?", options: [{label: "Yes"}]}, {question: "Product: keep `X`?", options: [{label: "Yes"}]}]}}' | bash "$hook")
expect_eq "any question in the call can deny it" deny "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision // empty')"

finish
