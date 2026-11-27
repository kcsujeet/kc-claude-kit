#!/usr/bin/env bash
# Tests scripts/verify-gate-blocks.sh on a later round whose verdicts are large or hold a byte the
# session's locale can't read: the receipt lines and Walk: lines present are found, and no
# multibyte error stops the read. (A large receipt read through printf | grep -q under pipefail
# reported present lines as missing.)
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
verifier="$(dirname "$tests_dir")/scripts/verify-gate-blocks.sh"

repo=$work_dir/repo
git init -q "$repo"
git -C "$repo" commit -q --allow-empty -m init
round=$work_dir/round-2
mkdir -p "$round/verdicts"
: > "$round/review.diff"; : > "$round/changed-files.txt"
printf 'HEAD_SHA=%s\n' "$(git -C "$repo" rev-parse HEAD)" > "$round/meta.env"
printf '3 fixes re-checked\n0 rewrites checked\n0 rename-only lines kept\n' > "$round/verdicts/checklist.txt"
# A verdict past the pipe buffer, after the receipt lines.
{ printf 'GATE: naming\nSTATUS: PASS\nBOXES:\n'; for i in $(seq 1 4000); do printf -- '- [N/A] §N%d: nothing in the storefront diff matches this box, padding the block past a pipe buffer\n' "$i"; done; printf 'FINDINGS:\n'; } > "$round/verdicts/naming.txt"

output=$(bash "$verifier" --later-round "$round" "$repo" 2>&1 || true)
expect_not_contains "large-receipt: a present fixes re-checked line is found" 'no "<n> fixes re-checked" line' "$output"
expect_not_contains "large-receipt: a present rewrites checked line is found" 'no "<n> rewrites checked" line' "$output"
expect_not_contains "large-receipt: no broken pipe" "Broken pipe" "$output"

printf 'GATE: clarity\nSTATUS: PASS\nBOXES:\n- [N/A] \302\247C1: caf\351 menu has no guard chain\nFINDINGS:\n' > "$round/verdicts/clarity.txt"
output=$(LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 bash "$verifier" --later-round "$round" "$repo" 2>&1 || true)
expect_not_contains "large-receipt: a byte the locale can't read does not stop awk" "multibyte" "$output"

finish
