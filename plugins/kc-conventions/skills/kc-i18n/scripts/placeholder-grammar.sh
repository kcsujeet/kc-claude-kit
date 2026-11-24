#!/usr/bin/env bash
# i18n §I9: added lines in locale JSON files whose message puts grammar on a placeholder: a
# possessive (`{name}'s plan`) or an ordinal suffix (`{count}th`). A translator can't inflect a
# value filled in at run time, so the sentence is written with the placeholder standing alone.
#
# Usage: placeholder-grammar.sh <diff-file|->
# Scans only the lines the diff adds, in .json files under a locale, messages, i18n, translations
# or lang folder, and prints `path:line: text` per hit. Exits 0 with or without hits, 2 on a usage error.
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=../../../scripts/lib/diff-lines.sh
. "$script_dir/../../../scripts/lib/diff-lines.sh"

if [ "$#" -ne 1 ]; then kc_require_diff_arg "$(basename "$0")" ""; fi
kc_require_diff_arg "$(basename "$0")" "$1"

include_pattern="[{][A-Za-z_][A-Za-z0-9_]*[}]('s|’s|st|nd|rd|th)([^A-Za-z]|$)"
path_pattern='(^|/)(locales?|messages|i18n|translations?|lang)/.*\.json$'
kc_sweep "$1" "$include_pattern" "" "$path_pattern"
