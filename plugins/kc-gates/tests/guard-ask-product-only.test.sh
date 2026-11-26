#!/usr/bin/env bash
# Tests scripts/guard-ask-product-only.sh: an AskUserQuestion is denied when its text, header or an
# option holds code or review jargon, or when its question does not begin with the kind of decision
# it is; a plain product, scope, irreversible or intent question passes. Needs jq.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
hook="$(dirname "$tests_dir")/scripts/guard-ask-product-only.sh"

# get_hook_verdict_for_question <question> [option label] [option description] [header]: runs the hook; prints denied or allowed.
get_hook_verdict_for_question() {
  local output
  output=$(jq -cn --arg q "$1" --arg l "${2:-Yes}" --arg d "${3:-Keeps the current behaviour}" --arg h "${4:-Decision}" \
    '{hook_event_name: "PreToolUse", tool_name: "AskUserQuestion", tool_input: {questions: [{question: $q, header: $h, multiSelect: false, options: [{label: $l, description: $d}, {label: "No", description: "Changes it"}]}]}}' | bash "$hook")
  if [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision // empty')" = deny ]; then
    printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason' > "$work_dir/reason"
    echo denied
  elif [ -z "$output" ]; then echo allowed
  else echo "unexpected output"; fi
}

expect_eq "a plain product question passes" allowed "$(get_hook_verdict_for_question "Product: should the closed storefront of a shop still list its orders?")"
expect_eq "a scope question passes" allowed "$(get_hook_verdict_for_question "Scope: the fix also changes the receipt page you did not mention. Include it?")"
expect_eq "an irreversible question passes" allowed "$(get_hook_verdict_for_question "Irreversible: delete the 40 archived orders now?")"
expect_eq "an intent question passes" allowed "$(get_hook_verdict_for_question "Intent: by 'refund' do you mean money back or store credit?")"
expect_eq "the kind is matched in any case" allowed "$(get_hook_verdict_for_question "product: should guests see prices?")"

expect_eq "a question with no kind is denied" denied "$(get_hook_verdict_for_question "Should guests see prices?")"
expect_contains "the no-kind reason names the kinds and the way out" "fewest moving parts" "$(cat "$work_dir/reason")"
expect_eq "a kind word not at the start is denied" denied "$(get_hook_verdict_for_question "Should guests see prices? Product call.")"

expect_eq "a backtick in the question is denied" denied "$(get_hook_verdict_for_question "Product: keep \`MAX_ITEMS\` at 50?")"
expect_contains "the jargon reason says the choice is the agent's" "is yours" "$(cat "$work_dir/reason")"
expect_eq "a file path is denied" denied "$(get_hook_verdict_for_question "Scope: move the helper to app/orders/totals.rb?")"
expect_eq "a bare file name is denied" denied "$(get_hook_verdict_for_question "Scope: should the spec live in totals.test.ts?")"
expect_eq "a section id is denied" denied "$(get_hook_verdict_for_question "Product: does §G5 apply to the receipt?")"
expect_eq "a skill name is denied" denied "$(get_hook_verdict_for_question "Product: kc-code-review wants a different label. Change it?")"
expect_eq "jargon in an option label is denied" denied "$(get_hook_verdict_for_question "Product: should guests see prices?" "Use kc-naming")"
expect_eq "jargon in an option description is denied" denied "$(get_hook_verdict_for_question "Product: should guests see prices?" "Yes" "Matches src/prices.ts")"
expect_eq "jargon in the header is denied" denied "$(get_hook_verdict_for_question "Product: should guests see prices?" "Yes" "Shows prices" "kc-header")"
expect_eq "a plain word like gateway is not jargon" allowed "$(get_hook_verdict_for_question "Product: should the payment gateway name show on the receipt?")"
expect_eq "a gate name is denied" denied "$(get_hook_verdict_for_question "Product: the naming gate and the clarity gate disagree. Which wins?")"
expect_eq "a leading-slash path is denied" denied "$(get_hook_verdict_for_question "Scope: should it live under ~/notes?")"
expect_eq "a review-conventions mention is denied" denied "$(get_hook_verdict_for_question "Scope: record this in review-conventions?")"
expect_eq "ordinary words gate, finding and checklist are allowed" allowed "$(get_hook_verdict_for_question "Product: which kind of gate should the checklist feature go behind, with a finding count?")"
expect_eq "a kind on a later line does not count" denied "$(get_hook_verdict_for_question "$(printf 'Should we refactor the helper?\nProduct: ok')")"

output=$(printf '%s' '{"tool_name":"AskUserQuestion","tool_input":{}}' | bash "$hook")
expect_eq "a payload with no questions is ignored" "" "$output"

finish
