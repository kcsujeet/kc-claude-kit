#!/usr/bin/env bash
# Flags Claude Code settings that make every call cost more than it needs to. Prints one line per
# finding, with the fix, and nothing when the settings are fine. Always exits 0 unless jq is missing.
#
# Usage: check-cost-settings.sh [<settings.json>...]
#   Default files: ~/.claude/settings.json, .claude/settings.json, .claude/settings.local.json
#   (missing ones are skipped). A later file wins over an earlier one, and the process
#   environment wins over every file.
#
# Findings:
#  - context: the point where auto-compaction fires is above 300000 tokens, so every call can
#    re-read that much cached context. The point is the auto-compact window (`autoCompactWindow`
#    or CLAUDE_CODE_AUTO_COMPACT_WINDOW; 200000 with CLAUDE_CODE_DISABLE_1M_CONTEXT=1; else the
#    1M window), scaled by CLAUDE_AUTOCOMPACT_PCT_OVERRIDE when set. A window or percent that is
#    not a number is flagged too.
#  - subagents: CLAUDE_CODE_SUBAGENT_MODEL names a mid or small model (sonnet, haiku), so an agent
#    spawned without a model, which may be one that decides, runs below the strongest tier.
#  - settings: a file that is not valid JSON, whose values are then not read.
set -euo pipefail

command -v jq >/dev/null 2>&1 || { echo "check-cost-settings: jq is required; install it (for example: brew install jq)" >&2; exit 2; }

max_compact_tokens=300000
full_window_tokens=1000000
capped_1m_window_tokens=200000
weak_models='sonnet|haiku'

if [ $# -gt 0 ]; then
  files=("$@")
else
  files=("$HOME/.claude/settings.json" ".claude/settings.json" ".claude/settings.local.json")
fi

compact_window="" disable_1m="" compact_pct_override="" subagent_model=""

# Prints the setting at <filter> in <file>, or <previous> when the file doesn't set it.
read_setting() { jq -r --arg previous "$3" "$1 // \$previous" "$2"; }

for file in "${files[@]}"; do
  [ -f "$file" ] || continue
  if ! jq empty "$file" 2>/dev/null; then
    echo "settings: $file is not valid JSON, so its settings were not read. Fix the file."
    continue
  fi
  compact_window=$(read_setting '.autoCompactWindow' "$file" "$compact_window")
  compact_window=$(read_setting '.env.CLAUDE_CODE_AUTO_COMPACT_WINDOW' "$file" "$compact_window")
  disable_1m=$(read_setting '.env.CLAUDE_CODE_DISABLE_1M_CONTEXT' "$file" "$disable_1m")
  compact_pct_override=$(read_setting '.env.CLAUDE_AUTOCOMPACT_PCT_OVERRIDE' "$file" "$compact_pct_override")
  subagent_model=$(read_setting '.env.CLAUDE_CODE_SUBAGENT_MODEL' "$file" "$subagent_model")
done

compact_window=${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-$compact_window}
disable_1m=${CLAUDE_CODE_DISABLE_1M_CONTEXT:-$disable_1m}
compact_pct_override=${CLAUDE_AUTOCOMPACT_PCT_OVERRIDE:-$compact_pct_override}
subagent_model=${CLAUDE_CODE_SUBAGENT_MODEL:-$subagent_model}

is_count() { case "$1" in "" | *[!0-9]*) return 1 ;; *) return 0 ;; esac; }
has_cap_setting() { [ -n "$compact_window$compact_pct_override" ] || [ "$disable_1m" = "1" ]; }
is_weak_model() { [ -n "$1" ] && printf '%s' "$1" | grep -Eiq "$weak_models"; }

# Prints a token count for "200000", "200k" or "1M" (the forms /autocompact accepts), or nothing.
to_tokens() {
  local number=${1%[kKmM]}
  is_count "$number" || return 0
  case "$1" in
    *[kK]) echo $((number * 1000)) ;;
    *[mM]) echo $((number * 1000000)) ;;
    *) echo "$number" ;;
  esac
}

compact_window_tokens=$(to_tokens "$compact_window")
if [ -n "$compact_window" ] && [ -z "$compact_window_tokens" ]; then
  echo "context: autoCompactWindow \"$compact_window\" is not a token count. Set \"autoCompactWindow\": 200000."
else
  window_tokens=${compact_window_tokens:-$full_window_tokens}
  is_1m_disabled_without_window=$([ -z "$compact_window" ] && [ "$disable_1m" = "1" ] && echo yes || true)
  if [ -n "$is_1m_disabled_without_window" ]; then
    window_tokens=$capped_1m_window_tokens
  fi
  compact_at_tokens=$window_tokens
  if [ -n "$compact_pct_override" ]; then
    if is_count "$compact_pct_override"; then
      compact_at_tokens=$((window_tokens * compact_pct_override / 100))
    else
      echo "context: CLAUDE_AUTOCOMPACT_PCT_OVERRIDE \"$compact_pct_override\" is not a percentage. Set \"autoCompactWindow\": 200000 instead."
    fi
  fi
  if [ "$compact_at_tokens" -gt "$max_compact_tokens" ]; then
    if has_cap_setting; then
      echo "context: auto-compaction fires at about $compact_at_tokens tokens, above $max_compact_tokens, so each call can re-read that much. Set \"autoCompactWindow\": 200000."
    else
      echo "context: no auto-compact cap, so a 1M-window session re-reads up to 1M cached tokens per call. Set \"autoCompactWindow\": 200000 in ~/.claude/settings.json."
    fi
  fi
fi

if is_weak_model "$subagent_model"; then
  echo "subagents: CLAUDE_CODE_SUBAGENT_MODEL=$subagent_model runs every agent spawned without a model, deciding ones included, below the strongest tier. Set it to the strongest (opus) or remove it, and name a mid model per agent for hands-on work."
fi
