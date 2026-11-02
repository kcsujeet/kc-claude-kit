#!/usr/bin/env bash
# naming §N5: every added declaration (`const`, `let`, `var`, `function`, `def`,
# `func`, or a returned object key) whose name starts lowercase, so each new
# identifier is checked for a subject and for collisions elsewhere in the repo.
# In shell scripts also an assignment, `local`, `readonly` or `declare` at the
# start of a line, a function definition, and a `for` loop's variable.
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
shell_pattern='^[[:space:]]*((local|readonly|declare)([[:space:]]+-[a-zA-Z]+)*[[:space:]]+[a-z_][a-z0-9_]*|[a-z_][a-z0-9_]*=|(function[[:space:]]+)?[a-z_][a-z0-9_]*[[:space:]]*\(\)|for[[:space:]]+[a-z_][a-z0-9_]*[[:space:]]+in([[:space:]]|$))'

# The diff is read twice, so stdin is saved first.
diff_input=$1
if [ "$1" = "-" ]; then
  diff_input=$(mktemp)
  trap 'rm -f "$diff_input"' EXIT
  cat > "$diff_input"
fi
{
  kc_sweep "$diff_input" "$include_pattern"
  kc_sweep "$diff_input" "$shell_pattern" "$include_pattern" '\.(sh|bash)$'
} | LC_ALL=C sort -t: -k1,1 -k2,2n
