#!/usr/bin/env bash
# Tests scripts/subagent-cost.sh: per-file sums, the largest single-call context, the TOTAL row,
# sorting by cache reads, folder recursion, lines without usage, and the usage errors.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
script="$(dirname "$tests_dir")/scripts/subagent-cost.sh"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

failures=0
cases=0
expect() {
  local label=$1 expected=$2 actual=$3
  cases=$((cases + 1))
  if [ "$actual" = "$expected" ]; then
    echo "ok   $label"
  else
    echo "FAIL $label"
    echo "     expected: $expected"
    echo "     actual:   $actual"
    failures=$((failures + 1))
  fi
}
tab=$(printf '\t')
usage_line() { printf '{"type":"assistant","message":{"usage":{"cache_read_input_tokens":%s,"cache_creation_input_tokens":%s,"input_tokens":%s,"output_tokens":%s}}}\n' "$1" "$2" "$3" "$4"; }

mkdir -p "$work_dir/sub/deep"
{
  usage_line 100 10 1 5
  echo '{"type":"user","message":{"content":"hello"}}'
  echo 'not json at all'
  echo '{"type":"assistant","message":{"content":"no usage here"}}'
  usage_line 300 20 2 7
} > "$work_dir/small.jsonl"
{
  usage_line 1000 100 3 50
  usage_line 2000 0 4 60
  usage_line 500 900 5 70
} > "$work_dir/sub/big.jsonl"
usage_line 1 2 3 4 > "$work_dir/sub/deep/nested.jsonl"
echo "ignored" > "$work_dir/sub/notes.txt"

header="file${tab}calls${tab}cache_read${tab}cache_creation${tab}input${tab}output${tab}max_context"

expect "one file: header, row, TOTAL; sums, max context, lines without usage ignored" \
  "$header
small.jsonl${tab}2${tab}400${tab}30${tab}3${tab}12${tab}322
TOTAL${tab}2${tab}400${tab}30${tab}3${tab}12${tab}322" \
  "$(bash "$script" "$work_dir/small.jsonl")"

expect "two files: sorted by cache reads descending, TOTAL sums and takes the largest context" \
  "$header
big.jsonl${tab}3${tab}3500${tab}1000${tab}12${tab}180${tab}2004
small.jsonl${tab}2${tab}400${tab}30${tab}3${tab}12${tab}322
TOTAL${tab}5${tab}3900${tab}1030${tab}15${tab}192${tab}2004" \
  "$(bash "$script" "$work_dir/small.jsonl" "$work_dir/sub/big.jsonl")"

expect "folder: recurses into subfolders, takes only .jsonl" \
  "$header
big.jsonl${tab}3${tab}3500${tab}1000${tab}12${tab}180${tab}2004
nested.jsonl${tab}1${tab}1${tab}2${tab}3${tab}4${tab}6
TOTAL${tab}4${tab}3501${tab}1002${tab}15${tab}184${tab}2004" \
  "$(bash "$script" "$work_dir/sub")"

set +e
bash "$script" >/dev/null 2>"$work_dir/err"; code=$?
set -e
expect "no arguments: exit 2" "2" "$code"
expect "no arguments: usage on stderr" "usage:" "$(cut -c1-6 "$work_dir/err")"

set +e
bash "$script" "$work_dir/missing.jsonl" >/dev/null 2>"$work_dir/err"; code=$?
set -e
expect "missing path: exit 2" "2" "$code"
expect "missing path: names the path" "yes" "$(grep -q 'missing.jsonl' "$work_dir/err" && echo yes || echo no)"

set +e
PATH="$work_dir/nobin" /bin/bash "$script" "$work_dir/small.jsonl" >/dev/null 2>"$work_dir/err"; code=$?
set -e
expect "jq missing: exit 2" "2" "$code"
expect "jq missing: says jq is required" "yes" "$(grep -q 'jq is required' "$work_dir/err" && echo yes || echo no)"

echo
echo "$((cases - failures))/$cases passed"
[ "$failures" -eq 0 ]
