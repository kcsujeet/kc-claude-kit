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
# "n/a" run record, which an issue or suggestion needs). Every draft carries "covered" unless
# <extra> overrides it.
draft() {
  local file=$1 body=$2 extra=${3:-'{ran: "cart spec with an empty cart: fails before, passes after", walked: "empty cart: 0 before, 0 after; cart with an archived item: counted before, skipped after"}'}
  jq -n --arg body "$body" "[{path: \"src/cart/total.ts\", line: 12, body: \$body, covered: \"read the description and the ticket: neither says how archived items count\"} + $extra]" > "$file"
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
draft "$work_dir/long-ok.json" "$long_body" '{ran: "checkout spec with the provider stubbed down: two charges", walked: "provider down: retries forever before, stops after; provider up: unchanged", long: "explains a double charge the author cannot see from the diff"}'
expect_eq "four sentences with a stated reason in \"long\" are clean" clean "$(result "$work_dir/long-ok.json")"

# --- an issue is reproduced, and a screen is seen (kc-post-review §PC4) ------------------------
draft "$work_dir/issue-na.json" $'**issue**:\nAn empty cart still shows the old total.' '{ran: "n/a: asks for an outcome and its test"}'
expect_contains "§PC4: an issue whose \"ran\" is n/a is flagged" "is an issue with \"ran\": n/a" "$(result "$work_dir/issue-na.json")"
draft "$work_dir/suggestion-na.json" $'**suggestion**:\nThis could read `visibleItems` like the list does.' '{ran: "n/a: no behaviour change", walked: "n/a: no behaviour change"}'
expect_eq "§PC4: a suggestion may still say n/a with a reason" clean "$(result "$work_dir/suggestion-na.json")"

write_rendered_file_draft() {
  local extra=${4:-'{}'}
  jq -n --arg body "$2" --arg path "$3" --argjson extra "$extra" \
    '[{path: $path, line: 12, body: $body, covered: "read the description: it says nothing about narrow screens", ran: "n/a: layout only", walked: "n/a: layout only"} + $extra]' > "$1"
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
printf 'webm' > "$work_dir/order-row.webm"
write_rendered_file_draft "$work_dir/ui-recording.json" "$ui_body" "src/storefront/OrderRow.tsx" "{\"seen\": \"$work_dir/order-row.webm\"}"
expect_eq "§PC4: a recording in the shared capture formats (webm) is clean" clean "$(result "$work_dir/ui-recording.json")"
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

# --- a draft is read by a person, and every claim in it was run (kc-post-review §PC5) -----------
draft "$work_dir/hard-word.json" $'**suggestion**:\nThe discount is ungated, so every caller sees it.'
expect_contains "§PC5: a hard word is flagged" 'uses the hard word "ungated"' "$(result "$work_dir/hard-word.json")"
for flow_word in "rerender" "re-render" "refetch" "fallbacks" "mid-edit" "early return" "short-circuits" "bails out"; do
  draft "$work_dir/flow-word.json" $'**suggestion**:\nThe total can '"$flow_word"$' when the cart changes.'
  expect_contains "§PC5: the code-flow word \"$flow_word\" is flagged" 'uses the hard word' "$(result "$work_dir/flow-word.json")"
done
draft "$work_dir/plain.json" $'**suggestion**:\nThe discount shows to everyone, guests included.'
expect_eq "§PC5: the same point in everyday words is clean" clean "$(result "$work_dir/plain.json")"
draft "$work_dir/test-ask.json" $'**todo**:\nA test that empties the cart would catch the old total.' '{}'
expect_contains "§PC5: asking for a test with no failing run is flagged" "asks for a test with no proof" "$(result "$work_dir/test-ask.json")"
draft "$work_dir/test-ask-ok.json" $'**todo**:\nA test that empties the cart would catch the old total.' '{ran: "wrote it; with the reset removed it failed, with it in place it passed"}'
expect_eq "§PC5: asking for a test that was seen to fail is clean" clean "$(result "$work_dir/test-ask-ok.json")"
draft "$work_dir/earlier.json" $'**question**:\nI was wrong last round about the totals. Do archived items count?' '{}'
expect_contains "§PC5: a claim about an earlier review with nothing run is flagged" "earlier review with nothing run" "$(result "$work_dir/earlier.json")"
draft "$work_dir/earlier-ok.json" $'**question**:\nI was wrong last round about the totals. Do archived items count?' '{ran: "cart spec with an archived item: the total leaves it out"}'
expect_eq "§PC5: a claim about an earlier review with a run is clean" clean "$(result "$work_dir/earlier-ok.json")"

draft "$work_dir/earlier-na.json" $'**question**:\nI was wrong last round about the totals. Do archived items count?' '{ran: "n/a: no change"}'
expect_contains "§PC5: a claim about an earlier review with \"ran\": n/a is flagged" "earlier review with nothing run" "$(result "$work_dir/earlier-na.json")"

draft "$work_dir/n-plus-one.json" $'**note**:\nThis runs one query per order, an N+1 on the order list.' '{ran: "console loop over 25 orders: 25 queries"}'
expect_contains "a query-count claim measured outside a request is flagged" "query counts with no request measuring them" "$(result "$work_dir/n-plus-one.json")"
draft "$work_dir/n-plus-one-ok.json" $'**note**:\nThis runs one query per order, an N+1 on the order list.' '{ran: "request spec GET /orders, 1 vs 4 orders: 3 vs 6 database queries"}'
expect_eq "a query-count claim measured through a request is clean" clean "$(result "$work_dir/n-plus-one-ok.json")"
draft "$work_dir/no-query-claim.json" $'**note**:\nThe order list reads the totals from the cart.' '{}'
expect_eq "a draft with no query-count claim needs no request" clean "$(result "$work_dir/no-query-claim.json")"
draft "$work_dir/names-test.json" $'**suggestion**:\nThe test above sets the archived flag, so the total looks right by luck.' '{ran: "n/a: asks for no behaviour change", walked: "n/a: names an existing test"}'
expect_eq "§PC5: naming an existing test is not asking for one" clean "$(result "$work_dir/names-test.json")"

# --- the asked-for change is walked, not only the bug (kc-post-review §PC6) ----------------------
walk_body=$'**suggestion**:\nCould the total skip archived items like the list does?'
draft "$work_dir/no-walked.json" "$walk_body" '{ran: "cart spec: fails before, passes after"}'
expect_contains "§PC6: a suggestion with no \"walked\" is flagged" 'asks for a change with no "walked"' "$(result "$work_dir/no-walked.json")"
draft "$work_dir/no-walked-issue.json" $'**issue**:\nAn empty cart still shows the old total.' '{ran: "cart spec: fails"}'
expect_contains "§PC6: an issue with no \"walked\" is flagged" 'asks for a change with no "walked"' "$(result "$work_dir/no-walked-issue.json")"
draft "$work_dir/walked-na.json" "$walk_body" '{ran: "cart spec: fails before, passes after", walked: "n/a"}'
expect_contains "§PC6: \"walked\": n/a with no reason is flagged" 'says "walked": n/a with no reason' "$(result "$work_dir/walked-na.json")"
draft "$work_dir/walked-na-why.json" $'**suggestion**:\nThis name could say what it holds.' '{ran: "n/a: a rename", walked: "n/a: a rename, no behaviour change"}'
expect_eq "§PC6: \"walked\": n/a with a reason is clean" clean "$(result "$work_dir/walked-na-why.json")"
draft "$work_dir/walked-ok.json" "$walk_body" '{ran: "cart spec: fails before, passes after", walked: "cart with archived items: 3 before, 2 after; empty cart: 0 before, 0 after; guest cart: unchanged"}'
expect_eq "§PC6: a real \"walked\" is clean" clean "$(result "$work_dir/walked-ok.json")"
draft "$work_dir/walked-question.json" $'**question:**\nIs the total meant to skip archived items?' '{}'
expect_eq "§PC6: a question needs no \"walked\"" clean "$(result "$work_dir/walked-question.json")"

# --- a ticket or pull request is a link the reader can open (kc-post-review §PC7) -------------
check_link() {
  draft "$work_dir/link.json" $'**note**:\n'"$1" '{}'
  result "$work_dir/link.json"
}
expect_contains "§PC7: a bare tracker id is flagged" "names ABC-1 without a link; write it as [ABC-1](<url>)" "$(check_link 'This repeats ABC-1 on the order list.')"
expect_eq "§PC7: a tracker id written as a link is clean" clean "$(check_link 'This repeats [ABC-1](https://tracker.example/ABC-1) on the order list.')"
expect_eq "§PC7: a tracker id inside a URL is clean" clean "$(check_link 'See https://tracker.example/browse/ABC-1 for the order list.')"
expect_contains "§PC7: a bare #42 is flagged" "names #42 without a link" "$(check_link 'The same fix landed in #42.')"
expect_contains "§PC7: a bare PR 42 is flagged" "names PR 42 without a link" "$(check_link 'The same fix landed in PR 42.')"
expect_contains "§PC7: a bare pull request #42 is flagged" "names pull request #42 without a link" "$(check_link 'The same fix landed in pull request #42.')"
expect_eq "§PC7: a pull request written as a link is clean" clean "$(check_link 'The same fix landed in [#42](https://github.com/acme/shop/pull/42).')"
expect_eq "§PC7: a pull request URL ending in a number is clean" clean "$(check_link 'See https://github.com/acme/shop/pull/42 for it.')"
tick='`'
expect_eq "§PC7: an id inside inline code is clean" clean "$(check_link "The key is ${tick}ABC-1${tick} in the fixture.")"
expect_eq "§PC7: an id in a URL query is clean" clean "$(check_link 'See https://tracker.example/search?q=ABC-1 for it.')"
draft "$work_dir/link-block.json" $'**note**:\nThe fixture holds this row.\n```\nticket: ABC-1 #42\n```'
expect_eq "§PC7: an id inside a code block is clean" clean "$(result "$work_dir/link-block.json")"
expect_eq "§PC7: standards names (UTF-8, ISO-8601, SHA-256) are not ids" clean "$(check_link 'The export is UTF-8 with ISO-8601 dates and a SHA-256 hash.')"
expect_contains "§PC7: a CVE id is still flagged" "names CVE-2024-1234 without a link" "$(check_link 'The fix covers CVE-2024-1234.')"
expect_eq "§PC7: a six-digit colour of digits only is not a reference" clean "$(check_link 'The badge text is #333333 on white.')"
expect_eq "§PC7: an eight-digit colour with alpha is not a reference" clean "$(check_link 'The overlay is #33333333 over the photo.')"
expect_contains "§PC7: a five-digit #12345 is still flagged" "names #12345 without a link" "$(check_link 'The same fix landed in #12345.')"
expect_eq "§PC7: a heading line and a hex colour are not references" clean "$(check_link $'# Totals\nThe badge uses #fff and #123abc.')"

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
draft "$work_dir/ran.json" "$run_fix" '{ran: "applied on a scratch copy: new test for a draft opened before the list loads, and the suite, pass", walked: "draft opened before the list loads: footer twice before, once after; draft opened after: unchanged"}'
expect_eq "an issue with a run record is clean" clean "$(result "$work_dir/ran.json")"
draft "$work_dir/question-no-ran.json" $'**question:**\nIs the swap meant to run on the first pass too?' '{}'
expect_eq "a question needs no \"ran\"" clean "$(result "$work_dir/question-no-ran.json")"

# --- a long unbroken stretch of words reads as one heavy run ----------------------------------
heavy=$'**note**:\nLocally, after cancelling the order the cart still had the coupon and the shipping address was unchanged.'
draft "$work_dir/heavy.json" "$heavy" '{}'
expect_contains "a 16-word stretch with no pause is flagged, with its first words" '16-word stretch with no comma or pause ("after cancelling the order the cart...")' "$(result "$work_dir/heavy.json")"
draft "$work_dir/paused.json" $'**note**:\nI tried it locally: after cancelling, the cart still had the coupon, but the address stayed the same.' '{}'
expect_eq "the same point with commas and a colon is clean" clean "$(result "$work_dir/paused.json")"
draft "$work_dir/heavy-dash.json" $'**note**:\nAfter cancelling the order the cart still had the coupon and the address - was unchanged (a bug).' '{}'
expect_eq "a spaced dash and a parenthesis break a stretch" clean "$(result "$work_dir/heavy-dash.json")"
draft "$work_dir/heavy-code.json" $'**note**:\nAfter cancelling `the order` the cart still had the coupon and the shipping address was unchanged.' '{}'
expect_contains "inline code counts as one word, so the stretch is still found" "-word stretch" "$(result "$work_dir/heavy-code.json")"
jq '.[0].long = "explains why the cart keeps its coupon"' "$work_dir/heavy.json" > "$work_dir/heavy-long.json"
expect_eq "a stretch with a reason in \"long\" is clean" clean "$(result "$work_dir/heavy-long.json")"
draft "$work_dir/thirteen.json" $'**note**:\nAfter cancelling the order the cart still had the coupon and address changed.' '{}'
expect_eq "a 13-word stretch is clean" clean "$(result "$work_dir/thirteen.json")"

# --- the author's own words are read first ("covered") ------------------------------------------
cover_body=$'**note**:\nThe total skips archived items, but the list shows them.'
draft "$work_dir/no-covered.json" "$cover_body" '{covered: null}'
no_covered=$(result "$work_dir/no-covered.json")
expect_contains "§PC8: a draft with no \"covered\" is flagged" 'no "covered": read the pull request description, the linked ticket and the author'"'"'s replies first' "$no_covered"
expect_contains "§PC8: the \"covered\" problem says what to do" "or drop the draft" "$no_covered"
draft "$work_dir/blank-covered.json" "$cover_body" '{covered: "  "}'
expect_contains "§PC8: a blank \"covered\" is flagged" 'no "covered"' "$(result "$work_dir/blank-covered.json")"
draft "$work_dir/na-covered.json" "$cover_body" '{covered: "n/a"}'
expect_contains "§PC8: a bare n/a \"covered\" is flagged" 'no "covered"' "$(result "$work_dir/na-covered.json")"
draft "$work_dir/covered-ok.json" "$cover_body" '{covered: "description says archived items stay in the list; it does not say the total counts them"}'
expect_eq "§PC8: a draft with a real \"covered\" is clean" clean "$(result "$work_dir/covered-ok.json")"

printf 'not json' > "$work_dir/broken.json"
status=0
bash "$check" "$work_dir/broken.json" >/dev/null 2>&1 || status=$?
expect_eq "unreadable drafts exit 2" 2 "$status"

finish
