#!/usr/bin/env bash
# naming §N5: every added declaration (`const`, `let`, `var`, `function`, `def`,
# `func`, or a returned object key) whose name starts lowercase, so each new
# identifier is checked for a subject and for collisions elsewhere in the repo.
#
# Usage: bare-word-declarations.sh <diff-file|->
# Scans only the lines the diff adds and prints `path:line: text` per hit.
# Exits 0 with or without hits, 2 on a usage error.
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=../../../scripts/lib/diff-lines.sh
. "$script_dir/../../../scripts/lib/diff-lines.sh"

if [ "$#" -ne 1 ]; then kc_require_diff_arg "$(basename "$0")" ""; fi
kc_require_diff_arg "$(basename "$0")" "$1"

include_pattern='(^|[^A-Za-z0-9_$])(const|let|var|function|def|func|return \{) [a-z][a-zA-Z_]*'
kc_sweep "$1" "$include_pattern"
