#!/usr/bin/env bash
# Tests scripts/lib/qa-surface.sh and the receipt check's use of it: each changed file gets one QA
# surface, and the walk receipt takes only that surface's evidence (verification-gate §V11). Kept
# small so the lesson-ledger guard can run it twice inside its timeout.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
scripts_dir="$(dirname "$tests_dir")/scripts"
# shellcheck source=../scripts/lib/qa-surface.sh
. "$scripts_dir/lib/qa-surface.sh"

repo=$work_dir/repo
mkdir -p "$repo/.claude"

expect_eq "a page component is browser" browser "$(kc_get_qa_surface src/ui/Cart.tsx "$repo")"
expect_eq "a controller is api" api "$(kc_get_qa_surface app/controllers/orders_controller.rb "$repo")"
expect_eq "an api route under pages is api, not browser" api "$(kc_get_qa_surface pages/api/orders.ts "$repo")"
expect_eq "a shell script is terminal" terminal "$(kc_get_qa_surface scripts/sync.sh "$repo")"
expect_eq "a scheduled job is terminal" terminal "$(kc_get_qa_surface app/jobs/nightly_report.rb "$repo")"
expect_eq "a library module is unit" unit "$(kc_get_qa_surface lib/pricing.rb "$repo")"

printf '# overrides\nlib/exporter/* terminal\n' > "$repo/.claude/qa-surfaces.txt"
expect_eq "the repo override wins" terminal "$(kc_get_qa_surface lib/exporter/csv.rb "$repo")"
expect_eq "a path the override does not match keeps the default" unit "$(kc_get_qa_surface lib/pricing.rb "$repo")"

# The receipt check: a terminal item takes a run transcript and refuses a screenshot.
select_output=$work_dir/select.txt
receipt=$work_dir/walk-receipt.tsv
printf 'GATES=naming\nWALK=required\nwalk: x\nwalk-item: scripts/sync.sh surface: terminal\n' > "$select_output"
printf 'synced 3 orders\n' > "$work_dir/run.txt"
printf 'png' > "$work_dir/shot.png"
run_check() {
  local output status=0
  output=$(bash "$scripts_dir/check-walk-receipt.sh" "$select_output" "$receipt") || status=$?
  if [ "$status" -eq 0 ]; then echo clean; else printf '%s\n' "$output"; fi
}
printf 'env\tscripts/sync.sh --dry-run\texit 0: run.txt\nscripts/sync.sh\tdry run listed 3 orders\texit 0: run.txt\tstates: dry run; --help\n' > "$receipt"
expect_eq "§V11: a terminal item with a run transcript passes" clean "$(run_check)"
printf 'env\tscripts/sync.sh --dry-run\texit 0: run.txt\nscripts/sync.sh\tdry run listed 3 orders\tshot.png\tstates: dry run; --help\n' > "$receipt"
expect_contains "§V11: a terminal item with a screenshot fails and names its surface" "scripts/sync.sh is a terminal surface" "$(run_check)"

finish
