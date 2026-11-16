#!/usr/bin/env bash
# Tests scripts/check-cost-settings.sh: silent when capped and the subagent default is a mid model;
# flags a missing cap, a cap too high, a cap that is not a count, and a strongest-tier subagent
# default; later files and the environment win; "200k" is read as a count; 1M disabled or a
# percent override counts as a cap.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
script="$(dirname "$tests_dir")/scripts/check-cost-settings.sh"
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
first_word() { awk '{print $1}' | tr '\n' ' ' | sed 's/ $//'; }
run() { env -u CLAUDE_CODE_AUTO_COMPACT_WINDOW -u CLAUDE_CODE_DISABLE_1M_CONTEXT -u CLAUDE_AUTOCOMPACT_PCT_OVERRIDE -u CLAUDE_CODE_SUBAGENT_MODEL "$@"; }
settings() { printf '%s\n' "$2" > "$work_dir/$1"; echo "$work_dir/$1"; }

good=$(settings good.json '{"autoCompactWindow":200000,"env":{"CLAUDE_CODE_SUBAGENT_MODEL":"sonnet"}}')
expect "capped window and mid subagent model: silent" "" "$(run bash "$script" "$good")"

none=$(settings none.json '{"model":"opus[1m]"}')
expect "no cap: flags context" "context:" "$(run bash "$script" "$none" | first_word)"

high=$(settings high.json '{"autoCompactWindow":800000}')
expect "cap above the limit: flags context" "context:" "$(run bash "$script" "$high" | first_word)"

word=$(settings word.json '{"autoCompactWindow":"large"}')
expect "cap that is not a count: flags context" "context:" "$(run bash "$script" "$word" | first_word)"

short=$(settings short.json '{"autoCompactWindow":"200k"}')
expect "\"200k\" is read as 200000: silent" "" "$(run bash "$script" "$short")"

env_cap=$(settings envcap.json '{"env":{"CLAUDE_CODE_AUTO_COMPACT_WINDOW":"150000"}}')
expect "cap in settings env: silent" "" "$(run bash "$script" "$env_cap")"

no1m=$(settings no1m.json '{"env":{"CLAUDE_CODE_DISABLE_1M_CONTEXT":"1"}}')
expect "1M disabled counts as a cap: silent" "" "$(run bash "$script" "$no1m")"

pct=$(settings pct.json '{"env":{"CLAUDE_AUTOCOMPACT_PCT_OVERRIDE":"20"}}')
expect "percent override counts as a cap: silent" "" "$(run bash "$script" "$pct")"

strong=$(settings strong.json '{"autoCompactWindow":200000,"env":{"CLAUDE_CODE_SUBAGENT_MODEL":"opus"}}')
expect "strongest-tier subagent default: flags subagents" "subagents:" "$(run bash "$script" "$strong" | first_word)"

expect "later file wins over an earlier one" "" "$(run bash "$script" "$none" "$good")"
expect "earlier good file, later uncapped high one: flags" "context:" "$(run bash "$script" "$good" "$high" | first_word)"

expect "environment wins over files" "" "$(run CLAUDE_CODE_AUTO_COMPACT_WINDOW=200000 bash "$script" "$none")"
expect "environment strong subagent model is flagged" "subagents:" "$(run CLAUDE_CODE_SUBAGENT_MODEL=claude-opus-5-5 bash "$script" "$good" | first_word)"

expect "both problems: two lines" "context: subagents:" "$(run bash "$script" "$none" "$(settings both.json '{"env":{"CLAUDE_CODE_SUBAGENT_MODEL":"fable"}}')" | first_word)"

expect "missing file is skipped" "context:" "$(run bash "$script" "$work_dir/missing.json" | first_word)"

echo "$((cases - failures))/$cases passed"
[ "$failures" -eq 0 ]
