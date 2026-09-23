#!/usr/bin/env bash
# clarity §C4 and §C17: added lines holding a type assertion, including
# `as string`, `as const` and `as unknown as T`. Import and export aliases
# (`import { x as y }`) and the word "as" in prose over-match and are dismissed
# by hand.
#
# Usage: as-casts.sh <diff-file|->
# Scans only the lines the diff adds and prints `path:line: text` per hit.
# Exits 0 with or without hits, 2 on a usage error.
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=../../../scripts/lib/diff-lines.sh
. "$script_dir/../../../scripts/lib/diff-lines.sh"

if [ "$#" -ne 1 ]; then kc_require_diff_arg "$(basename "$0")" ""; fi
kc_require_diff_arg "$(basename "$0")" "$1"

include_pattern='(^|[^A-Za-z0-9_$])as [A-Za-z]'
kc_sweep "$1" "$include_pattern"
