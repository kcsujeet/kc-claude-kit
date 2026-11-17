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
#  - subagents: CLAUDE_CODE_SUBAGENT_MODEL names a mid or small model (sonnet, haiku), so an agent
#    spawned without a model, which may be one that decides, runs below the strongest tier.
#  - settings: a file that is not valid JSON, whose values are then not read.
set -euo pipefail

command -v jq >/dev/null 2>&1 || { echo "check-cost-settings: jq is required; install it (for example: brew install jq)" >&2; exit 2; }

weak_models='sonnet|haiku'

if [ $# -gt 0 ]; then
  files=("$@")
else
  files=("$HOME/.claude/settings.json" ".claude/settings.json" ".claude/settings.local.json")
fi

subagent_model=""

# Prints the setting at <filter> in <file>, or <previous> when the file doesn't set it.
read_setting() { jq -r --arg previous "$3" "$1 // \$previous" "$2"; }

for file in "${files[@]}"; do
  [ -f "$file" ] || continue
  if ! jq empty "$file" 2>/dev/null; then
    echo "settings: $file is not valid JSON, so its settings were not read. Fix the file."
    continue
  fi
  subagent_model=$(read_setting '.env.CLAUDE_CODE_SUBAGENT_MODEL' "$file" "$subagent_model")
done

subagent_model=${CLAUDE_CODE_SUBAGENT_MODEL:-$subagent_model}

is_weak_model() { [ -n "$1" ] && printf '%s' "$1" | grep -Eiq "$weak_models"; }

if is_weak_model "$subagent_model"; then
  echo "subagents: CLAUDE_CODE_SUBAGENT_MODEL=$subagent_model runs every agent spawned without a model, deciding ones included, below the strongest tier. Set it to the strongest (opus) or remove it, and name a mid model per agent for hands-on work."
fi
