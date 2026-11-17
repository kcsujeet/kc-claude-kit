#!/usr/bin/env bash
# Tests scripts/check-cost-settings.sh: each finding's full line (a mid- or small-tier subagent
# default, a file that is not JSON), file and environment precedence, a missing file, and the exit
# when jq is missing.
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
run_with_clean_env() { env -u CLAUDE_CODE_SUBAGENT_MODEL "$@"; }
write_settings_file() { printf '%s\n' "$2" > "$work_dir/$1"; echo "$work_dir/$1"; }

weak_line() { echo "subagents: CLAUDE_CODE_SUBAGENT_MODEL=$1 runs every agent spawned without a model, deciding ones included, below the strongest tier. Set it to the strongest (opus) or remove it, and name a mid model per agent for hands-on work."; }

strongest_settings=$(write_settings_file strongest.json '{"env":{"CLAUDE_CODE_SUBAGENT_MODEL":"opus"}}')
mid_subagent_settings=$(write_settings_file mid.json '{"env":{"CLAUDE_CODE_SUBAGENT_MODEL":"sonnet"}}')
haiku_subagent_settings=$(write_settings_file haiku.json '{"env":{"CLAUDE_CODE_SUBAGENT_MODEL":"haiku"}}')
no_subagent_settings=$(write_settings_file no-subagent.json '{"model":"opus[1m]"}')
broken_settings=$(write_settings_file broken.json '{bad')

expect "strongest subagent model: silent" "" "$(run_with_clean_env bash "$script" "$strongest_settings")"
expect "mid-tier subagent default" "$(weak_line sonnet)" "$(run_with_clean_env bash "$script" "$mid_subagent_settings")"
expect "small-tier subagent default" "$(weak_line haiku)" "$(run_with_clean_env bash "$script" "$haiku_subagent_settings")"
expect "no subagent default: silent" "" "$(run_with_clean_env bash "$script" "$no_subagent_settings")"

expect "later file wins over an earlier one" "" "$(run_with_clean_env bash "$script" "$mid_subagent_settings" "$strongest_settings")"
expect "earlier strongest file, later mid one" "$(weak_line sonnet)" \
  "$(run_with_clean_env bash "$script" "$strongest_settings" "$mid_subagent_settings")"
expect "environment mid subagent model wins over a file's strongest" "$(weak_line claude-sonnet-5-5)" \
  "$(run_with_clean_env CLAUDE_CODE_SUBAGENT_MODEL=claude-sonnet-5-5 bash "$script" "$strongest_settings")"
expect "environment strongest subagent model wins over a file's mid: silent" "" \
  "$(run_with_clean_env CLAUDE_CODE_SUBAGENT_MODEL=claude-opus-5-5 bash "$script" "$mid_subagent_settings")"

expect "file that is not JSON is named and skipped" "settings: $broken_settings is not valid JSON, so its settings were not read. Fix the file." \
  "$(run_with_clean_env bash "$script" "$strongest_settings" "$broken_settings")"
expect "missing file is skipped" "" "$(run_with_clean_env bash "$script" "$work_dir/missing.json" "$strongest_settings")"

bin_without_jq="$work_dir/bin"
mkdir -p "$bin_without_jq"
ln -s "$(command -v bash)" "$bin_without_jq/bash"
no_jq_status=0
no_jq_stdout=$(PATH="$bin_without_jq" bash "$script" "$strongest_settings" 2>"$work_dir/no-jq.err") || no_jq_status=$?
expect "jq missing: exit 2, nothing on stdout, the reason on stderr" \
  "2||check-cost-settings: jq is required; install it (for example: brew install jq)" \
  "$no_jq_status|$no_jq_stdout|$(cat "$work_dir/no-jq.err")"

echo "$((cases - failures))/$cases passed"
[ "$failures" -eq 0 ]
