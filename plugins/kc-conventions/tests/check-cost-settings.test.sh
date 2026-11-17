#!/usr/bin/env bash
# Tests scripts/check-cost-settings.sh: each finding's full line (no cap, a cap too high, a cap or
# percent that is not a number, a mid- or small-tier subagent default, a file that is not JSON), the
# settings that count as a cap ("200k", "1M", 1M disabled, a low percent), file and environment
# precedence, a missing file, and the exit when jq is missing.
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
run_with_clean_env() { env -u CLAUDE_CODE_AUTO_COMPACT_WINDOW -u CLAUDE_CODE_DISABLE_1M_CONTEXT -u CLAUDE_AUTOCOMPACT_PCT_OVERRIDE -u CLAUDE_CODE_SUBAGENT_MODEL "$@"; }
write_settings_file() { printf '%s\n' "$2" > "$work_dir/$1"; echo "$work_dir/$1"; }

no_cap_line='context: no auto-compact cap, so a 1M-window session re-reads up to 1M cached tokens per call. Set "autoCompactWindow": 200000 in ~/.claude/settings.json.'
too_high_line() { echo "context: auto-compaction fires at about $1 tokens, above 300000, so each call can re-read that much. Set \"autoCompactWindow\": 200000."; }
weak_line() { echo "subagents: CLAUDE_CODE_SUBAGENT_MODEL=$1 runs every agent spawned without a model, deciding ones included, below the strongest tier. Set it to the strongest (opus) or remove it, and name a mid model per agent for hands-on work."; }

capped_settings=$(write_settings_file capped.json '{"autoCompactWindow":200000,"env":{"CLAUDE_CODE_SUBAGENT_MODEL":"opus"}}')
uncapped_settings=$(write_settings_file uncapped.json '{"model":"opus[1m]"}')
over_limit_settings=$(write_settings_file over-limit.json '{"autoCompactWindow":800000}')
non_numeric_cap_settings=$(write_settings_file non-numeric.json '{"autoCompactWindow":"large"}')
decimal_cap_settings=$(write_settings_file decimal.json '{"autoCompactWindow":"1.5M"}')
k_suffix_cap_settings=$(write_settings_file k-suffix.json '{"autoCompactWindow":"200k"}')
m_suffix_cap_settings=$(write_settings_file m-suffix.json '{"autoCompactWindow":"1M"}')
env_cap_settings=$(write_settings_file env-cap.json '{"env":{"CLAUDE_CODE_AUTO_COMPACT_WINDOW":"150000"}}')
disabled_1m_settings=$(write_settings_file disabled-1m.json '{"env":{"CLAUDE_CODE_DISABLE_1M_CONTEXT":"1"}}')
low_pct_settings=$(write_settings_file low-pct.json '{"env":{"CLAUDE_AUTOCOMPACT_PCT_OVERRIDE":"20"}}')
high_pct_settings=$(write_settings_file high-pct.json '{"env":{"CLAUDE_AUTOCOMPACT_PCT_OVERRIDE":"95"}}')
word_pct_settings=$(write_settings_file word-pct.json '{"autoCompactWindow":200000,"env":{"CLAUDE_AUTOCOMPACT_PCT_OVERRIDE":"most"}}')
mid_subagent_settings=$(write_settings_file mid.json '{"autoCompactWindow":200000,"env":{"CLAUDE_CODE_SUBAGENT_MODEL":"sonnet"}}')
haiku_subagent_settings=$(write_settings_file haiku.json '{"env":{"CLAUDE_CODE_SUBAGENT_MODEL":"haiku"}}')
capped_no_subagent_settings=$(write_settings_file capped-no-subagent.json '{"autoCompactWindow":200000}')
broken_settings=$(write_settings_file broken.json '{bad')

expect "capped window and strongest subagent model: silent" "" "$(run_with_clean_env bash "$script" "$capped_settings")"
expect "no cap" "$no_cap_line" "$(run_with_clean_env bash "$script" "$uncapped_settings")"
expect "cap above the limit" "$(too_high_line 800000)" "$(run_with_clean_env bash "$script" "$over_limit_settings")"
expect "cap that is not a count" 'context: autoCompactWindow "large" is not a token count. Set "autoCompactWindow": 200000.' \
  "$(run_with_clean_env bash "$script" "$non_numeric_cap_settings")"
expect "decimal with a suffix is not a count, and the script still exits 0" \
  'context: autoCompactWindow "1.5M" is not a token count. Set "autoCompactWindow": 200000.' \
  "$(run_with_clean_env bash "$script" "$decimal_cap_settings")"
expect "\"200k\" is read as 200000: silent" "" "$(run_with_clean_env bash "$script" "$k_suffix_cap_settings")"
expect "\"1M\" is read as 1000000" "$(too_high_line 1000000)" "$(run_with_clean_env bash "$script" "$m_suffix_cap_settings")"
expect "cap in settings env: silent" "" "$(run_with_clean_env bash "$script" "$env_cap_settings")"
expect "1M disabled caps at 200000: silent" "" "$(run_with_clean_env bash "$script" "$disabled_1m_settings")"
expect "low percent of the 1M window: silent" "" "$(run_with_clean_env bash "$script" "$low_pct_settings")"
expect "high percent of the 1M window is still too high" "$(too_high_line 950000)" "$(run_with_clean_env bash "$script" "$high_pct_settings")"
expect "percent that is not a number" \
  'context: CLAUDE_AUTOCOMPACT_PCT_OVERRIDE "most" is not a percentage. Set "autoCompactWindow": 200000 instead.' \
  "$(run_with_clean_env bash "$script" "$word_pct_settings")"
expect "mid-tier subagent default" "$(weak_line sonnet)" "$(run_with_clean_env bash "$script" "$mid_subagent_settings")"
expect "no subagent default: silent" "" "$(run_with_clean_env bash "$script" "$capped_no_subagent_settings")"

expect "later file wins over an earlier one" "" "$(run_with_clean_env bash "$script" "$uncapped_settings" "$capped_settings")"
expect "earlier capped file, later over-limit one" "$(too_high_line 800000)" \
  "$(run_with_clean_env bash "$script" "$capped_settings" "$over_limit_settings")"
expect "environment wins over files" "" "$(run_with_clean_env CLAUDE_CODE_AUTO_COMPACT_WINDOW=200000 bash "$script" "$uncapped_settings")"
expect "environment mid subagent model wins over a file's strongest" "$(weak_line claude-sonnet-5-5)" \
  "$(run_with_clean_env CLAUDE_CODE_SUBAGENT_MODEL=claude-sonnet-5-5 bash "$script" "$capped_settings")"
expect "environment strongest subagent model wins over a file's mid: silent" "" \
  "$(run_with_clean_env CLAUDE_CODE_SUBAGENT_MODEL=claude-opus-5-5 bash "$script" "$mid_subagent_settings")"
expect "both problems: two lines" "$no_cap_line
$(weak_line haiku)" "$(run_with_clean_env bash "$script" "$uncapped_settings" "$haiku_subagent_settings")"

expect "file that is not JSON is named and skipped" "settings: $broken_settings is not valid JSON, so its settings were not read. Fix the file." \
  "$(run_with_clean_env bash "$script" "$capped_settings" "$broken_settings")"
expect "missing file is skipped" "" "$(run_with_clean_env bash "$script" "$work_dir/missing.json" "$capped_settings")"

bin_without_jq="$work_dir/bin"
mkdir -p "$bin_without_jq"
ln -s "$(command -v bash)" "$bin_without_jq/bash"
no_jq_status=0
no_jq_stdout=$(PATH="$bin_without_jq" bash "$script" "$capped_settings" 2>"$work_dir/no-jq.err") || no_jq_status=$?
expect "jq missing: exit 2, nothing on stdout, the reason on stderr" \
  "2||check-cost-settings: jq is required; install it (for example: brew install jq)" \
  "$no_jq_status|$no_jq_stdout|$(cat "$work_dir/no-jq.err")"

echo "$((cases - failures))/$cases passed"
[ "$failures" -eq 0 ]
