#!/usr/bin/env bash
# Tests scripts/check-draft-format.sh with drafts shaped like real review comments: the slips
# kc-post-review's checklist exists for, and the drafts it allows.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
check="$(dirname "$tests_dir")/scripts/check-draft-format.sh"
require_jq

# Writes one draft with <body> (and an optional "long" reason) to <file>.
draft() {
  local file=$1 body=$2 long=${3:-}
  if [ -n "$long" ]; then
    jq -n --arg body "$body" --arg long "$long" '[{path: "src/cart/total.ts", line: 12, body: $body, long: $long}]' > "$file"
  else
    jq -n --arg body "$body" '[{path: "src/cart/total.ts", line: 12, body: $body}]' > "$file"
  fi
}

# Runs the check on <file>; prints its output, or "clean" when it passes.
result() {
  local output status=0
  output=$(bash "$check" "$1") || status=$?
  if [ "$status" -eq 0 ]; then echo clean; else printf '%s\n' "$output"; fi
}

# --- drafts the rules allow ------------------------------------------------------------------
draft "$work_dir/suggestion.json" $'**suggestion**:\nThis total skips archived items, but the list above shows them. Could it use `visibleItems` like the list does?\n```ts\nconst total = sum(visibleItems(cart))\n```'
expect_eq "a labelled two-sentence suggestion with a code block is clean" clean "$(result "$work_dir/suggestion.json")"

draft "$work_dir/nitpick.json" $'**nitpick** (non-blocking):\n`data` could say what it holds, like `openOrders`.'
expect_eq "a decorated nitpick is clean" clean "$(result "$work_dir/nitpick.json")"

draft "$work_dir/cc-layout.json" $'**suggestion (non-blocking):**\nCould this read `visibleItems` like the list does?'
expect_eq "the Conventional Comments layout the skill's examples use is clean" clean "$(result "$work_dir/cc-layout.json")"

long_body=$'**issue**:\nThis retries forever when the payment provider is down. Each retry opens a new charge attempt. A customer can be charged twice if the first one lands late. The provider docs say to reuse the idempotency key on retries.'
draft "$work_dir/long-ok.json" "$long_body" "explains a double charge the author can't see from the diff"
expect_eq "four sentences with a stated reason in \"long\" are clean" clean "$(result "$work_dir/long-ok.json")"

# --- slips the checklist exists for ---------------------------------------------------------
draft "$work_dir/no-label.json" 'Good catch on the rounding. Could this use the shared formatter?'
no_label=$(result "$work_dir/no-label.json")
expect_contains "no label line is flagged" "draft 1 (src/cart/total.ts:12): the first line is not a label" "$no_label"

draft "$work_dir/praise.json" $'**suggestion**:\nGood catch, but this also needs the archived filter.'
expect_contains "a praise opener after the label is flagged" "opens with praise" "$(result "$work_dir/praise.json")"

draft "$work_dir/em-dash.json" $'**suggestion**:\nThe count skips archived items — the list shows them.'
expect_contains "an em dash is flagged" "has an em dash" "$(result "$work_dir/em-dash.json")"

draft "$work_dir/rule-id.json" $'**issue**:\nThis breaks §T1: the new branch has no test.'
expect_contains "a rule citation is flagged" "cites a rule with" "$(result "$work_dir/rule-id.json")"

draft "$work_dir/blocking.json" $'**issue** (blocking):\nThe new branch has no test.'
blocking=$(result "$work_dir/blocking.json")
expect_contains "the (blocking) decoration is flagged" "uses the (blocking) decoration" "$blocking"

draft "$work_dir/emoji.json" $'**praise**:\nThis lookup reads much better than the switch 👍'
expect_contains "an emoji is flagged" "has an emoji" "$(result "$work_dir/emoji.json")"

draft "$work_dir/long.json" "$long_body"
expect_contains "four sentences with no reason are flagged" "has 4 sentences" "$(result "$work_dir/long.json")"

draft "$work_dir/run-on.json" $'**suggestion**:\nSince the total is computed before the archived filter runs and the list applies that filter after loading every item from the cart service the two numbers drift apart whenever anything is archived.'
expect_contains "a sentence over 25 words is flagged" "word sentence" "$(result "$work_dir/run-on.json")"

three_line_fix=$'**issue**:\nAn empty cart still shows the old total, since nothing resets it.\n```ts\nif (items.length === 0) {\n  return 0\n}\n```'
draft "$work_dir/long-code.json" "$three_line_fix"
expect_contains "three lines of code are flagged" "has 3 lines of code" "$(result "$work_dir/long-code.json")"
jq '.[0].code = "the author asked for the code"' "$work_dir/long-code.json" > "$work_dir/long-code-ok.json"
expect_eq "three lines of code with a reason in \"code\" are clean" clean "$(result "$work_dir/long-code-ok.json")"
draft "$work_dir/two-blocks.json" $'**suggestion**:\nThe two totals could share one sum.\n```ts\nconst total = sum(items)\n```\nAnd here.\n```ts\nconst shown = sum(items)\n\nconst kept = sum(items)\n```'
expect_contains "code lines are counted across blocks, blank lines left out" "has 3 lines of code" "$(result "$work_dir/two-blocks.json")"

printf 'not json' > "$work_dir/broken.json"
status=0
bash "$check" "$work_dir/broken.json" >/dev/null 2>&1 || status=$?
expect_eq "unreadable drafts exit 2" 2 "$status"

finish
