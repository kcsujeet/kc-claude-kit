#!/usr/bin/env bash
# react §R16: added lines calling `useMemo` or `useCallback`, so each memo is
# checked for whether its cache can hit.
#
# Usage: memo-hooks.sh <diff-file|->
# Scans only the lines the diff adds and prints `path:line: text` per hit.
# Exits 0 with or without hits, 2 on a usage error.
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=../../../scripts/lib/diff-lines.sh
. "$script_dir/../../../scripts/lib/diff-lines.sh"

if [ "$#" -ne 1 ]; then kc_require_diff_arg "$(basename "$0")" ""; fi
kc_require_diff_arg "$(basename "$0")" "$1"

include_pattern='(^|[^A-Za-z0-9_$])(useMemo|useCallback)([^A-Za-z0-9_$]|$)'
kc_sweep "$1" "$include_pattern"
