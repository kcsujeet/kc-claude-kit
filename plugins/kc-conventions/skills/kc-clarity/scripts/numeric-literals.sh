#!/usr/bin/env bash
# clarity §C16: added lines in code files holding a bare number other than 0 or 1,
# so each is named or its meaning is plain on sight. Skipped: comment lines; a
# line that names the number itself (a declaration whose value is just the
# number, an UPPER_CASE constant, a shell variable set to a number); an exact
# expected value in an assertion (`toBe(3)`, `to eq(3)`); and digits inside a
# name, a version, a unit (`16px`) or a hyphenated class (`p-4`). A number
# inside a string over-matches and is dismissed by hand.
#
# Usage: numeric-literals.sh <diff-file|->
# Scans only the lines the diff adds and prints `path:line: text` per hit.
# Exits 0 with or without hits, 2 on a usage error.
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=../../../scripts/lib/diff-lines.sh
. "$script_dir/../../../scripts/lib/diff-lines.sh"

if [ "$#" -ne 1 ]; then kc_require_diff_arg "$(basename "$0")" ""; fi
kc_require_diff_arg "$(basename "$0")" "$1"

include_pattern='(^|[^A-Za-z0-9_$.#-])([2-9]|[1-9][0-9_]+|[0-9]*\.[0-9]+)([^A-Za-z0-9_.]|$)'
comment_line='^[[:space:]]*(//|#|\*|/\*|<!--)'
named_constant='^[[:space:]]*((export|const|let|var|readonly|static|final|private|public|protected)[[:space:]]+)*[A-Z][A-Z0-9_]*[[:space:]]*(:[^=]*)?='
named_number='^[[:space:]]*((export|const|let|var|readonly|static|final|private|public|protected)[[:space:]]+)+[A-Za-z_$][A-Za-z0-9_$]*[[:space:]]*(:[^=]*)?=[[:space:]]*-?[0-9][0-9_.]*[[:space:]]*;?[[:space:]]*$'
shell_variable='^[[:space:]]*((local|readonly)[[:space:]]+)?[a-z_][a-z0-9_]*=[0-9]'
expected_value='\.(toBe|toEqual|toStrictEqual|toHaveLength|toHaveBeenCalledTimes|toBeCloseTo)\(|[[:space:]](to|not_to|to_not)[[:space:]]+(eq|eql|equal|be)[[:space:](]'
kc_sweep "$1" "$include_pattern" "$comment_line|$named_constant|$named_number|$shell_variable|$expected_value" "$KC_CODE_PATHS"
