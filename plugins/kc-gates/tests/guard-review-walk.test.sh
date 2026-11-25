#!/usr/bin/env bash
# Tests scripts/guard-review-walk.sh: while the saved review's walk receipt fails, the verification
# gate's dispatch is denied and a reply giving a verdict is blocked; a full receipt, a diff with
# nothing to walk, a reply that offers the walk as a question is blocked, a reply with no verdict and any other tool call pass.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
guard="$(dirname "$tests_dir")/scripts/guard-review-walk.sh"
require_jq

# Only this test's saved reviews may be found.
TMPDIR=$work_dir/tmp
mkdir -p "$TMPDIR"
export TMPDIR
review=$TMPDIR/kc-review-abc123
cd "$work_dir"

# Saves a review the way gather-review.sh does, changing <path>.
write_review() {
  mkdir -p "$review"
  printf -- '--- a/%s\n+++ b/%s\n@@ -0,0 +1 @@\n+x\n' "$1" "$1" > "$review/review.diff"
  printf '%s\n' "$1" > "$review/changed-files.txt"
  printf 'HEAD_SHA=abc123\nPR=12\nURL=https://github.com/acme/shop/pull/12\n' > "$review/meta.env"
}

# Runs the guard on a Stop payload with <reply>; prints held or out, and keeps its output in
# $work_dir/last-output (the runs are in command substitutions, so a variable would not survive).
run_stop() {
  local active=${2:-false} output
  output=$(jq -cn --arg reply "$1" --argjson active "$active" '{session_id: "s", hook_event_name: "Stop", stop_hook_active: $active, last_assistant_message: $reply}' | bash "$guard")
  printf '%s' "$output" > "$work_dir/last-output"
  if printf '%s' "$output" | grep -q '"decision":"block"'; then echo held; else echo out; fi
}

# Runs the guard on a PreToolUse Agent payload for <subagent_type>; prints deny or allow.
run_dispatch() {
  local output
  output=$(jq -cn --arg type "$1" '{session_id: "s", hook_event_name: "PreToolUse", tool_name: "Agent", tool_input: {subagent_type: $type, prompt: "x", description: "x"}}' | bash "$guard")
  printf '%s' "$output" > "$work_dir/last-output"
  if printf '%s' "$output" | grep -q '"permissionDecision":"deny"'; then echo deny; else echo allow; fi
}

works_section=$'**Does it work / what can it break**\n- Measured: checkout query before 420 ms -> after 38 ms.\n- Uses: 4 traced, 3 run, 1 read.\n'
verdict_reply=$'### Review: Add free shipping\n**Head:** `abc1234` · **Verdict:** ❌ FAILED (2 gates failing)\n'"$works_section"$'\n**Gate status:**\n| Gate | Status |\n|------|--------|\n| naming | ❌ FAIL |\n\n**Naming:**\n- 🟡 `cart.ts:L4`: `tmp` is opaque. Rename `total`. (non-blocking)'
passed_reply=$'**Verdict:** ✅ PASSED'
clean_reply=$'### Review: Add free shipping\n'"$works_section"$'`abc1234` `cart.ts`: follows existing conventions and naming. No changes.'
failed_line_reply=$'Round 2 · **Verdict:** ❌ FAILED (1 gate failing)'
unfinished_reply="The review is not finished: app/models/order.rb is not walked yet; it needs the app running."

write_review app/models/order.rb
rm -f "$review/walk-receipt.tsv"
expect_eq "no receipt: a FAILED verdict is held" held "$(run_stop "$verdict_reply")"
expect_contains "the block names the unwalked item" "walk-item app/models/order.rb" "$(cat "$work_dir/last-output")"
expect_contains "the block gives the way out when the walk can't run" "reply without a verdict" "$(cat "$work_dir/last-output")"
expect_eq "no receipt: a FAILED verdict line with no heading is held" held "$(run_stop "$failed_line_reply")"
expect_eq "no receipt: a PASSED verdict is held" held "$(run_stop "$passed_reply")"
expect_eq "no receipt: the one-line clean report is held" held "$(run_stop "$clean_reply")"
expect_eq "no receipt: held again on the second try" held "$(run_stop "$verdict_reply" true)"
expect_eq "no receipt: a reply with no verdict goes out" out "$(run_stop "$unfinished_reply")"
expect_eq "no receipt: the verification gate's dispatch is denied" deny "$(run_dispatch kc-gates:verification-gate)"
expect_contains "the denial says to walk first" "walk-receipt.tsv" "$(cat "$work_dir/last-output")"
expect_eq "no receipt: other gates still dispatch" allow "$(run_dispatch kc-gates:correctness-gate)"

offer_reply="The gates are done. Do you want me to walk it in the running app before I give the verdict?"
qa_offer_reply="Should I QA this change first?"
try_offer_reply="Want me to try it locally?"
expect_eq "no receipt: asking whether to walk it in the app is held" held "$(run_stop "$offer_reply")"
expect_contains "the block says the walk is required, not a choice" "requires that walk" "$(cat "$work_dir/last-output")"
expect_eq "no receipt: asking whether to QA it is held" held "$(run_stop "$qa_offer_reply")"
expect_eq "no receipt: asking whether to try it locally is held" held "$(run_stop "$try_offer_reply")"
expect_eq "no receipt: an unrelated question goes out" out "$(run_stop "Which gate do you want first?")"
expect_eq "no receipt: saying it will walk, with no question, goes out" out "$(run_stop "I will walk it in the running app now.")"

printf 'app/models/order.rb\tcreated an order with a free item\tno evidence\tstates: empty cart; two items\n' > "$review/walk-receipt.tsv"
expect_eq "a receipt line with no evidence: verdict held" held "$(run_stop "$verdict_reply")"

printf 'env\tbin/review-env up\tGET /health 200\napp/models/order.rb\tcreated an order with a free item, total 0\tPOST /orders 201\tstates: empty cart; two items\n' > "$review/walk-receipt.tsv"
expect_eq "full receipt: the verdict goes out" out "$(run_stop "$verdict_reply")"
expect_eq "full receipt: the verification gate dispatches" allow "$(run_dispatch kc-gates:verification-gate)"

write_review docs/notes.md
rm -f "$review/walk-receipt.tsv"
expect_eq "nothing to walk: the verdict goes out with no receipt" out "$(run_stop "$verdict_reply")"

expect_eq "full receipt: a question about the app goes out" out "$(run_stop "$offer_reply")"

rm -rf "$review"
expect_eq "no saved review: the verdict goes out" out "$(run_stop "$verdict_reply")"

# §G6: a verdict whose report does not lead with the does-it-work section, or leaves a style
# finding unlabeled, is blocked even with nothing to walk; a reply with no verdict is untouched.
bare_verdict=$'### Review: Add free shipping\n**Head:** `abc1234` · **Verdict:** ❌ FAILED (1 gate failing)\n\n**Naming:**\n- 🟡 `cart.ts:L4`: `tmp` is opaque. Rename `total`.'
expect_eq "§G6 no saved review: a verdict with no does-it-work section is held" held "$(run_stop "$bare_verdict")"
expect_contains "§G6 the block says what to add" "Does it work / what can it break" "$(cat "$work_dir/last-output")"
expect_contains "§G6 the block names the unlabeled finding" "without (non-blocking)" "$(cat "$work_dir/last-output")"
unlabeled_verdict=${verdict_reply%" (non-blocking)"}
expect_eq "§G6 no saved review: an unlabeled style finding is held" held "$(run_stop "$unlabeled_verdict")"
expect_eq "§G6 no saved review: a reply with no verdict is untouched" out "$(run_stop "$unfinished_reply")"
expect_eq "§G6 no saved review: an ordinary reply is untouched" out "$(run_stop "Which gate do you want first?")"

write_review app/models/order.rb
other=$work_dir/other-review
mkdir -p "$other"
cp "$review/review.diff" "$review/changed-files.txt" "$other/"
printf 'env\tbin/review-env up\tGET /health 200\napp/models/order.rb\tcreated an order\tPOST /orders 201\tstates: empty cart; two items\n' > "$other/walk-receipt.tsv"
expect_eq "KC_REVIEW_DIR names the review to check" out "$(KC_REVIEW_DIR=$other run_stop "$verdict_reply")"

# Confirmed findings stay in the report: with a verdicts/ folder in the review, a verdict reply that
# neither names a gate's finding (basename and line) nor lists it under Dropped: is blocked.
write_review docs/notes.md
mkdir -p "$review/verdicts"
# shellcheck disable=SC2016 # backticks in the fixture text are literal
printf 'STATUS: FAIL\nFINDINGS:\n- 🟡 src/cart.ts:L4: `tmp` is opaque. Rename `total`.\n- 🟠 src/orders/refund.ts:42@abc1234: skips archived orders.\n' > "$review/verdicts/naming.txt"
expect_eq "§G7 verdicts: a verdict that leaves out a confirmed finding is held" held "$(run_stop "$verdict_reply")"
expect_contains "§G7 verdicts: the block names the missing finding" "a gate found refund.ts:42 and the reply neither reports it nor lists it under Dropped: with a reason" "$(cat "$work_dir/last-output")"
expect_not_contains "§G7 verdicts: the block leaves out the finding the reply names" "a gate found cart.ts:4" "$(cat "$work_dir/last-output")"
expect_eq "§G7 verdicts: a reply naming both findings goes out" out "$(run_stop "$verdict_reply"$'\n- 🟠 `refund.ts:42`: skips archived orders. (non-blocking)')"
expect_eq "§G7 verdicts: a finding on a Dropped: line goes out" out "$(run_stop "$verdict_reply"$'\nDropped: refund.ts:42 (the author already fixed it)')"
expect_eq "§G7 verdicts: a reply with no verdict is untouched" out "$(run_stop "$unfinished_reply")"
bare_with_findings=$bare_verdict
both_output=$(run_stop "$bare_with_findings")
expect_eq "§G7 verdicts: a reply with a report problem and a missing finding is held" held "$both_output"
expect_contains "§G7 verdicts: the block holds the report problem" "Does it work / what can it break" "$(cat "$work_dir/last-output")"
expect_contains "§G7 verdicts: the block holds the missing finding too" "a gate found refund.ts:42 and the reply neither reports it nor lists it under Dropped: with a reason" "$(cat "$work_dir/last-output")"
expect_not_contains "§G7 verdicts: a reply with no Dropped: reason is not excused" "a gate found cart.ts:4" "$(cat "$work_dir/last-output")"
expect_eq "§G7 verdicts: Dropped: with only file:line and no reason is held" held "$(run_stop "$verdict_reply"$'\nDropped: refund.ts:42')"
# A folder with verdicts but no saved review (no review.diff) is not a review to check.
verdicts_only=$work_dir/verdicts-only
mkdir -p "$verdicts_only/verdicts"
cp "$review/verdicts/naming.txt" "$verdicts_only/verdicts/"
expect_eq "§G7 verdicts: a folder with no review files is not checked" out "$(KC_REVIEW_DIR=$verdicts_only run_stop "$verdict_reply")"
rm -rf "$review/verdicts"
expect_eq "§G7 verdicts: no verdicts folder, nothing to check" out "$(run_stop "$verdict_reply")"

finish
