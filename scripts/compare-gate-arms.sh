#!/usr/bin/env bash
# Compares two `claude plugin eval --json` results of the same fixtures: the review run one agent
# per gate (the default) and run with the opt-in combined gate, for recall (graders passed) and
# cost (tokens, dollars, agents), per case and in total. Prints what the combined arm lost.
#
# Usage: scripts/compare-gate-arms.sh <per-gate.json> <combined.json>
#
#   Cases pair by name: a combined case is `combined-<name>` of the per-gate case `<name>`.
#   Tokens are read from each run's trace (its `tracePath`, kept with `--keep-temp`): the result
#   line's modelUsage summed over every model, subagents included. A run whose trace is gone shows
#   `n/a` and counts for no total.
#
# Recall is graders passed over graders run, summed over the case's runs. Exits 0 when the
# combined arm passed every grader the per-gate arm passed, 1 when it lost one or a case has no combined case, 2 on a usage error.
set -euo pipefail

script_name=$(basename "$0")
[ "$#" -eq 2 ] || { echo "usage: $script_name <per-gate.json> <combined.json>" >&2; exit 2; }
for input in "$1" "$2"; do
  [ -f "$input" ] || { echo "$script_name: no such file: $input" >&2; exit 2; }
done

# Prints one tab-separated line per case in <result.json>: name, passed, total, runs, agents,
# tokens (sum over runs with a readable trace), traced runs, cost, failed grader names.
summarize() {
  local result=$1 name trace tokens traced agents
  jq -r '.cases[] | .name' "$result" | while IFS= read -r name; do
    tokens=0
    traced=0
    agents=0
    while IFS= read -r trace; do
      [ -r "$trace" ] || continue
      tokens=$((tokens + $(jq -s 'map(select(.type == "result")) | last | [.modelUsage[] | .inputTokens + .outputTokens + .cacheReadInputTokens + .cacheCreationInputTokens] | add // 0' "$trace")))
      agents=$((agents + $(jq -s 'map(select(.type == "result")) | last | .subagent_stats.spawned // 0' "$trace")))
      traced=$((traced + 1))
    done < <(jq -r --arg name "$name" '.cases[] | select(.name == $name) | .arms.with[] | .tracePath // empty' "$result")
    jq -r --arg name "$name" --argjson tokens "$tokens" --argjson traced "$traced" --argjson agents "$agents" '
      .cases[] | select(.name == $name) | .arms.with as $runs
      | [$name,
         ([$runs[] | .graders[] | select(.passed)] | length),
         ([$runs[] | .graders[]] | length),
         ($runs | length), $agents, $tokens, $traced,
         ([$runs[] | .costUsd] | add),
         ([$runs[] | .graders[] | select(.passed | not) | .name] | unique | join(","))]
      | @tsv' "$result"
  done
}

per_gate=$(summarize "$1")
combined=$(summarize "$2" | sed -E 's/^combined-//')

lost_total=0
unpaired=0
# print_row <case> <arm> <passed> <total> <agents> <tokens> <traced runs> <cost>
print_row() {
  printf '%-28s %-9s %-8s %-7s %-7s %-10s $%.2f\n' "$1" "$2" "$3/$4" \
    "$(awk -v p="$3" -v t="$4" 'BEGIN { printf "%.0f%%", t ? 100 * p / t : 0 }')" "$5" \
    "$([ "$7" -gt 0 ] && echo "$6" || echo n/a)" "$8"
}
# total_row <arm> <rows>: sums the rows of <rows>, tokens only over runs with a trace.
total_row() {
  printf '%s\n' "$2" | awk -F'\t' '{ p += $2; t += $3; a += $5; k += $6; g += $7; c += $8 } END { print p, t, a, k, g, c }' \
    | { read -r p t a k g c; print_row TOTAL "$1" "$p" "$t" "$a" "$k" "$g" "$c"; }
}

printf '%-28s %-9s %-8s %-7s %-7s %-10s %s\n' case arm graders recall agents tokens cost
paired_combined=
while IFS=$'\t' read -r name passed total _ agents tokens traced cost missed; do
  print_row "$name" per-gate "$passed" "$total" "$agents" "$tokens" "$traced" "$cost"
  other=$(printf '%s\n' "$combined" | awk -F'\t' -v n="$name" '$1 == n')
  if [ -z "$other" ]; then
    printf '%-28s %-9s no combined case of this name\n' "$name" combined
    unpaired=$((unpaired + 1))
    continue
  fi
  paired_combined+="$other"$'\n'
  IFS=$'\t' read -r _ c_passed c_total _ c_agents c_tokens c_traced c_cost c_missed <<< "$other"
  [ "$c_total" -gt 0 ] || unpaired=$((unpaired + 1))
  print_row "$name" combined "$c_passed" "$c_total" "$c_agents" "$c_tokens" "$c_traced" "$c_cost"
  # Graders the combined arm failed that the per-gate arm did not.
  lost=$(comm -13 <(printf '%s\n' "${missed:-}" | tr ',' '\n' | sort) <(printf '%s\n' "${c_missed:-}" | tr ',' '\n' | sort) | grep -v '^$' || true)
  if [ -n "$lost" ]; then
    printf '     lost by combined: %s\n' "$(printf '%s' "$lost" | tr '\n' ' ')"
    lost_total=$((lost_total + $(printf '%s\n' "$lost" | wc -l)))
  fi
done <<< "$per_gate"

total_row per-gate "$per_gate"
total_row combined "$paired_combined"
[ "$unpaired" -eq 0 ] || { echo "$unpaired case(s) have no combined case or no combined grader result"; exit 1; }
[ "$lost_total" -eq 0 ] || { echo "combined lost $lost_total grader(s) the per-gate arm passed"; exit 1; }
echo "combined lost no grader the per-gate arm passed"
