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
if [ "$(jq -r 'type' "$config")" != object ]; then
  echo "autopilot.json: $config must be a JSON object" >&2
  exit 1
fi

# Sections of the wrong type read as {} so normalization never crashes;
# SHAPE reports them.
# jq program: $-variables are jq's, not the shell's.
# shellcheck disable=SC2016
readonly NORMALIZE='
  def o: if type == "object" then . else {} end;
  . as $c
  | ($c.launch | o) as $l
  | ($l.ports | o) as $p
  | ($c.review | o) as $r
  | ($c.limits | o) as $lim
  | ($lim.qa_personas | o) as $qa
  | ($c.models | o) as $m
  | {
      launch: {
        install: ($l.install // ""),
        start: $l.start,
        ready: $l.ready,
        seed: ($l.seed // ""),
        ready_timeout_s: ($l.ready_timeout_s // 120),
        ports: { base: ($p.base // 4100), per_unit: ($p.per_unit // 10) },
        login: ($l.login // null)
      },
      checks: $c.checks,
      risky_paths: ($c.risky_paths // []),
      review: { extra_agents: ($r.extra_agents // []) },
      limits: {
        max_fix_rounds: ($lim.max_fix_rounds // 4),
        max_parallel_units: ($lim.max_parallel_units // 4),
        qa_personas: { min: ($qa.min // 3), max: ($qa.max // 5) },
        max_agents_per_unit: ($lim.max_agents_per_unit // 120)
      },
      models: { workers: ($m.workers // "sonnet"), staff: ($m.staff // "best") }
    }'

# jq program: $-variables are jq's, not the shell's.
# shellcheck disable=SC2016
readonly SHAPE='
  def wrong($v): $v != null and ($v | type) != "object";
  def o: if type == "object" then . else {} end;
  . as $c
  | ($c.launch | o) as $l
  | ($c.limits | o) as $lim
  | [
      (if wrong($c.launch) then "launch must be an object" else empty end),
      (if wrong($l.ports) then "launch.ports must be an object" else empty end),
      (if wrong($l.login) then "launch.login must be an object or null" else empty end),
      (if wrong($c.limits) then "limits must be an object" else empty end),
      (if wrong($lim.qa_personas) then "limits.qa_personas must be an object" else empty end),
      (if wrong($c.review) then "review must be an object" else empty end),
      (if wrong($c.models) then "models must be an object" else empty end)
    ] | .[]'

readonly PROBLEMS='
  def posint: type == "number" and . >= 1 and floor == .;
  def strs: type == "array" and all(.[]; type == "string");
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

shape_problems=$(jq -r "$SHAPE" "$config")
normalized=$(jq -c "$NORMALIZE" "$config")
value_problems=$(printf '%s' "$normalized" | jq -r "$PROBLEMS")
problems=$(printf '%s\n%s\n' "$shape_problems" "$value_problems" | sed '/^$/d')
if [ -n "$problems" ]; then
  printf '%s\n' "$problems" | sed 's/^/autopilot.json: /' >&2
  exit 1
fi
printf '%s\n' "$normalized"
