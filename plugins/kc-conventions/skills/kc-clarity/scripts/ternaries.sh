#!/usr/bin/env bash
# clarity §C15: added lines holding a ternary `?`. A `?` that is part of `?.`,
# `??`, or an optional `?:` is skipped; a line holding both an optional property
# and a real ternary is still a hit, and so is a `?` the formatter left at the end
# of a line. A `?` inside a string or regex over-matches and is dismissed by hand.
#
# Usage: ternaries.sh <diff-file|->
# Scans only the lines the diff adds and prints `path:line: text` per hit.
# Exits 0 with or without hits, 2 on a usage error.
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=../../../scripts/lib/diff-lines.sh
. "$script_dir/../../../scripts/lib/diff-lines.sh"

if [ "$#" -ne 1 ]; then kc_require_diff_arg "$(basename "$0")" ""; fi
kc_require_diff_arg "$(basename "$0")" "$1"

include_pattern='(^|[^?])[?]([^.?:]|$)'
kc_sweep "$1" "$include_pattern"
