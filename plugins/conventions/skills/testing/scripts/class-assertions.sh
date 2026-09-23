#!/usr/bin/env bash
# testing §T2: added lines in test files (`*.test.*`, `*.spec.*`,
# `__tests__/`) that assert on or reference a class name.
#
# Usage: class-assertions.sh <diff-file|->
# Scans only the lines the diff adds and prints `path:line: text` per hit.
# Exits 0 with or without hits, 2 on a usage error.
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=../../../scripts/lib/diff-lines.sh
. "$script_dir/../../../scripts/lib/diff-lines.sh"

if [ "$#" -ne 1 ]; then kc_require_diff_arg "$(basename "$0")" ""; fi
kc_require_diff_arg "$(basename "$0")" "$1"

include_pattern='(toHaveClass|className|classList)'
path_pattern='(\.(test|spec)\.[A-Za-z0-9]+$|(^|/)__tests__/)'
kc_sweep "$1" "$include_pattern" "${exclude_pattern:-}" "$path_pattern"
