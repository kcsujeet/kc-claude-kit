#!/usr/bin/env bash
# clarity §C17: added lines holding an explicit `any`: `: any`, `<any>`,
# `as any`, or `any[]`.
#
# Usage: any-types.sh <diff-file|->
# Scans only the lines the diff adds and prints `path:line: text` per hit.
# Exits 0 with or without hits, 2 on a usage error.
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=../../../scripts/lib/diff-lines.sh
. "$script_dir/../../../scripts/lib/diff-lines.sh"

if [ "$#" -ne 1 ]; then kc_require_diff_arg "$(basename "$0")" ""; fi
kc_require_diff_arg "$(basename "$0")" "$1"

include_pattern='(: *any([^A-Za-z0-9_$]|$)|<any>|(^|[^A-Za-z0-9_$])as any([^A-Za-z0-9_$]|$)|(^|[^A-Za-z0-9_$])any\[\])'
kc_sweep "$1" "$include_pattern"
