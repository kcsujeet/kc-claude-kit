#!/usr/bin/env bash
# Checks every plugin agent file against kc-delegation's tree: each names its model, a deciding
# agent runs on the strongest tier, and every other agent (gates, workers, script runners) on a mid
# one. A new agent is executing until it is added to deciding_agents below, so none lands on a tier
# by accident. Usage: agent-model-tiers.test.sh [<plugins dir>] (default: this repo's plugins/).
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
plugins_root=${1:-$(dirname "$(dirname "$tests_dir")")}

# Agents that decide (judge findings, approaches or what ships), as <plugin>/<agent>.
deciding_agents=" kc-autopilot/staff-reviewer "
# Reviewed exceptions: agents that make a bounded call on a list they are handed, which a
# strongest-tier gate checks downstream, so they stay on a mid tier. Each needs its reason.
#   skeptic: two vote per finding, and a finding drops only when both refute it.
#   triage:  fix or dismiss to a schema, each dismissal logged; staff-reviewer gates the final diff.
bounded_mid_agents=" kc-autopilot/skeptic kc-autopilot/triage "
strongest_models='^(best|opus|fable|claude-opus-.*|claude-fable-.*)$'
mid_models='^(sonnet|claude-sonnet-.*)$'

failures=0
checked=0
fail() { echo "FAIL $1"; failures=$((failures + 1)); }

for agent_file in "$plugins_root"/*/agents/*.md; do
  [ -f "$agent_file" ] || continue
  checked=$((checked + 1))
  plugin=$(basename "$(dirname "$(dirname "$agent_file")")")
  agent="$plugin/$(basename "$agent_file" .md)"
  model=$(awk 'NR==1 && /^---$/ { fm=1; next } fm && /^---$/ { exit } fm && /^model:/ { sub(/^model:[[:space:]]*/, ""); print; exit }' "$agent_file")
  if [ -z "$model" ]; then
    fail "$agent has no model: line, so it inherits whatever spawns it"
  elif [[ "$deciding_agents" == *" $agent "* ]]; then
    printf '%s\n' "$model" | grep -Eq "$strongest_models" || fail "$agent decides but runs on $model; use best"
  elif [[ "$bounded_mid_agents" == *" $agent "* ]]; then
    printf '%s\n' "$model" | grep -Eq "$mid_models" || fail "$agent is a reviewed mid-tier exception but runs on $model; move it to deciding_agents if that changed"
  else
    printf '%s\n' "$model" | grep -Eq "$mid_models" || fail "$agent executes but runs on $model; use sonnet, or add it to deciding_agents if it decides"
  fi
done

[ "$checked" -gt 0 ] || fail "no agent files under $plugins_root"
[ "$failures" -eq 0 ] && echo "ok   $checked agent files on their tree tier"
exit "$failures"
