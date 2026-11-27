#!/usr/bin/env bash
# Tests scripts/check-walk-receipt.sh: every walk-item needs a receipt line with something seen,
# evidence that is an existing capture or a request with its status, and the states walked (at
# least two, or "only state:" with a reason): kc-code-review §G8.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
walk_receipt_checker="$(dirname "$tests_dir")/scripts/check-walk-receipt.sh"

select_output=$work_dir/select.txt
printf 'GATES=naming\nWALK=required\nwalk: x\nwalk-item: app/models/order.rb\nwalk-item: src/cart/total.ts\n' > "$select_output"
printf 'png' > "$work_dir/total.png"
receipt=$work_dir/walk-receipt.tsv

# Runs the checker; prints its output, or "clean" when it passes.
run_walk_receipt_check() {
  local output status=0
  output=$(bash "$walk_receipt_checker" "$select_output" "$receipt") || status=$?
  if [ "$status" -eq 0 ]; then echo clean; else printf '%s\n' "$output"; fi
}

printf 'design\tnone: no mock for this page\nenv\tbin/review-env up\tGET /health 200\napp/models/order.rb\tcreated an order with a free item, total 0\tPOST /orders 201\tstates: empty cart; two items\nsrc/cart/total.ts\tcart page shows 2 items\t%s\tstates: one item; many items\n' "$work_dir/total.png" > "$receipt"
expect_eq "§V11: a full receipt passes" clean "$(run_walk_receipt_check)"

printf 'app/models/order.rb\tcreated an order\tPOST /orders 201\tstates: empty cart; two items\n' > "$receipt"
missing=$(run_walk_receipt_check)
expect_contains "§V11: an item with no receipt line fails" "walk-item src/cart/total.ts: no receipt line" "$missing"
expect_eq "only the missing item is listed" 1 "$(printf '%s\n' "$missing" | grep -c '^walk-item')"

rm -f "$receipt"
expect_contains "§V11: no receipt file fails every item" "walk-item app/models/order.rb: no receipt line" "$(run_walk_receipt_check)"

printf 'design\tnone: no mock for this page\nenv\tbin/review-env up\tGET /health 200\napp/models/order.rb\t\tPOST /orders 201\tstates: empty cart; two items\nsrc/cart/total.ts\t  \t%s\tstates: one item; many items\n' "$work_dir/total.png" > "$receipt"
empty_seen=$(run_walk_receipt_check)
expect_contains "an empty seen fails" "walk-item app/models/order.rb: nothing seen" "$empty_seen"
expect_contains "a blank seen fails" "walk-item src/cart/total.ts: nothing seen" "$empty_seen"

printf 'design\tnone: no mock for this page\nenv\tbin/review-env up\tGET /health 200\napp/models/order.rb\tcreated an order\tlooked fine\tstates: empty cart; two items\nsrc/cart/total.ts\tcart page\t%s\tstates: one item; many items\n' "$work_dir/gone.png" > "$receipt"
bad_evidence=$(run_walk_receipt_check)
expect_contains "evidence that is prose fails" "walk-item app/models/order.rb: evidence is none of" "$bad_evidence"
expect_contains "a capture that does not exist fails" "walk-item src/cart/total.ts: evidence file does not exist" "$bad_evidence"

printf 'design\tnone: no mock for this page\nenv\tbin/review-env up\tGET /health 200\napp/models/order.rb\tcreated an order\tPOST /orders\tstates: empty cart; two items\nsrc/cart/total.ts\tcart page\t%s\tstates: one item; many items\n' "$work_dir/total.png" > "$receipt"
expect_contains "a request line with no status fails" "walk-item app/models/order.rb: evidence is none of" "$(run_walk_receipt_check)"

printf 'design\tnone: no mock for this page\nenv\tbin/review-env up\tGET /health 200\napp/models/order.rb\tcreated an order\tPOST /orders 201\tstates: empty cart; two items\nsrc/cart/total.ts\tcart page\ttotal.png\tstates: one item; many items\n' > "$receipt"
expect_eq "a relative capture path is read from the receipt's folder" clean "$(run_walk_receipt_check)"

printf 'design\tnone: no mock for this page\nenv\tbin/review-env up\tGET /health 200\napp/models/order.rb\tcreated an order\tPOST /orders 201\tstates: empty cart; two items\nsrc/cart/total.ts\tcart page\t%s\tstates: one item; many items\n' "$work_dir/total.webm" > "$receipt"
printf 'webm' > "$work_dir/total.webm"
expect_eq "a recording in the shared capture formats (webm) is evidence" clean "$(run_walk_receipt_check)"

printf 'GATES=naming\nWALK=not-required\nwalk: no non-test source file in the diff\n' > "$select_output"
rm -f "$receipt"
expect_eq "no walk-item lines: nothing to walk, passes with no receipt" clean "$(run_walk_receipt_check)"

# A browser change is walked beside its design: the receipt names it, or says why there is none.
printf 'GATES=react\nWALK=required\nwalk: x\nwalk-item: src/storefront/OrderPanel.tsx surface: browser\n' > "$select_output"
printf 'png' > "$work_dir/panel.png"; printf 'png' > "$work_dir/panel-design.png"
printf 'env\tbin/review-env up\t%s\nsrc/storefront/OrderPanel.tsx\tpanel shows totals on the right\t%s\tstates: empty cart; two items\n' "$work_dir/panel.png" "$work_dir/panel.png" > "$receipt"
expect_contains "§UI7 design-walk: a browser walk with no design line fails" "design: no design line" "$(run_walk_receipt_check)"
printf 'env\tbin/review-env up\t%s\ndesign\thttps://mock.example/storefront\nsrc/storefront/OrderPanel.tsx\tpanel shows totals on the right\t%s\tstates: empty cart; two items\n' "$work_dir/panel.png" "$work_dir/panel.png" > "$receipt"
expect_contains "§UI7 design-walk: a linked design with no capture of it fails" "walk-item src/storefront/OrderPanel.tsx: the walk follows a design" "$(run_walk_receipt_check)"
printf 'env\tbin/review-env up\t%s\ndesign\thttps://mock.example/storefront\nsrc/storefront/OrderPanel.tsx\tpanel shows totals on the right\t%s\tstates: empty cart; two items\tdesign: %s\n' "$work_dir/panel.png" "$work_dir/panel.png" "$work_dir/panel-design.png" > "$receipt"
expect_eq "§UI7 design-walk: a linked design with its capture beside the walk passes" clean "$(run_walk_receipt_check)"
printf 'env\tbin/review-env up\t%s\ndesign\tnone: no mock exists for this page\nsrc/storefront/OrderPanel.tsx\tpanel shows totals on the right\t%s\tstates: empty cart; two items\n' "$work_dir/panel.png" "$work_dir/panel.png" > "$receipt"
expect_eq "§UI7 design-walk: none with a reason passes" clean "$(run_walk_receipt_check)"
printf 'env\tbin/review-env up\t%s\ndesign\tnone:\nsrc/storefront/OrderPanel.tsx\tpanel\t%s\tstates: empty cart; two items\n' "$work_dir/panel.png" "$work_dir/panel.png" > "$receipt"
expect_contains "§UI7 design-walk: none with no reason fails" "design: none needs a reason" "$(run_walk_receipt_check)"
printf 'GATES=naming\nWALK=required\nwalk: x\nwalk-item: app/jobs/nightly_export.rb surface: terminal\n' > "$select_output"
printf 'exported 3 rows\n' > "$work_dir/run.txt"
printf 'env\tbin/export\texit 0: %s\napp/jobs/nightly_export.rb\texported 3 rows\texit 0: %s\tstates: no rows; three rows\n' "$work_dir/run.txt" "$work_dir/run.txt" > "$receipt"
expect_eq "§UI7 design-walk: a change nobody sees needs no design line" clean "$(run_walk_receipt_check)"

status=0
bash "$walk_receipt_checker" > /dev/null 2>&1 || status=$?
expect_eq "usage error exits 2" 2 "$status"

status=0
unreadable=$(bash "$walk_receipt_checker" "$work_dir/no-such-select.txt" "$receipt" 2>&1) || status=$?
expect_eq "an unreadable select-gates file exits 2" 2 "$status"
expect_contains "it says which file it cannot read" "check-walk-receipt.sh: cannot read $work_dir/no-such-select.txt" "$unreadable"

# A blank `walk-item:` line names no file to walk.
printf 'WALK=required\nwalk-item: \n' > "$select_output"
rm -f "$receipt"
expect_eq "a blank walk-item line is not an item" clean "$(run_walk_receipt_check)"

# The environment line: the one command that brought the app up, with evidence it answered.
printf 'GATES=naming\nWALK=required\nwalk: x\nwalk-item: app/models/order.rb\nwalk-item: src/cart/total.ts\n' > "$select_output"
printf 'png' > "$work_dir/total.png"
write_with_env() { printf 'design\tnone: no mock for this page\nenv\t%s\t%s\n' "$1" "$2" > "$receipt"; printf '%b' "$items_only" >> "$receipt"; }
items_only='app/models/order.rb\tcreated an order\tPOST /orders 201\tstates: empty cart; two items\nsrc/cart/total.ts\tcart page\tPOST /orders 201\tstates: empty cart; two items\n'
printf '%b' "$items_only" > "$receipt"
expect_contains "env: no env line fails" "env: no env line" "$(run_walk_receipt_check)"
write_with_env 'bin/review-env up && bin/seed' 'GET /health 200'
expect_contains "env: a chain of steps fails" "env: more than one step" "$(run_walk_receipt_check)"
write_with_env 'start the server; open the app' 'GET /health 200'
expect_contains "env: steps joined by a semicolon fail" "env: more than one step" "$(run_walk_receipt_check)"
write_with_env '' 'GET /health 200'
expect_contains "env: a blank command fails" "env: no command" "$(run_walk_receipt_check)"
write_with_env 'bin/review-env up' 'it came up'
expect_contains "env: evidence that is prose fails" "env: evidence is none of" "$(run_walk_receipt_check)"
printf 'design\tnone: no mock for this page\nenv\tbin/review-env up\t%s\tstates: one item; many items\n' "$work_dir/gone.png" > "$receipt"
printf '%b' "$items_only" >> "$receipt"
expect_contains "env: a capture that does not exist fails" "env: evidence file does not exist" "$(run_walk_receipt_check)"
write_with_env 'bin/review-env up' 'total.png'
expect_eq "env: a capture beside the receipt is evidence" clean "$(run_walk_receipt_check)"
printf 'GATES=naming\nWALK=not-required\nwalk: none\n' > "$select_output"
rm -f "$receipt"
expect_eq "env: nothing to walk needs no env line" clean "$(run_walk_receipt_check)"

# Run transcripts: a command-line change is walked by running it; `exit <N>: <path>` is its evidence.
printf 'GATES=naming\nWALK=required\nwalk: x\nwalk-item: bin/sync-orders\n' > "$select_output"
printf 'sync: 3 orders (dry run)\n' > "$work_dir/run.txt"
: > "$work_dir/empty.txt"
write_cli() { printf '%b' "env\t$1\t$2\nbin/sync-orders\tdry run listed 3 orders\t$3\tstates: dry run; --help\n" > "$receipt"; }
write_cli 'bin/sync-orders --dry-run' 'exit 0: run.txt' 'exit 0: run.txt'
expect_eq "§V11: a run transcript is evidence for an item and for the env line" clean "$(run_walk_receipt_check)"
write_cli 'bin/sync-orders --dry-run' 'GET /health 200' "exit 2: $work_dir/run.txt"
expect_eq "a transcript with an absolute path and a non-zero exit code passes" clean "$(run_walk_receipt_check)"
write_cli 'bin/sync-orders --dry-run' 'exit 0: run.txt' 'exit 0: gone.txt'
expect_contains "a transcript file that does not exist fails" "walk-item bin/sync-orders: transcript file does not exist: gone.txt" "$(run_walk_receipt_check)"
write_cli 'bin/sync-orders --dry-run' 'exit 0: run.txt' 'exit 0: empty.txt'
expect_contains "an empty transcript file fails" "walk-item bin/sync-orders: transcript file is empty: empty.txt" "$(run_walk_receipt_check)"
write_cli 'bin/sync-orders --dry-run' 'exit 0: run.txt' 'run.txt'
expect_contains "a transcript path with no exit code fails" "walk-item bin/sync-orders: evidence is none of" "$(run_walk_receipt_check)"
write_cli 'bin/sync-orders --dry-run' 'exit 0: run.txt' 'exit: run.txt'
expect_contains "an exit with no number fails" "walk-item bin/sync-orders: evidence is none of" "$(run_walk_receipt_check)"
write_cli 'bin/sync-orders --dry-run' 'exit 0: gone.txt' 'exit 0: run.txt'
expect_contains "env: a transcript file that does not exist fails" "env: transcript file does not exist: gone.txt" "$(run_walk_receipt_check)"
write_cli 'bin/sync-orders --dry-run' 'exit 0: empty.txt' 'exit 0: run.txt'
expect_contains "env: an empty transcript file fails" "env: transcript file is empty: empty.txt" "$(run_walk_receipt_check)"
write_cli 'bin/sync-orders --dry-run' 'run.txt' 'exit 0: run.txt'
expect_contains "env: a transcript with no exit code fails" "env: evidence is none of" "$(run_walk_receipt_check)"
printf 'GATES=naming\nWALK=required\nwalk: x\nwalk-item: app/models/order.rb\n' > "$select_output"
rm -f "$receipt"
expect_contains "the no-receipt message names the surface to walk" "on its QA surface (browser, API, terminal, unit)" "$(run_walk_receipt_check)"

# QA surfaces: select-gates.sh names a surface per walk-item, and only that surface's evidence passes.
printf 'GATES=naming\nWALK=required\nwalk: x\nwalk-item: src/ui/Cart.tsx surface: browser\nwalk-item: app/controllers/orders_controller.rb surface: api\nwalk-item: scripts/sync.sh surface: terminal\nwalk-item: lib/pricing.rb surface: unit\n' > "$select_output"
printf 'HTTP/1.1 200 OK\r\ncontent-type: application/json\r\n\r\n{"id":7}\n' > "$work_dir/resp.txt"
printf '{"id":7}\n' > "$work_dir/body-only.txt"
write_surfaces() {
  {
    printf 'design\tnone: no mock for this page\nenv\tscripts/sync.sh --dry-run\t%s\n' "$1"
    printf 'src/ui/Cart.tsx\tcart shows 2 items\t%s\tstates: one item; many items\n' "$2"
    printf 'app/controllers/orders_controller.rb\torder 7 returned\t%s\tstates: found; missing\n' "$3"
    printf 'scripts/sync.sh\tdry run listed 3 orders\t%s\tstates: dry run; --help\n' "$4"
    printf 'lib/pricing.rb\ttotal of an empty cart is 0\t%s\tstates: empty; two items\n' "$5"
  } > "$receipt"
}
write_surfaces 'exit 0: run.txt' 'total.png' 'curl -si https://shop.test/orders/7: resp.txt' 'exit 0: run.txt' 'exit 0: run.txt'
expect_eq "surfaces: each surface's own evidence passes (capture, curl response, transcripts)" clean "$(run_walk_receipt_check)"
write_surfaces 'exit 0: run.txt' 'total.png' 'GET /orders/7 200' 'exit 0: run.txt' 'GET /orders/7 200'
expect_eq "surfaces: a bare request line passes for an api item and for a unit item" clean "$(run_walk_receipt_check)"
write_surfaces 'exit 0: run.txt' 'total.png' 'curl -si https://shop.test/orders/7: resp.txt' 'exit 0: run.txt' 'total.png'
expect_eq "surfaces: a capture passes for a unit item" clean "$(run_walk_receipt_check)"
write_surfaces 'exit 0: run.txt' 'total.png' 'curl -si https://shop.test/orders/7: resp.txt' 'total.png' 'exit 0: run.txt'
mismatch=$(run_walk_receipt_check)
expect_contains "surfaces: a screenshot for a terminal item names the surface and the evidence" "walk-item scripts/sync.sh: scripts/sync.sh is a terminal surface: give a run transcript (exit 0: run.txt), not: total.png" "$mismatch"
expect_eq "surfaces: only the mismatched item is listed" 1 "$(printf '%s\n' "$mismatch" | grep -c '^walk-item')"
write_surfaces 'exit 0: run.txt' 'exit 0: run.txt' 'curl -si https://shop.test/orders/7: resp.txt' 'exit 0: run.txt' 'exit 0: run.txt'
expect_contains "surfaces: a transcript for a browser item says to give a screenshot" "src/ui/Cart.tsx is a browser surface: give a screenshot or recording" "$(run_walk_receipt_check)"
write_surfaces 'exit 0: run.txt' 'total.png' 'exit 0: run.txt' 'exit 0: run.txt' 'exit 0: run.txt'
expect_contains "surfaces: a transcript for an api item says to give the curl request and its saved response" "is a api surface: give a curl request and its saved response (curl -si https://host/orders/7: resp.txt) or a request line with its status" "$(run_walk_receipt_check)"
write_surfaces 'exit 0: run.txt' 'total.png' 'curl -si https://shop.test/orders/7: body-only.txt' 'exit 0: run.txt' 'exit 0: run.txt'
expect_contains "curl: a response file with no HTTP status line fails" "walk-item app/controllers/orders_controller.rb: curl response file has no HTTP status line" "$(run_walk_receipt_check)"
write_surfaces 'exit 0: run.txt' 'total.png' 'curl -si https://shop.test/orders/7: gone.txt' 'exit 0: run.txt' 'exit 0: run.txt'
expect_contains "curl: a missing response file fails" "curl response file does not exist: gone.txt" "$(run_walk_receipt_check)"
write_surfaces 'exit 0: run.txt' 'total.png' 'curl -si https://shop.test/orders/7: empty.txt' 'exit 0: run.txt' 'exit 0: run.txt'
expect_contains "curl: an empty response file fails" "curl response file is empty: empty.txt" "$(run_walk_receipt_check)"
write_surfaces 'exit 0: run.txt' 'total.png' 'curl -si https://shop.test/orders/7' 'exit 0: run.txt' 'exit 0: run.txt'
expect_contains "curl: a curl line with no saved response fails" "is a api surface" "$(run_walk_receipt_check)"
write_surfaces 'it came up' 'total.png' 'curl -si https://shop.test/orders/7: resp.txt' 'exit 0: run.txt' 'exit 0: run.txt'
expect_contains "env: with all four surfaces it may use any of their kinds, prose fails" "env: evidence is none of" "$(run_walk_receipt_check)"
cp "$work_dir/resp.txt" "$work_dir/out.png"
write_surfaces 'exit 0: run.txt' 'total.png' 'curl -si https://shop.test/orders/7: out.png' 'exit 0: run.txt' 'exit 0: run.txt'
expect_eq "surfaces: a curl line whose saved file is named like a capture is still a curl response" clean "$(run_walk_receipt_check)"
printf 'GATES=naming\nWALK=required\nwalk: x\nwalk-item: src/ui/Cart.tsx surface: browser\n' > "$select_output"
printf 'design\tnone: no mock for this page\nenv\tbin/review-env up\tGET /health 200\nsrc/ui/Cart.tsx\tcart shows 2 items\ttotal.png\tstates: one item; many items\n' > "$receipt"
expect_contains "env: a browser-only walk takes a capture for the env line, not a request line" "env: evidence is none of a screenshot or recording, after the command: GET /health 200" "$(run_walk_receipt_check)"
printf 'design\tnone: no mock for this page\nenv\tbin/review-env up\ttotal.png\nsrc/ui/Cart.tsx\tcart shows 2 items\ttotal.png\tstates: one item; many items\n' > "$receipt"
expect_eq "env: a browser-only walk with a capture env line passes" clean "$(run_walk_receipt_check)"
printf 'GATES=naming\nWALK=required\nwalk: x\nwalk-item: scripts/sync.sh surface: terminal\n' > "$select_output"
printf 'design\tnone: no mock for this page\nenv\tscripts/sync.sh --dry-run\tGET /health 200\nscripts/sync.sh\tdry run listed 3 orders\texit 0: run.txt\tstates: dry run; --help\n' > "$receipt"
expect_contains "env: a terminal-only walk needs a transcript for the env line, not a request line" "env: evidence is none of a run transcript (exit 0: run.txt), after the command: GET /health 200" "$(run_walk_receipt_check)"
printf 'GATES=naming\nWALK=required\nwalk: x\nwalk-item: scripts/sync.sh\n' > "$select_output"
printf 'design\tnone: no mock for this page\nenv\tscripts/sync.sh --dry-run\tGET /health 200\nscripts/sync.sh\tdry run listed 3 orders\ttotal.png\tstates: dry run; --help\n' > "$receipt"
expect_eq "legacy: a walk-item line with no surface accepts any kind (capture here)" clean "$(run_walk_receipt_check)"
printf 'design\tnone: no mock for this page\nenv\tscripts/sync.sh --dry-run\tGET /health 200\nscripts/sync.sh\tdry run listed 3 orders\tcurl -si https://shop.test/x: resp.txt\tstates: dry run; --help\n' > "$receipt"
expect_eq "legacy: a curl response is accepted with no surface" clean "$(run_walk_receipt_check)"

# The states walked: one walk of one state is not QA.
printf 'GATES=naming\nWALK=required\nwalk: x\nwalk-item: app/models/order.rb\n' > "$select_output"
write_states() { printf 'design\tnone: no mock for this page\nenv\tbin/review-env up\tGET /health 200\napp/models/order.rb\tcreated an order\tPOST /orders 201\t%s\n' "$1" > "$receipt"; }
printf 'design\tnone: no mock for this page\nenv\tbin/review-env up\tGET /health 200\napp/models/order.rb\tcreated an order\tPOST /orders 201\n' > "$receipt"
missing_states=$(run_walk_receipt_check)
expect_contains "§G8: an item with no states field fails" "walk-item app/models/order.rb: fewer than two states walked" "$missing_states"
expect_contains "§G8: the message says to list every shape and walk each" "list every shape the change's output can take" "$missing_states"
write_states 'states: empty cart'
expect_contains "§G8: one state fails" "fewer than two states walked" "$(run_walk_receipt_check)"
write_states 'states: empty cart;  ; '
expect_contains "§G8: blank entries are not states" "fewer than two states walked" "$(run_walk_receipt_check)"
write_states 'states: empty cart; one long row; many short rows; landscape'
expect_eq "§G8: four states pass" clean "$(run_walk_receipt_check)"
write_states 'states: empty cart; two items'
expect_eq "§G8: two states pass" clean "$(run_walk_receipt_check)"
write_states 'only state: the page has no variants'
expect_eq "§G8: only state with a reason passes" clean "$(run_walk_receipt_check)"
write_states 'only state: none'
expect_contains "§G8: only state with a one-word reason fails" "fewer than two states walked" "$(run_walk_receipt_check)"
write_states 'only state:'
expect_contains "§G8: only state with no reason fails" "fewer than two states walked" "$(run_walk_receipt_check)"

# Dimensions: a walk-dimension item needs its states field to cover each dimension the diff varies along.
printf 'GATES=naming\nWALK=required\nwalk: x\nwalk-item: src/cart/total.tsx\nwalk-dimension: src/cart/total.tsx: viewport\n' > "$select_output"
write_dimension_states() { printf 'design\tnone: no mock for this page\nenv\tbin/review-env up\tGET /health 200\nsrc/cart/total.tsx\tcard sits at the top\tPOST /orders 201\t%s\n' "$1" > "$receipt"; }
write_dimension_states 'states: 1280px; 390px'
viewport_missing=$(run_walk_receipt_check)
expect_contains "viewport: no wide desktop width fails" "walk-item src/cart/total.tsx: its diff varies along viewport, but the states field does not cover it (a wide desktop (1920px or more))" "$viewport_missing"
expect_not_contains "viewport: it does not list the widths that are there" "laptop" "$viewport_missing"
write_dimension_states 'states: empty cart; two items'
expect_contains "viewport: states with no widths list all three" "a wide desktop (1920px or more), a laptop (1024px to 1919px), a phone (600px or less)" "$(run_walk_receipt_check)"
write_dimension_states 'states: 1920px; 390px'
expect_contains "viewport: no laptop width fails" "a laptop (1024px to 1919px)" "$(run_walk_receipt_check)"
write_dimension_states 'states: 1920px; 1280px'
expect_contains "viewport: no phone width fails" "a phone (600px or less)" "$(run_walk_receipt_check)"
write_dimension_states 'states: 1920px; 1440px; 1280px; 768px; 390px'
expect_eq "viewport: wide, laptop and phone pass" clean "$(run_walk_receipt_check)"
write_dimension_states 'only state: one fixed layout for all'
expect_contains "viewport: only state does not excuse the widths" "varies along viewport" "$(run_walk_receipt_check)"
write_dimension_states 'states: 1920x1080; 1366w; @375'
expect_eq "viewport: widths written as 1920x1080, 1366w and @375 count" clean "$(run_walk_receipt_check)"
write_dimension_states 'states: 1000 rows; 2000 rows; 500 rows'
expect_contains "viewport: counts without px are not widths" "varies along viewport" "$(run_walk_receipt_check)"

printf 'GATES=naming\nWALK=required\nwalk: x\nwalk-item: src/cart/total.tsx\nwalk-dimension: src/cart/total.tsx: locale\n' > "$select_output"
write_dimension_states 'states: de-DE; empty cart'
expect_contains "locale: one locale fails" "varies along locale" "$(run_walk_receipt_check)"
write_dimension_states 'states: en-US; de-DE'
expect_eq "locale: two locales pass" clean "$(run_walk_receipt_check)"
write_dimension_states 'locale de-de; en-us'
expect_eq "locale: lowercase tags count when the field says locale" clean "$(run_walk_receipt_check)"
write_dimension_states 'states: no-op state; re-do state'
expect_contains "locale: hyphenated words are not locales" "varies along locale" "$(run_walk_receipt_check)"
write_dimension_states 'states: ar-SA rtl; empty cart'
expect_eq "locale: one locale and rtl pass" clean "$(run_walk_receipt_check)"

printf 'GATES=naming\nWALK=required\nwalk: x\nwalk-item: src/cart/total.tsx\nwalk-dimension: src/cart/total.tsx: print\n' > "$select_output"
write_dimension_states 'states: screen; narrow screen'
expect_contains "print: no print state fails" "a print or pdf state" "$(run_walk_receipt_check)"
write_dimension_states 'states: screen; print preview'
expect_eq "print: a print state passes" clean "$(run_walk_receipt_check)"

printf 'GATES=naming\nWALK=required\nwalk: x\nwalk-item: src/cart/total.tsx\nwalk-dimension: src/cart/total.tsx: data-size\n' > "$select_output"
write_dimension_states 'states: one item; two items'
expect_contains "data-size: no empty state and no large state fails" "an empty state; a large state" "$(run_walk_receipt_check)"
write_dimension_states 'states: empty cart; 500 rows'
expect_eq "data-size: empty and 500 rows pass" clean "$(run_walk_receipt_check)"

# Exits: a form or dialog is walked through each way out, a failed save included.
printf 'GATES=naming\nWALK=required\nwalk: x\nwalk-item: src/cart/total.tsx\nwalk-dimension: src/cart/total.tsx: exits\n' > "$select_output"
write_dimension_states 'states: fill the address and save; empty address shows required'
exits_missing=$(run_walk_receipt_check)
expect_contains "exits: only the happy path names the cancel that is missing" "a cancel or close" "$exits_missing"
expect_contains "exits: only the happy path names the failed save that is missing" "a failed save" "$exits_missing"
write_dimension_states 'states: change name, confirm, saves; change name, cancel, asks again; save fails with 500, stays open'
expect_eq "exits: confirm, cancel and a failed save cover it" clean "$(run_walk_receipt_check)"
write_dimension_states 'states: apply in the drawer; close the drawer'
expect_contains "exits: no failed save fails" "a failed save" "$(run_walk_receipt_check)"
write_dimension_states 'states: book the slot; dismiss the dialog; request rejected with 500'
expect_contains "exits: no submit or confirm fails (book is not ok)" "a submit or confirm" "$(run_walk_receipt_check)"
write_dimension_states 'states: save; cancel; 1440px; 500px'
expect_contains "exits: a width is not a failed save" "a failed save" "$(run_walk_receipt_check)"
write_dimension_states 'states: save; cancel; answered 422'
expect_eq "exits: a 4xx status on its own is a failed save" clean "$(run_walk_receipt_check)"

printf 'GATES=naming\nWALK=required\nwalk: x\nwalk-item: src/cart/total.tsx\nwalk-dimension: src/cart/total.tsx: viewport\nwalk-dimension: src/cart/total.tsx: print\n' > "$select_output"
write_dimension_states 'states: 1920px; 1280px; 390px'
expect_contains "two dimensions: the one left uncovered is named" "varies along print" "$(run_walk_receipt_check)"
printf 'GATES=naming\nWALK=required\nwalk: x\nwalk-item: src/cart/total.tsx\n' > "$select_output"
write_dimension_states 'states: empty cart; two items'
expect_eq "no walk-dimension line needs no dimension" clean "$(run_walk_receipt_check)"

printf 'GATES=naming\nWALK=required\nwalk: x\nwalk-item: app/[locale]/page.tsx\nwalk-dimension: app/[locale]/page.tsx: print\n' > "$select_output"
printf 'design\tnone: no mock for this page\nenv\tbin/review-env up\tGET /health 200\napp/[locale]/page.tsx\tpage\tPOST /orders 201\tstates: screen; narrow screen\n' > "$receipt"
expect_contains "a path with regex characters still gets its dimension checked" "varies along print" "$(run_walk_receipt_check)"

# Consumers (§V11, §B8): a changed unit is walked from every consumer's side. uses.txt is
# trace-uses.sh's output; each consumer file of an item needs an entry in the fifth field with an
# omitted or partial input and its output before and after, or an only-state reason.
printf 'GATES=naming\nWALK=required\nwalk: x\nwalk-item: app/models/order.rb surface: api\n' > "$select_output"
uses_file=$work_dir/uses.txt
cat > "$uses_file" <<'USES'
name Order (definition, app/models/order.rb): 3 uses
  app/services/checkout.rb:12: Order.create(params)
  app/services/checkout.rb:40: Order.find(id)
  app/jobs/export_job.rb:5: Order.all
  docs/orders.md:2: Order is documented here
  spec/models/order_spec.rb:3: Order.new
  app/models/order.rb:9: Order.first
name Other (definition, app/models/other.rb): 1 uses
  app/views/other_view.rb:2: Other.x
tests: 1
  spec/models/order_spec.rb
summary: 2 names, 5 uses, 1 test files
USES
write_consumer_receipt() {
  printf 'design\tnone: no mock for this page\nenv\tbin/review-env up\tGET /health 200\napp/models/order.rb\tsaved an order\tPOST /orders 201\tstates: full form; empty cart\t%s\n' "$1" > "$receipt"
}
run_consumer_check() {
  local output status=0
  output=$(bash "$walk_receipt_checker" "$select_output" "$receipt" "$uses_file") || status=$?
  if [ "$status" -eq 0 ]; then echo clean; else printf '%s\n' "$output"; fi
}
full_entries='consumers: app/services/checkout.rb: omitted the discount field; before discount stayed on; after it reads off | app/jobs/export_job.rb: only state: it always passes every field'
write_consumer_receipt "$full_entries"
expect_eq "§V11: every consumer with an omitted state and before/after (or an only-state reason) passes" clean "$(run_consumer_check)"
write_consumer_receipt ''
missing_field=$(run_consumer_check)
expect_contains "§V11: an item with consumers and no fifth field fails, naming a consumer" "consumer app/services/checkout.rb uses what this item changes and has no entry" "$missing_field"
expect_contains "§V11: every consumer file is named" "consumer app/jobs/export_job.rb uses what this item changes" "$missing_field"
expect_eq "a test file, the item itself and another item's consumer are not consumers" 2 "$(printf '%s\n' "$missing_field" | grep -c 'consumer app/')"
write_consumer_receipt 'consumers: app/services/checkout.rb: omitted the discount field; before on; after off'
expect_contains "§V11: a consumer left out of the field fails" "consumer app/jobs/export_job.rb uses what this item changes" "$(run_consumer_check)"
write_consumer_receipt 'consumers: app/services/checkout.rb: saved with all fields; before on; after on | app/jobs/export_job.rb: only state: it always passes every field'
expect_contains "§V11: an entry with no omitted or partial input fails" "consumer app/services/checkout.rb: walk it with an input left out or partial" "$(run_consumer_check)"
write_consumer_receipt 'consumers: app/services/checkout.rb: omitted the discount field; after it reads off | app/jobs/export_job.rb: only state: it always passes every field'
expect_contains "§V11: an entry with no before state fails" "consumer app/services/checkout.rb: give what it received before and after" "$(run_consumer_check)"
write_consumer_receipt 'consumers: app/services/checkout.rb: omitted the discount field; before on; after off | app/jobs/export_job.rb: only state: n/a'
expect_contains "§V11: an only-state reason under three words fails" "consumer app/jobs/export_job.rb: walk it with an input left out or partial" "$(run_consumer_check)"
# A prose mention is not a consumer (the fixture's docs/orders.md). Neither is a comment, quoted text,
# or a plain variable of the changed name when the name is only the hunk's enclosing context.
reader_count=20
other_use_count=3
generic_use_count=$((reader_count + other_use_count))
{
  printf 'name script_name (enclosing, app/models/order.rb): %s uses\n' "$generic_use_count"
  # shellcheck disable=SC2016 # $script_name is fixture text, not an expansion
  for fixture_index in $(seq 1 "$reader_count"); do printf '  lib/generic_%s.rb:1: echo "usage: $script_name"\n' "$fixture_index"; done
  # shellcheck disable=SC2016 # fixture text, not an expansion
  printf '  lib/assigned.rb:1: script_name=$(basename "$0")\n  lib/commented.rb:1: # script_name is the basename\n  lib/passed.rb:1: render(script_name, other)\n'
  printf 'tests: 0\nsummary: 1 names, %s uses, 0 test files\n' "$generic_use_count"
} > "$uses_file"
write_consumer_receipt ''
expect_eq "§V11: variable reads, assignments and an uncalled bare use of an enclosing name are not consumers" clean "$(run_consumer_check)"
# The same bare use is a consumer when the name is a definition, and a comment, a `$name` read, quoted
# text and a spaced assignment of it are not.
{
  # shellcheck disable=SC2016 # fixture text, not an expansion
  printf 'name script_name (definition, app/models/order.rb): 6 uses\n  lib/passed.rb:1: render(script_name, other)\n  lib/read.rb:1: echo "usage: $script_name"\n  lib/commented.rb:1: # script_name is the basename\n  lib/quoted.rb:1: log("script_name is a word here")\n  lib/spaced.rb:1: script_name = other\n  lib/subst.sh:1: result="$(script_name arg)"\n'
  printf 'tests: 0\nsummary: 1 names, 6 uses, 0 test files\n'
} > "$uses_file"
definition_uses=$(run_consumer_check)
expect_contains "§V11: a bare use of a definition name is a consumer" "consumer lib/passed.rb uses what this item changes" "$definition_uses"
expect_not_contains "§V11: a \$name read of a definition name is not" "consumer lib/read.rb" "$definition_uses"
expect_not_contains "§V11: a comment mentioning a definition name is not" "consumer lib/commented.rb" "$definition_uses"
expect_not_contains "§V11: quoted text holding a definition name is not" "consumer lib/quoted.rb" "$definition_uses"
expect_contains "§V11: a call inside a double-quoted command substitution is a consumer" "consumer lib/subst.sh uses what this item changes" "$definition_uses"
expect_not_contains "§V11: a spaced assignment of a definition name is not" "consumer lib/spaced.rb" "$definition_uses"
# A name with regex characters (a `$` prefix) still finds its consumers.
{
  # shellcheck disable=SC2016 # fixture text, not an expansion
  printf 'name $fetchUser (definition, app/models/order.rb): 1 uses\n  src/b.js:1: const user = $fetchUser(id)\ntests: 0\nsummary: 1 names, 1 uses, 0 test files\n'
} > "$uses_file"
expect_contains "§V11: a name starting with a regex character still lists its consumer" "consumer src/b.js uses what this item changes" "$(run_consumer_check)"
# A changed function with thirty code callers still lists every one: there is no cap on code consumers.
caller_count=30
{
  printf 'name Order (definition, app/models/order.rb): %s uses\n' "$caller_count"
  for fixture_index in $(seq 1 "$caller_count"); do printf '  lib/caller_%s.rb:1: Order.create(params)\n' "$fixture_index"; done
  printf 'tests: 0\nsummary: 1 names, %s uses, 0 test files\n' "$caller_count"
} > "$uses_file"
many_callers=$(run_consumer_check)
expect_eq "§V11: a function with $caller_count code callers needs $caller_count consumer entries" "$caller_count" "$(printf '%s\n' "$many_callers" | grep -c 'consumer lib/caller_')"
{
  printf 'name Order (enclosing, app/models/order.rb): 2 uses\n  lib/caller_a.rb:1: result = Order.create(params)\n  lib/caller_b.rb:1: Order.create(params)\n'
  printf 'tests: 0\nsummary: 1 names, 2 uses, 0 test files\n'
} > "$uses_file"
enclosing_callers=$(run_consumer_check)
expect_contains "§V11: an enclosing name used at command position is a consumer" "consumer lib/caller_b.rb uses what this item changes" "$enclosing_callers"
expect_contains "§V11: an enclosing name used as a member call after other text is a consumer" "consumer lib/caller_a.rb uses what this item changes" "$enclosing_callers"
write_consumer_receipt "$full_entries"
printf 'name Order (definition, app/models/order.rb): 1 uses\n  app/models/order.rb:9: Order.first\ntests: 0\nsummary: 1 names, 1 uses, 0 test files\n' > "$uses_file"
printf 'design\tnone: no mock for this page\nenv\tbin/review-env up\tGET /health 200\napp/models/order.rb\tsaved an order\tPOST /orders 201\tstates: full form; empty cart\n' > "$receipt"
expect_eq "§V11: an item with no consumer outside itself and its tests needs no fifth field" clean "$(run_consumer_check)"
status=0
bash "$walk_receipt_checker" "$select_output" "$receipt" "$work_dir/no-such-uses.txt" > /dev/null 2>&1 || status=$?
expect_eq "an unreadable uses file exits 2" 2 "$status"
finish
