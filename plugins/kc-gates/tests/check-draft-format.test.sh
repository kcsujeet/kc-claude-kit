#!/usr/bin/env bash
# Tests scripts/check-draft-format.sh with drafts shaped like real review comments: the slips
# kc-post-review's checklist exists for, and the drafts it allows.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
check="$(dirname "$tests_dir")/scripts/check-draft-format.sh"
require_jq

# Writes one draft with <body> to <file>, plus the fields of the jq object <extra> (default: an
# "n/a" run record, which an issue or suggestion needs).
draft() {
  local file=$1 body=$2 extra=${3:-'{ran: "cart spec with an empty cart: fails before, passes after"}'}
  jq -n --arg body "$body" "[{path: \"src/cart/total.ts\", line: 12, body: \$body} + $extra]" > "$file"
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
draft "$work_dir/long-ok.json" "$long_body" '{ran: "checkout spec with the provider stubbed down: two charges", long: "explains a double charge the author cannot see from the diff"}'
expect_eq "four sentences with a stated reason in \"long\" are clean" clean "$(result "$work_dir/long-ok.json")"

# --- an issue is reproduced, and a screen is seen (kc-post-review §PC4) ------------------------
draft "$work_dir/issue-na.json" $'**issue**:\nAn empty cart still shows the old total.' '{ran: "n/a: asks for an outcome and its test"}'
expect_contains "§PC4: an issue whose \"ran\" is n/a is flagged" "is an issue with \"ran\": n/a" "$(result "$work_dir/issue-na.json")"
draft "$work_dir/suggestion-na.json" $'**suggestion**:\nThis could read `visibleItems` like the list does.' '{ran: "n/a: no behaviour change"}'
expect_eq "§PC4: a suggestion may still say n/a with a reason" clean "$(result "$work_dir/suggestion-na.json")"

write_rendered_file_draft() {
  local extra=${4:-'{}'}
  jq -n --arg body "$2" --arg path "$3" --argjson extra "$extra" \
    '[{path: $path, line: 12, body: $body, ran: "n/a: layout only"} + $extra]' > "$1"
}
ui_body=$'**suggestion**:\nThe price wraps under the button on a narrow screen. Keeping them on one row would match the list.'
write_rendered_file_draft "$work_dir/ui-unseen.json" "$ui_body" "src/storefront/OrderRow.tsx"
expect_contains "§PC4: a draft on a component with no \"seen\" is flagged" "is on a screen with no \"seen\"" "$(result "$work_dir/ui-unseen.json")"
for path in src/storefront/order.html.erb src/storefront/order.vue src/storefront/order.scss; do
  write_rendered_file_draft "$work_dir/ui-other.json" "$ui_body" "$path"
  expect_contains "§PC4: a draft on $path with no \"seen\" is flagged" "no \"seen\"" "$(result "$work_dir/ui-other.json")"
done
write_rendered_file_draft "$work_dir/ui-missing.json" "$ui_body" "src/storefront/OrderRow.tsx" "{\"seen\": \"$work_dir/nope.png\"}"
expect_contains "§PC4: a \"seen\" file that does not exist is flagged" "is not a screenshot or recording that exists" "$(result "$work_dir/ui-missing.json")"
printf 'x' > "$work_dir/notes.txt"
write_rendered_file_draft "$work_dir/ui-text.json" "$ui_body" "src/storefront/OrderRow.tsx" "{\"seen\": \"$work_dir/notes.txt\"}"
expect_contains "§PC4: a \"seen\" that is not an image or video is flagged" "is not a screenshot or recording" "$(result "$work_dir/ui-text.json")"
printf 'png' > "$work_dir/order-row.png"
write_rendered_file_draft "$work_dir/ui-seen.json" "$ui_body" "src/storefront/OrderRow.tsx" "{\"seen\": \"$work_dir/order-row.png\"}"
expect_eq "§PC4: a draft on a component with a capture is clean" clean "$(result "$work_dir/ui-seen.json")"
write_rendered_file_draft "$work_dir/ui-test.json" "$ui_body" "src/storefront/OrderRow.test.tsx"
expect_eq "§PC4: a draft on a test file needs no \"seen\"" clean "$(result "$work_dir/ui-test.json")"
write_rendered_file_draft "$work_dir/ui-question.json" $'**question**:\nIs the row meant to wrap here?' "src/storefront/OrderRow.tsx"
expect_eq "§PC4: a question on a component needs no \"seen\"" clean "$(result "$work_dir/ui-question.json")"

write_rendered_file_draft "$work_dir/ui-list.json" "$ui_body" "src/storefront/OrderRow.tsx" '{"seen": ["order-row.png"]}'
expect_contains "§PC4: a \"seen\" that is not a path is flagged" "no \"seen\"" "$(result "$work_dir/ui-list.json")"

# A capture older than the head commit shows older code.
repo="$work_dir/repo"; git init -q "$repo"
git -C "$repo" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m one
sha=$(git -C "$repo" rev-parse HEAD)
touch -t 200001010000 "$work_dir/old.png"
write_rendered_file_draft "$work_dir/ui-old.json" "$ui_body" "src/storefront/OrderRow.tsx" "{\"seen\": \"$work_dir/old.png\"}"
old_capture_problems=$(cd "$repo" && bash "$check" "$work_dir/ui-old.json" "$sha" || true)
expect_contains "§PC4: a capture older than the head commit is flagged" "captured before the head commit" "$old_capture_problems"
touch "$work_dir/order-row.png"
fresh_capture_result=$(cd "$repo" && bash "$check" "$work_dir/ui-seen.json" "$sha" && echo clean || true)
expect_eq "§PC4: a capture newer than the head commit is clean" clean "$fresh_capture_result"
unknown_head_result=$(cd "$repo" && bash "$check" "$work_dir/ui-old.json" 0000000000000000000000000000000000000000 && echo clean || true)
expect_eq "§PC4: a head the repo doesn't know skips the age check" clean "$unknown_head_result"

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

# A comment carries at most two lines of code (kc-post-review §PC1).
three_line_fix=$'**issue**:\nAn empty cart still shows the old total, since nothing resets it.\n```ts\nif (items.length === 0) {\n  return 0\n}\n```'
draft "$work_dir/long-code.json" "$three_line_fix"
expect_contains "three lines of code are flagged" "has 3 lines of code" "$(result "$work_dir/long-code.json")"
jq '.[0].code = "the author asked for the code"' "$work_dir/long-code.json" > "$work_dir/long-code-ok.json"
expect_eq "three lines of code with a reason in \"code\" are clean" clean "$(result "$work_dir/long-code-ok.json")"
draft "$work_dir/two-blocks.json" $'**suggestion**:\nThe two totals could share one sum.\n```ts\nconst total = sum(items)\n```\nAnd here.\n```ts\nconst shown = sum(items)\n\nconst kept = sum(items)\n```'
expect_contains "code lines are counted across blocks, blank lines left out" "has 3 lines of code" "$(result "$work_dir/two-blocks.json")"

# A change asked for in a review is run before it is asked for (kc-post-review §PC2, correctness
# §B15, verification §V8): an issue or suggestion carries a "ran" record.
run_fix=$'**issue**:\nA stored draft opened before the storefront list loads gets the footer twice. Could the swap run only when the person picks another storefront?'
draft "$work_dir/no-ran.json" "$run_fix" '{}'
expect_contains "an issue with no \"ran\" is flagged" "asks for a change with no \"ran\"" "$(result "$work_dir/no-ran.json")"
draft "$work_dir/no-ran-suggestion.json" $'**suggestion (non-blocking):**\nCould the fallback apply only to saved store credit?' '{}'
expect_contains "a suggestion with no \"ran\" is flagged, in either label layout" "asks for a change with no \"ran\"" "$(result "$work_dir/no-ran-suggestion.json")"
draft "$work_dir/blank-ran.json" "$run_fix" '{ran: "  "}'
expect_contains "a blank \"ran\" is flagged" "asks for a change with no \"ran\"" "$(result "$work_dir/blank-ran.json")"
draft "$work_dir/bare-na.json" "$run_fix" '{ran: "n/a"}'
expect_contains "\"ran\": n/a with no reason is flagged" "n/a with no reason" "$(result "$work_dir/bare-na.json")"
draft "$work_dir/ran.json" "$run_fix" '{ran: "applied on a scratch copy: new test for a draft opened before the list loads, and the suite, pass"}'
expect_eq "an issue with a run record is clean" clean "$(result "$work_dir/ran.json")"
draft "$work_dir/question-no-ran.json" $'**question:**\nIs the swap meant to run on the first pass too?' '{}'
expect_eq "a question needs no \"ran\"" clean "$(result "$work_dir/question-no-ran.json")"

printf 'not json' > "$work_dir/broken.json"
status=0
bash "$check" "$work_dir/broken.json" >/dev/null 2>&1 || status=$?
expect_eq "unreadable drafts exit 2" 2 "$status"

finish
