#!/usr/bin/env bash
# Tests scripts/check-walk-receipt.sh: every walk-item needs a receipt line with something seen,
# evidence that is an existing capture or a request with its status, and the states walked (at
# least two, or "only state:" with a reason): kc-ready-for-review §H8.
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

printf 'env\tbin/review-env up\tGET /health 200\napp/models/order.rb\tcreated an order with a free item, total 0\tPOST /orders 201\tstates: empty cart; two items\nsrc/cart/total.ts\tcart page shows 2 items\t%s\tstates: one item; many items\n' "$work_dir/total.png" > "$receipt"
expect_eq "§V11: a full receipt passes" clean "$(run_walk_receipt_check)"

printf 'app/models/order.rb\tcreated an order\tPOST /orders 201\tstates: empty cart; two items\n' > "$receipt"
missing=$(run_walk_receipt_check)
expect_contains "§V11: an item with no receipt line fails" "walk-item src/cart/total.ts: no receipt line" "$missing"
expect_eq "only the missing item is listed" 1 "$(printf '%s\n' "$missing" | grep -c '^walk-item')"

rm -f "$receipt"
expect_contains "§V11: no receipt file fails every item" "walk-item app/models/order.rb: no receipt line" "$(run_walk_receipt_check)"

printf 'env\tbin/review-env up\tGET /health 200\napp/models/order.rb\t\tPOST /orders 201\tstates: empty cart; two items\nsrc/cart/total.ts\t  \t%s\tstates: one item; many items\n' "$work_dir/total.png" > "$receipt"
empty_seen=$(run_walk_receipt_check)
expect_contains "an empty seen fails" "walk-item app/models/order.rb: nothing seen" "$empty_seen"
expect_contains "a blank seen fails" "walk-item src/cart/total.ts: nothing seen" "$empty_seen"

printf 'env\tbin/review-env up\tGET /health 200\napp/models/order.rb\tcreated an order\tlooked fine\tstates: empty cart; two items\nsrc/cart/total.ts\tcart page\t%s\tstates: one item; many items\n' "$work_dir/gone.png" > "$receipt"
bad_evidence=$(run_walk_receipt_check)
expect_contains "evidence that is prose fails" "walk-item app/models/order.rb: evidence is none of" "$bad_evidence"
expect_contains "a capture that does not exist fails" "walk-item src/cart/total.ts: evidence file does not exist" "$bad_evidence"

printf 'env\tbin/review-env up\tGET /health 200\napp/models/order.rb\tcreated an order\tPOST /orders\tstates: empty cart; two items\nsrc/cart/total.ts\tcart page\t%s\tstates: one item; many items\n' "$work_dir/total.png" > "$receipt"
expect_contains "a request line with no status fails" "walk-item app/models/order.rb: evidence is none of" "$(run_walk_receipt_check)"

printf 'env\tbin/review-env up\tGET /health 200\napp/models/order.rb\tcreated an order\tPOST /orders 201\tstates: empty cart; two items\nsrc/cart/total.ts\tcart page\ttotal.png\tstates: one item; many items\n' > "$receipt"
expect_eq "a relative capture path is read from the receipt's folder" clean "$(run_walk_receipt_check)"

printf 'env\tbin/review-env up\tGET /health 200\napp/models/order.rb\tcreated an order\tPOST /orders 201\tstates: empty cart; two items\nsrc/cart/total.ts\tcart page\t%s\tstates: one item; many items\n' "$work_dir/total.webm" > "$receipt"
printf 'webm' > "$work_dir/total.webm"
expect_eq "a recording in the shared capture formats (webm) is evidence" clean "$(run_walk_receipt_check)"

printf 'GATES=naming\nWALK=not-required\nwalk: no non-test source file in the diff\n' > "$select_output"
rm -f "$receipt"
expect_eq "no walk-item lines: nothing to walk, passes with no receipt" clean "$(run_walk_receipt_check)"

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
write_with_env() { printf 'env\t%s\t%s\n' "$1" "$2" > "$receipt"; printf '%b' "$items_only" >> "$receipt"; }
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
printf 'env\tbin/review-env up\t%s\tstates: one item; many items\n' "$work_dir/gone.png" > "$receipt"
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
    printf 'env\tscripts/sync.sh --dry-run\t%s\n' "$1"
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
printf 'GATES=naming\nWALK=required\nwalk: x\nwalk-item: scripts/sync.sh surface: terminal\n' > "$select_output"
printf 'env\tscripts/sync.sh --dry-run\tGET /health 200\nscripts/sync.sh\tdry run listed 3 orders\texit 0: run.txt\tstates: dry run; --help\n' > "$receipt"
expect_contains "env: a terminal-only walk needs a transcript for the env line, not a request line" "env: evidence is none of a run transcript (exit 0: run.txt), after the command: GET /health 200" "$(run_walk_receipt_check)"
printf 'GATES=naming\nWALK=required\nwalk: x\nwalk-item: scripts/sync.sh\n' > "$select_output"
printf 'env\tscripts/sync.sh --dry-run\tGET /health 200\nscripts/sync.sh\tdry run listed 3 orders\ttotal.png\tstates: dry run; --help\n' > "$receipt"
expect_eq "legacy: a walk-item line with no surface accepts any kind (capture here)" clean "$(run_walk_receipt_check)"
printf 'env\tscripts/sync.sh --dry-run\tGET /health 200\nscripts/sync.sh\tdry run listed 3 orders\tcurl -si https://shop.test/x: resp.txt\tstates: dry run; --help\n' > "$receipt"
expect_eq "legacy: a curl response is accepted with no surface" clean "$(run_walk_receipt_check)"

# The states walked: one walk of one state is not QA.
printf 'GATES=naming\nWALK=required\nwalk: x\nwalk-item: app/models/order.rb\n' > "$select_output"
write_states() { printf 'env\tbin/review-env up\tGET /health 200\napp/models/order.rb\tcreated an order\tPOST /orders 201\t%s\n' "$1" > "$receipt"; }
printf 'env\tbin/review-env up\tGET /health 200\napp/models/order.rb\tcreated an order\tPOST /orders 201\n' > "$receipt"
missing_states=$(run_walk_receipt_check)
expect_contains "§H8: an item with no states field fails" "walk-item app/models/order.rb: fewer than two states walked" "$missing_states"
expect_contains "§H8: the message says to list every shape and walk each" "list every shape the change's output can take" "$missing_states"
write_states 'states: empty cart'
expect_contains "§H8: one state fails" "fewer than two states walked" "$(run_walk_receipt_check)"
write_states 'states: empty cart;  ; '
expect_contains "§H8: blank entries are not states" "fewer than two states walked" "$(run_walk_receipt_check)"
write_states 'states: empty cart; one long row; many short rows; landscape'
expect_eq "§H8: four states pass" clean "$(run_walk_receipt_check)"
write_states 'states: empty cart; two items'
expect_eq "§H8: two states pass" clean "$(run_walk_receipt_check)"
write_states 'only state: the page has no variants'
expect_eq "§H8: only state with a reason passes" clean "$(run_walk_receipt_check)"
write_states 'only state: none'
expect_contains "§H8: only state with a one-word reason fails" "fewer than two states walked" "$(run_walk_receipt_check)"
write_states 'only state:'
expect_contains "§H8: only state with no reason fails" "fewer than two states walked" "$(run_walk_receipt_check)"

# Dimensions: a walk-dimension item needs its states field to cover each dimension the diff varies along.
printf 'GATES=naming\nWALK=required\nwalk: x\nwalk-item: src/cart/total.tsx\nwalk-dimension: src/cart/total.tsx: viewport\n' > "$select_output"
write_dimension_states() { printf 'env\tbin/review-env up\tGET /health 200\nsrc/cart/total.tsx\tcard sits at the top\tPOST /orders 201\t%s\n' "$1" > "$receipt"; }
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

printf 'GATES=naming\nWALK=required\nwalk: x\nwalk-item: src/cart/total.tsx\nwalk-dimension: src/cart/total.tsx: viewport\nwalk-dimension: src/cart/total.tsx: print\n' > "$select_output"
write_dimension_states 'states: 1920px; 1280px; 390px'
expect_contains "two dimensions: the one left uncovered is named" "varies along print" "$(run_walk_receipt_check)"
printf 'GATES=naming\nWALK=required\nwalk: x\nwalk-item: src/cart/total.tsx\n' > "$select_output"
write_dimension_states 'states: empty cart; two items'
expect_eq "no walk-dimension line needs no dimension" clean "$(run_walk_receipt_check)"

printf 'GATES=naming\nWALK=required\nwalk: x\nwalk-item: app/[locale]/page.tsx\nwalk-dimension: app/[locale]/page.tsx: print\n' > "$select_output"
printf 'env\tbin/review-env up\tGET /health 200\napp/[locale]/page.tsx\tpage\tPOST /orders 201\tstates: screen; narrow screen\n' > "$receipt"
expect_contains "a path with regex characters still gets its dimension checked" "varies along print" "$(run_walk_receipt_check)"

finish
