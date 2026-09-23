#!/usr/bin/env bash
# structure §S5: added lines holding a `switch`, an `else if`, or an IIFE
# assigned to a value (an IIFE that picks one value from a discriminant is a
# `switch` in disguise).
#
# Usage: switch-else-if-iife.sh <diff-file|->
# Scans only the lines the diff adds and prints `path:line: text` per hit.
# Exits 0 with or without hits, 2 on a usage error.
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=../../../scripts/lib/diff-lines.sh
. "$script_dir/../../../scripts/lib/diff-lines.sh"

if [ "$#" -ne 1 ]; then kc_require_diff_arg "$(basename "$0")" ""; fi
kc_require_diff_arg "$(basename "$0")" "$1"

include_pattern='(^|[^A-Za-z0-9_$])switch *\(|(^|[^A-Za-z0-9_$])else +if *\(|= *\((async *)?\(\) *=>'
kc_sweep "$1" "$include_pattern"
