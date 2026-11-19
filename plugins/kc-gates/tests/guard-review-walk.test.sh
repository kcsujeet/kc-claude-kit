#!/usr/bin/env bash
# Tests scripts/guard-review-walk.sh: while the saved review's walk receipt fails, the verification
# gate's dispatch is denied and a reply giving a verdict is blocked; a full receipt, a diff with
# nothing to walk, a reply with no verdict and any other tool call pass.
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

verdict_reply=$'### Review: Add free shipping\n**Head:** `abc1234` · **Verdict:** ❌ FAILED (2 gates failing)'
passed_reply=$'**Verdict:** ✅ PASSED'
clean_reply=$'### Review: Add free shipping\n`abc1234` `cart.ts`: follows existing conventions and naming. No changes.'
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

printf 'app/models/order.rb\tcreated an order with a free item\tno evidence\n' > "$review/walk-receipt.tsv"
expect_eq "a receipt line with no evidence: verdict held" held "$(run_stop "$verdict_reply")"

printf 'app/models/order.rb\tcreated an order with a free item, total 0\tPOST /orders 201\n' > "$review/walk-receipt.tsv"
expect_eq "full receipt: the verdict goes out" out "$(run_stop "$verdict_reply")"
expect_eq "full receipt: the verification gate dispatches" allow "$(run_dispatch kc-gates:verification-gate)"

write_review docs/notes.md
rm -f "$review/walk-receipt.tsv"
expect_eq "nothing to walk: the verdict goes out with no receipt" out "$(run_stop "$verdict_reply")"

rm -rf "$review"
expect_eq "no saved review: the verdict goes out" out "$(run_stop "$verdict_reply")"

write_review app/models/order.rb
other=$work_dir/other-review
mkdir -p "$other"
cp "$review/review.diff" "$review/changed-files.txt" "$other/"
printf 'app/models/order.rb\tcreated an order\tPOST /orders 201\n' > "$other/walk-receipt.tsv"
expect_eq "KC_REVIEW_DIR names the review to check" out "$(KC_REVIEW_DIR=$other run_stop "$verdict_reply")"

finish
