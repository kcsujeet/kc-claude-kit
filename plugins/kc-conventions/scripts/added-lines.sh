#!/usr/bin/env bash
# Citation map: prints every line a unified diff adds as `path:line: text`, where
# `line` is the line number in the new-side source file, not in the diff file.
# Gates cite findings from this output so a line number always points into the
# repo at the head SHA.
#
# Usage: added-lines.sh <diff-file|->
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/diff-lines.sh
. "$script_dir/lib/diff-lines.sh"

kc_require_diff_arg "added-lines.sh" "${1:-}"
kc_added_lines "$1" | awk -F '\t' '{ text = $0; sub(/^[^\t]*\t[^\t]*\t/, "", text); print $1 ":" $2 ": " text }'
