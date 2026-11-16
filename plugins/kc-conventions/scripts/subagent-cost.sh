#!/usr/bin/env bash
# Shows what each agent transcript cost: calls and token sums, so a long-running agent stands out.
#
# Usage: subagent-cost.sh <path>...
#   Each path is a transcript .jsonl file, or a folder searched recursively for *.jsonl (for
#   example a session's subagents/ folder).
#
# Prints a TSV with a header: one row per file (its basename) and a TOTAL row, sorted by cache
# reads, largest first. Columns: calls (assistant messages carrying message.usage),
# cache_read, cache_creation, input, output (sums), max_context (the largest single call's
# cache_read + cache_creation + input). Lines without usage are ignored.
# Exit 2 with usage on no arguments or a missing path; needs jq.
set -euo pipefail

usage() { echo "usage: $(basename "$0") <transcript.jsonl|folder>..." >&2; exit 2; }

[ $# -gt 0 ] || usage
command -v jq >/dev/null 2>&1 || { echo "subagent-cost: jq is required but was not found; install it (for example: brew install jq)" >&2; exit 2; }

files=()
for path in "$@"; do
  if [ -d "$path" ]; then
    while IFS= read -r found; do files+=("$found"); done < <(find "$path" -type f -name '*.jsonl' | sort)
  elif [ -f "$path" ]; then
    files+=("$path")
  else
    echo "subagent-cost: no such file or folder: $path" >&2
    usage
  fi
done

[ ${#files[@]} -gt 0 ] || { echo "subagent-cost: no .jsonl files found" >&2; exit 2; }

rows=$(for file in "${files[@]}"; do
  jq -R -s -r --arg name "$(basename "$file")" '
    [split("\n")[] | fromjson? | select(type == "object") | (.message.usage? // empty) | select(type == "object")
     | {r: (.cache_read_input_tokens // 0), c: (.cache_creation_input_tokens // 0), i: (.input_tokens // 0), o: (.output_tokens // 0)}] as $u
    | [$name, ($u | length), ($u | map(.r) | add // 0), ($u | map(.c) | add // 0), ($u | map(.i) | add // 0),
       ($u | map(.o) | add // 0), ($u | map(.r + .c + .i) | max // 0)] | @tsv
  ' "$file"
done)

printf 'file\tcalls\tcache_read\tcache_creation\tinput\toutput\tmax_context\n'
printf '%s\n' "$rows" | sort -t "$(printf '\t')" -k3,3nr
printf '%s\n' "$rows" | awk -F '\t' '
  { for (i = 2; i <= 6; i++) sum[i] += $i; if ($7 > max) max = $7 }
  END { printf "TOTAL\t%d\t%d\t%d\t%d\t%d\t%d\n", sum[2], sum[3], sum[4], sum[5], sum[6], max }'
