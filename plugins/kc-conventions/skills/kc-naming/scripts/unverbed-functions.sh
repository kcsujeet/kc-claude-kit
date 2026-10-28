#!/usr/bin/env bash
# naming §N6: added function declarations and arrow-function consts whose name
# does not start with a known verb. Object methods are not matched; read them in
# the diff. An IIFE assigned to a value is matched and dismissed by hand.
# Extend the verb list in exclude_pattern with the target repo's own verbs.
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

include_pattern='(^|[^A-Za-z0-9_$])(const [a-z][A-Za-z0-9]* = (async )?(\(|[a-z][A-Za-z0-9]* =>)|function [a-z][A-Za-z0-9]* *\()'
exclude_pattern='(const|function) (is|has|can|should|get|set|to|use|handle|on|toggle|create|build|make|render|parse|format|resolve|compute|find|filter|map|sort|merge|apply|run|load|save|read|write|add|remove|update|delete|fetch|validate|normalize|ensure|init|detect|select|wrap|with|extract|convert|check|compare|register|reset|clear|open|close|show|hide|emit|dispatch|subscribe)[A-Z]'
kc_sweep "$1" "$include_pattern" "$exclude_pattern"
