#!/usr/bin/env bash
# Flags Claude Code settings that make every call cost more than it needs to. Prints one line per
# finding, with the fix, and nothing when the settings are fine. Always exits 0 unless misused.
#
# Usage: check-cost-settings.sh [<settings.json>...]
#   Default files: ~/.claude/settings.json, .claude/settings.json, .claude/settings.local.json
#   (missing ones are skipped). The process environment counts too, as a later file would.
#
# Findings:
#  - context: no auto-compact cap. Without `autoCompactWindow` (or CLAUDE_CODE_AUTO_COMPACT_WINDOW,
#    CLAUDE_CODE_DISABLE_1M_CONTEXT, CLAUDE_AUTOCOMPACT_PCT_OVERRIDE) a 1M-window session compacts
#    only near 1M, so every call re-reads hundreds of thousands of cached tokens. A cap above
#    KC_COST_MAX_WINDOW (default 300000) is flagged the same way.
#  - subagents: CLAUDE_CODE_SUBAGENT_MODEL names the strongest tier (KC_COST_STRONG_MODELS, an
#    extended regex, default opus|fable|best), so every agent spawned without a model runs on it.
# Needs jq.
set -euo pipefail

command -v jq >/dev/null 2>&1 || { echo "check-cost-settings: jq is required; install it (for example: brew install jq)" >&2; exit 2; }

max_window=${KC_COST_MAX_WINDOW:-300000}
strong_models=${KC_COST_STRONG_MODELS:-opus|fable|best}

if [ $# -gt 0 ]; then
  files=("$@")
else
  files=("$HOME/.claude/settings.json" ".claude/settings.json" ".claude/settings.local.json")
fi

window="" disable_1m="" pct="" subagent_model=""
read_setting() { jq -r "$1 // empty" "$2" 2>/dev/null || true; }

for file in "${files[@]}"; do
  [ -f "$file" ] || continue
  value=$(read_setting '.autoCompactWindow' "$file"); [ -n "$value" ] && window=$value
  value=$(read_setting '.env.CLAUDE_CODE_AUTO_COMPACT_WINDOW' "$file"); [ -n "$value" ] && window=$value
  value=$(read_setting '.env.CLAUDE_CODE_DISABLE_1M_CONTEXT' "$file"); [ -n "$value" ] && disable_1m=$value
  value=$(read_setting '.env.CLAUDE_AUTOCOMPACT_PCT_OVERRIDE' "$file"); [ -n "$value" ] && pct=$value
  value=$(read_setting '.env.CLAUDE_CODE_SUBAGENT_MODEL' "$file"); [ -n "$value" ] && subagent_model=$value
done

[ -n "${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-}" ] && window=$CLAUDE_CODE_AUTO_COMPACT_WINDOW
[ -n "${CLAUDE_CODE_DISABLE_1M_CONTEXT:-}" ] && disable_1m=$CLAUDE_CODE_DISABLE_1M_CONTEXT
[ -n "${CLAUDE_AUTOCOMPACT_PCT_OVERRIDE:-}" ] && pct=$CLAUDE_AUTOCOMPACT_PCT_OVERRIDE
[ -n "${CLAUDE_CODE_SUBAGENT_MODEL:-}" ] && subagent_model=$CLAUDE_CODE_SUBAGENT_MODEL

# "500k" and "1M" are accepted by /autocompact; normalise them to a token count.
to_tokens() {
  case "$1" in
    *[kK]) echo $(( ${1%[kK]} * 1000 )) ;;
    *[mM]) echo $(( ${1%[mM]} * 1000000 )) ;;
    *[!0-9]*|"") echo "" ;;
    *) echo "$1" ;;
  esac
}

if [ "$disable_1m" != "1" ] && [ -z "$pct" ]; then
  tokens=$(to_tokens "$window")
  if [ -z "$window" ]; then
    echo "context: no auto-compact cap, so a 1M-window session re-reads up to 1M cached tokens per call. Set \"autoCompactWindow\": 200000 in ~/.claude/settings.json."
  elif [ -z "$tokens" ]; then
    echo "context: autoCompactWindow \"$window\" is not a token count. Set \"autoCompactWindow\": 200000."
  elif [ "$tokens" -gt "$max_window" ]; then
    echo "context: autoCompactWindow $window is above $max_window, so each call can re-read that much. Set \"autoCompactWindow\": 200000."
  fi
fi

if [ -n "$subagent_model" ] && printf '%s' "$subagent_model" | grep -Eiq "$strong_models"; then
  echo "subagents: CLAUDE_CODE_SUBAGENT_MODEL=$subagent_model runs every agent spawned without a model on the strongest tier. Set it to a mid model (sonnet) and name a stronger one per agent where judgment needs it."
fi
