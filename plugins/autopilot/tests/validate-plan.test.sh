#!/usr/bin/env bash
# Tests scripts/validate-plan.sh against the plan template's rules.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
script="$(dirname "$tests_dir")/scripts/validate-plan.sh"
plans="$tests_dir/fixtures/plans"
stderr_file=$(mktemp)
trap 'rm -f "$stderr_file"' EXIT
passes=0
failures=0

pass() { echo "ok   $1"; passes=$((passes + 1)); }
fail() { echo "FAIL $1"; echo "     $2"; failures=$((failures + 1)); }

expect_value() {
  local label=$1 fixture=$2 filter=$3 expected=$4 out actual status=0
  out=$(bash "$script" "$plans/$fixture" 2>"$stderr_file") || status=$?
  actual=$(printf '%s' "$out" | jq -c "$filter") || actual="<jq failed>"
  if [ "$status" = 0 ] && [ "$actual" = "$expected" ]; then
    pass "$label"
  else
    fail "$label" "expected $expected, got $actual (status $status); stderr: $(cat "$stderr_file")"
  fi
}

expect_error() {
  local label=$1 fixture=$2 needle=$3 status=0
  bash "$script" "$plans/$fixture" >/dev/null 2>"$stderr_file" || status=$?
  if [ "$status" = 1 ] && grep -qF "plan: $needle" "$stderr_file" && ! grep -v '^plan: ' "$stderr_file" | grep -q .; then
    pass "$label"
  else
    fail "$label" "status $status, stderr: $(cat "$stderr_file")"
  fi
}

expect_value "title"              good.md '.title'                       '"Saved replies"'
expect_value "goal"               good.md '.goal'                        '"Agents can save a reply and reuse it."'
expect_value "criteria ids"       good.md '[.criteria[].id]'             '["AC1","AC2","AC3"]'
expect_value "criterion text"     good.md '.criteria[2].statement'       '"An empty picker shows \"No saved replies yet\"."'
expect_value "unit ids"           good.md '[.units[].id]'                '["U1","U2"]'
expect_value "unit index"         good.md '[.units[].index]'             '[0,1]'
expect_value "unit title"         good.md '.units[1].title'              '"Picker UI"'
expect_value "depends parsed"     good.md '.units[1].depends_on'         '["U1"]'
expect_value "none is empty"      good.md '.units[0].depends_on'         '[]'
expect_value "covers parsed"      good.md '.units[1].covers'             '["AC2","AC3"]'
expect_value "scope kept"         good.md '.units[0].scope'              '"Model, migration and API for saved replies."'
expect_value "out of scope"       good.md '.out_of_scope'                '"- Sharing replies between users."'
expect_error "missing criteria"   no-criteria.md 'missing section: ## Acceptance criteria'
expect_error "uncovered criterion" uncovered.md 'AC3 is not covered by any unit'
expect_error "unknown criterion"  bad-ref.md   'U2 covers unknown criterion AC9'
expect_error "forward dependency" forward-dep.md 'U1 depends on U2, which is not an earlier unit'
expect_error "missing title"      bad-shape.md 'missing title: a "# <Plan title>" line'
expect_error "unnumbered criteria" bad-shape.md '## Acceptance criteria has no numbered criteria'
expect_error "no units"           bad-shape.md '## Work units has no ### U<n>: units'
expect_error "missing file"       missing.md   "$plans/missing.md not found"

echo "validate-plan: $passes passed, $failures failed"
[ "$failures" = 0 ]
