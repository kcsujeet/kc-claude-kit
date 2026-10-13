#!/usr/bin/env bash
# Validates a repo's .claude/autopilot.json and prints it normalized, with
# every default filled in, as compact JSON on stdout.
#
# Usage: read-config.sh <config.json>
# Exit: 0 valid; 1 invalid (one "autopilot.json: <problem>" line per problem
# on stderr); 2 jq missing.
set -euo pipefail

command -v jq >/dev/null 2>&1 || { echo "autopilot: jq is required" >&2; exit 2; }

config=${1:?usage: read-config.sh <config.json>}
if [ ! -f "$config" ]; then
  echo "autopilot.json: $config not found" >&2
  exit 1
fi
if ! jq empty "$config" >/dev/null 2>&1; then
  echo "autopilot.json: $config is not valid JSON" >&2
  exit 1
fi

readonly NORMALIZE='
  def strs: type == "array" and all(.[]; type == "string");
  {
    launch: {
      install: (.launch.install // ""),
      start: .launch.start,
      ready: .launch.ready,
      seed: (.launch.seed // ""),
      ready_timeout_s: (.launch.ready_timeout_s // 120),
      ports: { base: (.launch.ports.base // 4100), per_unit: (.launch.ports.per_unit // 10) },
      login: (.launch.login // null)
    },
    checks: .checks,
    risky_paths: (.risky_paths // []),
    review: { extra_agents: (.review.extra_agents // []) },
    limits: {
      max_fix_rounds: (.limits.max_fix_rounds // 4),
      max_parallel_units: (.limits.max_parallel_units // 4),
      qa_personas: { min: (.limits.qa_personas.min // 3), max: (.limits.qa_personas.max // 5) },
      max_agents_per_unit: (.limits.max_agents_per_unit // 120)
    },
    models: { workers: (.models.workers // "sonnet"), staff: (.models.staff // "best") }
  }'

readonly PROBLEMS='
  def strs: type == "array" and all(.[]; type == "string");
  def posint: type == "number" and . >= 1 and floor == .;
  [
    (if (.launch.start | type) == "string" and (.launch.start | contains("{port}")) then empty else "launch.start must contain {port}" end),
    (if (.launch.ready | type) == "string" and (.launch.ready | contains("{port}")) then empty else "launch.ready must contain {port}" end),
    (if (.checks | strs) and (.checks | length) > 0 then empty else "checks must be a non-empty array of commands" end),
    (if (.risky_paths | strs) then empty else "risky_paths must be an array of globs" end),
    (if (.review.extra_agents | strs) then empty else "review.extra_agents must be an array of agent types" end),
    (if (.launch.ports.base | posint) and (.launch.ports.per_unit | posint) then empty else "launch.ports.base and per_unit must be positive integers" end),
    (if (.launch.ready_timeout_s | posint) then empty else "launch.ready_timeout_s must be a positive integer" end),
    (if (.limits | [.max_fix_rounds, .max_parallel_units, .qa_personas.min, .qa_personas.max, .max_agents_per_unit] | all(.[]; posint)) then empty else "limits must be positive integers" end),
    (if .limits.qa_personas.min <= .limits.qa_personas.max then empty else "limits.qa_personas.min must be <= max" end)
  ] | .[]'

normalized=$(jq -c "$NORMALIZE" "$config")
problems=$(printf '%s' "$normalized" | jq -r "$PROBLEMS")
if [ -n "$problems" ]; then
  printf '%s\n' "$problems" | sed 's/^/autopilot.json: /' >&2
  exit 1
fi
printf '%s\n' "$normalized"
