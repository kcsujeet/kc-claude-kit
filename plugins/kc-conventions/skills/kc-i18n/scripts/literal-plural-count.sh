#!/usr/bin/env bash
# i18n §I6: added lines in code files that pass a numeric literal as the `count` of a translation
# call, `t('x', { count: 2 })` or `formatMessage(m, { count: 0 })`, to get a word form out of a
# plural message. A fixed label is a plain string key; a plural message is read with the real
# count. Follows a call across the lines it is written on.
#
# Usage: literal-plural-count.sh <diff-file|->
# Scans only the lines the diff adds and prints `path:line: text` per hit.
# Exits 0 with or without hits, 2 on a usage error.
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=../../../scripts/lib/diff-lines.sh
. "$script_dir/../../../scripts/lib/diff-lines.sh"

if [ "$#" -ne 1 ]; then kc_require_diff_arg "$(basename "$0")" ""; fi
kc_require_diff_arg "$(basename "$0")" "$1"

kc_added_lines "$1" | awk -F '\t' '
  function parens(s,   opens, closes) {
    opens = gsub(/\(/, "(", s)
    closes = gsub(/\)/, ")", s)
    return opens - closes
  }
  $1 !~ /\.(ts|tsx|js|jsx|mjs|cjs|vue|svelte)$/ { next }
  {
    path = $1; line = $2 + 0
    text = $0
    sub(/^[^\t]*\t[^\t]*\t/, "", text)
    if (path != last_path || line != last_line + 1) depth = 0
    last_path = path; last_line = line
    call_here = match(text, /(^|[^A-Za-z0-9_])(t|\$t|tr|translate|formatMessage|t[A-Z][A-Za-z0-9_]*)\(/)
    in_call = depth > 0
    if ((call_here || in_call) && text ~ /(^|[^A-Za-z0-9_$])count[ ]*:[ ]*[0-9]+(\.[0-9]+)?[ ]*([,})]|$)/) {
      printf "%s:%d: %s\n", path, line, text
    }
    if (call_here) depth = parens(substr(text, RSTART))
    else if (in_call) { depth += parens(text); if (depth < 0) depth = 0 }
  }
'
