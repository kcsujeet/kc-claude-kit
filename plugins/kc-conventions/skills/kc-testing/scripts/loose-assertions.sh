#!/usr/bin/env bash
# testing §T6: added lines in test files (`KC_TEST_PATHS` in lib/diff-lines.sh)
# holding a bound or truthiness matcher where an exact value may be known.
# `toBeCloseTo` is the stated-tolerance form and is not matched.
#
# Usage: loose-assertions.sh <diff-file|->
# Scans only the lines the diff adds and prints `path:line: text` per hit.
# Exits 0 with or without hits, 2 on a usage error.
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=../../../scripts/lib/diff-lines.sh
. "$script_dir/../../../scripts/lib/diff-lines.sh"

if [ "$#" -ne 1 ]; then kc_require_diff_arg "$(basename "$0")" ""; fi
kc_require_diff_arg "$(basename "$0")" "$1"

include_pattern='(toBeGreaterThan|toBeLessThan|toBeGreaterThanOrEqual|toBeLessThanOrEqual|toBeTruthy|toBeFalsy|toBeDefined|not\.toBeNull|not\.toBeUndefined)'
kc_sweep "$1" "$include_pattern" "" "$KC_TEST_PATHS"
