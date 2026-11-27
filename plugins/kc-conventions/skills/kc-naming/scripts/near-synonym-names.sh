#!/usr/bin/env bash
# naming §N14: boolean-shaped names declared in one file that share a content word
# ("hasFailedProcessing" and "hasProcessingError"), so the gate checks a reader can tell each one
# apart by what it tests. Each hit is a declaration in such a group, for the gate to judge.
#
# Usage: near-synonym-names.sh <diff-file|->
# A boolean-shaped name starts with is, has, should, can, did, was, will or needs (camelCase or
# snake_case). Its content words are the rest, split at case changes and underscores, lowercased,
# of 4 or more letters. Every added declaration of such a name whose content words meet another
# added one's in the same file is printed as `path:line: text`, in file and line order.
# Exits 0 with or without hits, 2 on a usage error. Portable to bash 3.2 and BSD awk.
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=../../../scripts/lib/diff-lines.sh
. "$script_dir/../../../scripts/lib/diff-lines.sh"

if [ "$#" -ne 1 ]; then kc_require_diff_arg "$(basename "$0")" ""; fi
kc_require_diff_arg "$(basename "$0")" "$1"

kc_added_lines "$1" | awk -F '\t' -v code_paths="$KC_CODE_PATHS" '
  function content_words(name, into,    spaced, parts, n, i, word) {
    split("", into)
    spaced = name
    gsub(/_/, " ", spaced)
    while (match(spaced, /[a-z0-9][A-Z]/)) spaced = substr(spaced, 1, RSTART) " " substr(spaced, RSTART + 1)
    n = split(tolower(spaced), parts, " ")
    for (i = 2; i <= n; i++) { word = parts[i]; if (length(word) >= 4) into[word] = 1 }
  }
  function flush(    i, j, w, a, b) {
    for (i = 1; i <= count; i++) for (j = i + 1; j <= count; j++) {
      content_words(names[i], a); content_words(names[j], b)
      for (w in a) if (w in b) { grouped[i] = 1; grouped[j] = 1; break }
    }
    for (i = 1; i <= count; i++) if (i in grouped) print hits[i]
    count = 0; split("", names); split("", hits); split("", grouped); split("", seen)
  }
  $1 != current_path { flush(); current_path = $1 }
  $1 !~ code_paths { next }
  {
    text = $0
    sub(/^[^\t]*\t[^\t]*\t/, "", text)
    if (!match(text, /^[ \t]*(export[ \t]+)?((const|let|var|def|function)[ \t]+)?(is|has|should|can|did|was|will|needs)(_[a-z]|[A-Z])[A-Za-z0-9_]*[ \t]*(=([^=]|$)|\(|:)/)) next
    name = substr(text, RSTART, RLENGTH)
    sub(/^[ \t]*(export[ \t]+)?((const|let|var|def|function)[ \t]+)?/, "", name)
    sub(/[ \t]*(=([^=]|$)|\(|:)$/, "", name)
    if (name in seen) next
    seen[name] = 1
    count++; names[count] = name; hits[count] = sprintf("%s:%s: %s", $1, $2, text)
  }
  END { flush() }
'
