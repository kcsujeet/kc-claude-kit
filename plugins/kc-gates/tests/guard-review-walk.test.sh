#!/usr/bin/env bash
# Tests scripts/guard-review-walk.sh (PreToolUse on Agent): while the saved review's walk receipt
# fails, the verification gate's dispatch is denied; a full receipt, a diff with nothing to walk,
# another gate and any other tool call pass. It is not a Stop hook: a reply is never blocked here,
# because by then the person has read it (a Stop payload prints nothing).
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
# The session runs in a checkout that holds the review's head commit.
repo_dir=$work_dir/repo
mkdir -p "$repo_dir"
git -C "$repo_dir" init -q
git -C "$repo_dir" -c user.name=t -c user.email=t@example.test commit -q --allow-empty -m base
head_sha=$(git -C "$repo_dir" rev-parse HEAD)
cd "$repo_dir"

# Saves a review the way gather-review.sh does, changing <path>.
write_review() {
  mkdir -p "$review"
  printf -- '--- a/%s\n+++ b/%s\n@@ -0,0 +1 @@\n+x\n' "$1" "$1" > "$review/review.diff"
  printf '%s\n' "$1" > "$review/changed-files.txt"
  printf 'HEAD_SHA=%s\nPR=12\nURL=https://github.com/acme/shop/pull/12\n' "$head_sha" > "$review/meta.env"
}

# Runs the guard on a PreToolUse Agent payload for <subagent_type>; prints deny or allow.
run_dispatch() {
  local output
  output=$(jq -cn --arg type "$1" '{session_id: "s", hook_event_name: "PreToolUse", tool_name: "Agent", tool_input: {subagent_type: $type, prompt: "x", description: "x"}}' | bash "$guard")
  printf '%s' "$output" > "$work_dir/last-output"
  if printf '%s' "$output" | grep -q '"permissionDecision":"deny"'; then echo deny; else echo allow; fi
}

write_review app/models/order.rb
rm -f "$review/walk-receipt.tsv"
expect_eq "no receipt: the verification gate's dispatch is denied" deny "$(run_dispatch kc-gates:verification-gate)"
expect_contains "the denial names the unwalked item" "walk-item app/models/order.rb" "$(cat "$work_dir/last-output")"
expect_contains "the denial says to walk first" "walk-receipt.tsv" "$(cat "$work_dir/last-output")"
expect_eq "no receipt: other gates still dispatch" allow "$(run_dispatch kc-gates:correctness-gate)"
expect_eq "no receipt: a Stop payload with a verdict prints nothing" "" "$(jq -cn '{session_id: "s", hook_event_name: "Stop", last_assistant_message: "### Review: x\n**Verdict:** PASSED"}' | bash "$guard")"
expect_eq "no receipt: a Bash call is not held" allow "$(jq -cn '{session_id: "s", hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: "ls"}}' | bash "$guard" | grep -q deny && echo deny || echo allow)"

printf 'app/models/order.rb\tcreated an order with a free item\tno evidence\tstates: empty cart; two items\n' > "$review/walk-receipt.tsv"
expect_eq "a receipt line with no evidence: the dispatch is denied" deny "$(run_dispatch kc-gates:verification-gate)"

printf 'env\tbin/review-env up\tGET /health 200\napp/models/order.rb\tcreated an order with a free item, total 0\tPOST /orders 201\tstates: empty cart; two items\n' > "$review/walk-receipt.tsv"
expect_eq "full receipt: the verification gate dispatches" allow "$(run_dispatch kc-gates:verification-gate)"

write_review docs/notes.md
rm -f "$review/walk-receipt.tsv"
expect_eq "nothing to walk: the dispatch goes through with no receipt" allow "$(run_dispatch kc-gates:verification-gate)"

rm -rf "$review"
expect_eq "no saved review: the dispatch goes through" allow "$(run_dispatch kc-gates:verification-gate)"

write_review app/models/order.rb
other=$work_dir/other-review
mkdir -p "$other"
cp "$review/review.diff" "$review/changed-files.txt" "$other/"
printf 'env\tbin/review-env up\tGET /health 200\napp/models/order.rb\tcreated an order\tPOST /orders 201\tstates: empty cart; two items\n' > "$other/walk-receipt.tsv"
expect_eq "KC_REVIEW_DIR names the review to check" allow "$(KC_REVIEW_DIR=$other run_dispatch kc-gates:verification-gate)"

# Another session's review, gathered in another repo, never holds this session's dispatches.
rm -f "$review/walk-receipt.tsv"
other_repo=$work_dir/other-repo
mkdir -p "$other_repo"
git -C "$other_repo" init -q
expect_eq "another repo's unwalked review: the dispatch there goes through" allow "$(cd "$other_repo" && run_dispatch kc-gates:verification-gate)"
expect_eq "outside any checkout: the dispatch goes through" allow "$(cd "$work_dir" && run_dispatch kc-gates:verification-gate)"
expect_eq "the review's own repo: the dispatch is still denied" deny "$(run_dispatch kc-gates:verification-gate)"

finish
