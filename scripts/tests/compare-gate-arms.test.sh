#!/usr/bin/env bash
# Tests scripts/compare-gate-arms.sh against two fixture eval results and their traces.
set -euo pipefail

scripts_dir="$(cd "$(dirname "$0")/.." && pwd)"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
passes=0
failures=0

check() { # <label> <want status> <text the output holds> <args...>
  local label=$1 want=$2 text=$3 output status=0
  shift 3
  output=$(bash "$scripts_dir/compare-gate-arms.sh" "$@" 2>&1) || status=$?
  if [ "$status" -eq "$want" ] && printf '%s' "$output" | grep -qF -- "$text"; then
    echo "ok   $label"
    passes=$((passes + 1))
  else
    echo "FAIL $label (want status $want with: $text; got status $status: $output)"
    failures=$((failures + 1))
  fi
}

# A trace whose result line carries <input> input and <output> output tokens and <agents> subagents.
make_trace() {
  printf '{"type":"result","modelUsage":{"m":{"inputTokens":%s,"outputTokens":%s,"cacheReadInputTokens":0,"cacheCreationInputTokens":0}},"subagent_stats":{"spawned":%s}}\n' "$2" "$3" "$4" > "$1"
}
# make_result <file> <case> <trace> <cost> <grader=passed>...: one case, one run (no graders: a run that errored).
make_result() {
  local file=$1 case_name=$2 trace=$3 cost=$4 graders='' pair
  shift 4
  for pair in "$@"; do
    graders+="{\"name\":\"${pair%%=*}\",\"passed\":${pair##*=},\"scored\":true},"
  done
  printf '{"cases":[{"name":"%s","arms":{"with":[{"costUsd":%s,"tracePath":"%s","graders":[%s]}]}}]}\n' \
    "$case_name" "$cost" "$trace" "${graders%,}" > "$file"
}

make_trace "$work_dir/pg.jsonl" 1000 500 7
make_trace "$work_dir/cb.jsonl" 300 200 1
make_result "$work_dir/pg.json" seeded "$work_dir/pg.jsonl" 1.50 a=true b=true c=true
make_result "$work_dir/same.json" combined-seeded "$work_dir/cb.jsonl" 0.50 a=true b=true c=true
make_result "$work_dir/worse.json" combined-seeded "$work_dir/cb.jsonl" 0.50 a=true b=false c=true
make_result "$work_dir/gone.json" combined-seeded "$work_dir/missing.jsonl" 0.50 a=true b=true c=true
make_result "$work_dir/other.json" combined-unrelated "$work_dir/cb.jsonl" 0.50 a=true

check "equal recall: exits 0 and says nothing was lost" 0 "combined lost no grader" "$work_dir/pg.json" "$work_dir/same.json"
check "per-gate tokens are summed over input and output" 0 "1500" "$work_dir/pg.json" "$work_dir/same.json"
check "combined tokens and agents are its own" 0 "500" "$work_dir/pg.json" "$work_dir/same.json"
check "recall shows as a percentage" 0 "100%" "$work_dir/pg.json" "$work_dir/same.json"
check "a lost grader exits 1 and is named" 1 "lost by combined: b" "$work_dir/pg.json" "$work_dir/worse.json"
check "a lost grader lowers the recall" 1 "67%" "$work_dir/pg.json" "$work_dir/worse.json"
check "a missing trace shows n/a" 0 "n/a" "$work_dir/pg.json" "$work_dir/gone.json"
check "an unpaired case is reported and exits 1" 1 "no combined case of this name" "$work_dir/pg.json" "$work_dir/other.json"
make_result "$work_dir/empty.json" combined-seeded "$work_dir/cb.jsonl" 0
check "a combined run with no grader results exits 1" 1 "no combined grader result" "$work_dir/pg.json" "$work_dir/empty.json"
check "no arguments exits 2" 2 "usage"
check "a missing file exits 2" 2 "no such file" "$work_dir/pg.json" "$work_dir/none.json"

echo "$passes passed, $failures failed"
[ "$failures" -eq 0 ]
