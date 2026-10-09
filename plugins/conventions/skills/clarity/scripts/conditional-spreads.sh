#!/usr/bin/env bash
# clarity §C19: added lines holding a conditional spread. Three shapes are
# matched: a spread of a parenthesized expression (`...(flag && { key })`,
# `...(flag ? { key } : {})`), an object built conditionally to be spread later
# (`const extra = flag && { key }`), and a ternary whose other branch is an
# empty object (`flag ? { key } : {}`). A spread of a plain call
# (`...(await load())`) over-matches and is dismissed by hand.
#
# Usage: conditional-spreads.sh <diff-file|->
# Scans only the lines the diff adds and prints `path:line: text` per hit.
# Exits 0 with or without hits, 2 on a usage error.
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=../../../scripts/lib/diff-lines.sh
. "$script_dir/../../../scripts/lib/diff-lines.sh"

if [ "$#" -ne 1 ]; then kc_require_diff_arg "$(basename "$0")" ""; fi
kc_require_diff_arg "$(basename "$0")" "$1"

spread_pattern='[.][.][.][(]'
built_later_pattern='(^|[^=!<>])=[^=>].*&&[ ]*[{]'
empty_branch_pattern='[?][^?:]*:[ ]*[{][ ]*[}]'
kc_sweep "$1" "$spread_pattern|$built_later_pattern|$empty_branch_pattern"
