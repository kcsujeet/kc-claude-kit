#!/usr/bin/env bash
# naming §N6: added function declarations and arrow-function consts whose name
# does not start with a known verb, and in shell scripts each function definition
# whose snake_case name does not (`is_full_sha` and `print_env_line` start with
# one). Object methods are not matched; read them in the diff. An IIFE assigned
# to a value is matched and dismissed by hand. Extend `verbs` with the target
# repo's own verbs.
#
# Usage: unverbed-functions.sh <diff-file|->
# Scans only the lines the diff adds and prints `path:line: text` per hit.
# Exits 0 with or without hits, 2 on a usage error.
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=../../../scripts/lib/diff-lines.sh
. "$script_dir/../../../scripts/lib/diff-lines.sh"

if [ "$#" -ne 1 ]; then kc_require_diff_arg "$(basename "$0")" ""; fi
kc_require_diff_arg "$(basename "$0")" "$1"

verbs='is|has|can|should|get|set|to|use|handle|on|toggle|create|build|make|render|parse|format|resolve|compute|find|filter|map|sort|merge|apply|run|load|save|read|write|add|remove|update|delete|fetch|validate|normalize|ensure|init|detect|select|wrap|with|extract|convert|check|compare|register|reset|clear|open|close|show|hide|emit|dispatch|subscribe|print|fail|record|list|copy|move|install|start|stop|send|wait|restore'
include_pattern='(^|[^A-Za-z0-9_$])(const [a-z][A-Za-z0-9]* = (async )?(\(|[a-z][A-Za-z0-9]* =>)|function [a-z][A-Za-z0-9]* *\()'
exclude_pattern="(const|function) ($verbs)[A-Z_]"
shell_pattern='^[[:space:]]*((function[[:space:]]+)?[a-z_][a-z0-9_]*[[:space:]]*\(\)|function[[:space:]]+[a-z_][a-z0-9_]*)'
shell_exclude="^[[:space:]]*(function[[:space:]]+)?($verbs)(_[a-z0-9_]*)?([[:space:]]*\\(\\)|[[:space:]]|$)"

# The diff is read twice, so stdin is saved first.
diff_input=$1
if [ "$1" = "-" ]; then
  diff_input=$(mktemp)
  trap 'rm -f "$diff_input"' EXIT
  cat > "$diff_input"
fi
{
  kc_sweep "$diff_input" "$include_pattern" "$exclude_pattern"
  kc_sweep "$diff_input" "$shell_pattern" "$shell_exclude|$include_pattern" '\.(sh|bash)$'
} | LC_ALL=C sort -t: -k1,1 -k2,2n
