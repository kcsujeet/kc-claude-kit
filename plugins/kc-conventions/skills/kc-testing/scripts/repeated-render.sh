#!/usr/bin/env bash
# testing §T4: a component rendered inline (`render(<X …/>)`, `mount(<X …/>)`) on 2+ added lines of
# one test file. Repeated setup is a local helper even when each copy is one call. A helper's own
# render (`const renderX = () => render(<X />)`) is the helper, not a copy, so it is not counted.
#
# Usage: repeated-render.sh <diff-file|->
# Scans only the lines the diff adds in test files (`KC_TEST_PATHS` in lib/diff-lines.sh) and prints
# `path:line: text` for every inline render of a component that appears on 2+ of them in a file.
# Exits 0 with or without hits, 2 on a usage error.
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=../../../scripts/lib/diff-lines.sh
. "$script_dir/../../../scripts/lib/diff-lines.sh"

if [ "$#" -ne 1 ]; then kc_require_diff_arg "$(basename "$0")" ""; fi
kc_require_diff_arg "$(basename "$0")" "$1"

kc_added_lines "$1" | KC_PATHS=$KC_TEST_PATHS awk -F '\t' '
  $1 !~ ENVIRON["KC_PATHS"] { next }
  {
    text = $0
    sub(/^[^\t]*\t[^\t]*\t/, "", text)
    if (text ~ /(=>|return)[ ]*\(?[ ]*(render|mount)[A-Za-z]*\(/) next
    if (!match(text, /(^|[^A-Za-z0-9_])(render|mount)[A-Za-z]*\([ ]*<[A-Z][A-Za-z0-9_.]*/)) next
    component = substr(text, RSTART, RLENGTH)
    sub(/^.*</, "", component)
    key = $1 SUBSEP component
    seen[key]++
    n++
    hit_key[n] = key
    hit_out[n] = $1 ":" $2 ": " text
  }
  END { for (i = 1; i <= n; i++) if (seen[hit_key[i]] >= 2) print hit_out[i] }
'
