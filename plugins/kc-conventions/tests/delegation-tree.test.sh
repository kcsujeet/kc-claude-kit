#!/usr/bin/env bash
# Checks kc-delegate's delegation tree: each role keeps its model tier (deciding roles on the
# strongest, executing roles on a mid model), sessions keep their effort, and the README's graph
# of the tree agrees.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
plugin_dir=$(dirname "$tests_dir")
repo_root=$(dirname "$(dirname "$plugin_dir")")
skill="$plugin_dir/skills/kc-delegate/SKILL.md"
readme="$repo_root/README.md"

failures=0
fail() { echo "FAIL $1"; failures=$((failures + 1)); }

# Prints the model column of the tree row whose first column starts with <role>.
model_of() { awk -F'|' -v role="$1" 'index($2, " " role) == 1 { print $3; exit }' "$skill"; }

# expect_tier <role> <tier>: the row exists, names <tier>, and names no other tier.
expect_tier() {
  local role=$1 tier=$2 other model
  other=$([ "$tier" = strongest ] && echo mid || echo strongest)
  model=$(model_of "$role")
  if [ -z "$model" ]; then fail "kc-delegate tree: no row for \"$role\""; return; fi
  case "$model" in *"$tier"*) ;; *) fail "kc-delegate tree: \"$role\" is not on the $tier model ($model)" ;; esac
  case "$model" in *"$other"*) fail "kc-delegate tree: \"$role\" also names the $other model ($model)" ;; esac
}

expect_tier "Orchestrating (main) session" strongest
expect_tier "Child session that decides" strongest
expect_tier "Unnamed agent" strongest
expect_tier "Mechanical session" mid
expect_tier "Hands-on agent" mid
expect_tier "Review gate agent" mid
# Sessions keep their effort: high for the orchestrator, medium for child and mechanical sessions.
effort_of() { awk -F'|' -v role="$1" 'index($2, " " role) == 1 { gsub(/ /, "", $4); print $4; exit }' "$skill"; }
for role_effort in "Orchestrating (main) session=high" "Child session that decides=medium" "Mechanical session=medium"; do
  role=${role_effort%=*}
  effort=$(effort_of "$role")
  [ "$effort" = "${role_effort#*=}" ] || fail "kc-delegate tree: \"$role\" effort is \"$effort\", not ${role_effort#*=}"
done

grep -q 'Whatever decides .* runs on the strongest model' "$skill" || fail "kc-delegate: the decide-on-strongest rule is missing"

# The README graph: deciding nodes in the decide class, executing nodes in the execute class.
for node in M T U; do
  grep -qE "^ *class [A-Z,]*${node}[A-Z,]* decide$" "$readme" || fail "README graph: node $node is not styled as deciding"
done
for node in X H G; do
  grep -qE "^ *class [A-Z,]*${node}[A-Z,]* execute$" "$readme" || fail "README graph: node $node is not styled as executing"
done
grep -q 'skills/kc-delegate/SKILL.md' "$readme" || fail "README graph: no link to kc-delegate"

[ "$failures" -eq 0 ] && echo "ok   delegation tree"
exit "$failures"
