#!/usr/bin/env bash
# Tests scripts/validate-units.sh: the contracts /kc-autopilot:kc-run writes must
# match the validated plan and the config's persona limits before the
# deliver workflow starts. Bad cases are jq edits of fixtures/units/good.json.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
plugin_dir=$(dirname "$tests_dir")
script="$plugin_dir/scripts/validate-units.sh"
fixtures="$tests_dir/fixtures/units"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
passes=0
failures=0

pass() { echo "ok   $1"; passes=$((passes + 1)); }
fail() { echo "FAIL $1"; echo "     $2"; failures=$((failures + 1)); }

# expect_ok <label> <units.json> [config.json]
expect_ok() {
  local label=$1 units=$2 config=${3:-$fixtures/config.json} status=0
  bash "$script" "$units" "$config" "$fixtures/plan.json" >/dev/null 2>"$work/stderr" || status=$?
  if [ "$status" = 0 ] && ! grep -q . "$work/stderr"; then
    pass "$label"
  else
    fail "$label" "status $status, stderr: $(cat "$work/stderr")"
  fi
}

# expect_error <label> <units.json> <needle> [config.json]
# Exit 1, the needle on a "units: " line, and nothing but "units: " lines.
expect_error() {
  local label=$1 units=$2 needle=$3 config=${4:-$fixtures/config.json} status=0
  bash "$script" "$units" "$config" "$fixtures/plan.json" >/dev/null 2>"$work/stderr" || status=$?
  if [ "$status" = 1 ] && grep -qF "units: $needle" "$work/stderr" && ! grep -v '^units: ' "$work/stderr" | grep -q .; then
    pass "$label"
  else
    fail "$label" "status $status, stderr: $(cat "$work/stderr")"
  fi
}

# mutate <name> <jq filter> → path of good.json with the filter applied
mutate() {
  jq "$2" "$fixtures/good.json" >"$work/$1.json" || echo "<jq failed for $1>" >"$work/$1.json"
  printf '%s' "$work/$1.json"
}

# The plan fixture must stay what validate-plan.sh prints for the good plan.
plan_now=$(bash "$plugin_dir/scripts/validate-plan.sh" "$tests_dir/fixtures/plans/good.md" | jq -S .) || plan_now="<validate-plan failed>"
if [ "$plan_now" = "$(jq -S . "$fixtures/plan.json")" ]; then pass "plan fixture matches validate-plan.sh"
else fail "plan fixture matches validate-plan.sh" "regenerate tests/fixtures/units/plan.json"; fi

expect_ok    "good contracts"           "$fixtures/good.json"
expect_ok    "criteria in any order"    "$(mutate reordered '.units[1].contract.criteria |= reverse')"
expect_ok    "five personas allowed"    "$(mutate five '.units[0].contract.personas += [{name: "a", goals: "g", behaviour: "b"}, {name: "c", goals: "g", behaviour: "b"}]')"

expect_error "missing file"             "$work/missing.json" "$work/missing.json not found"
printf 'not json' >"$work/broken.json"
expect_error "not json"                 "$work/broken.json" "$work/broken.json is not valid JSON"
expect_error "no architecture"          "$(mutate no-arch 'del(.architecture)')" "architecture must be a non-empty string"
expect_error "no design review"         "$(mutate no-design 'del(.architecture) | .architecture = "Replies live next to the composer."')" "architecture has no Design review section"
expect_error "units not an array"       "$(mutate units-obj '.units = {}')" "units must be an array"
expect_error "unit missing"             "$(mutate drop-unit '.units |= .[0:1]')" "unit ids must be U1, U2 (the plan's, in order); got U1"
expect_error "unit field changed"       "$(mutate deps '.units[1].depends_on = []')" "U2 depends_on differs from the plan"
expect_error "scope changed"            "$(mutate scope '.units[0].scope = "Just the model."')" "U1 scope differs from the plan"
expect_error "no contract"              "$(mutate no-contract 'del(.units[0].contract)')" "U1 contract must be an object with criteria and personas arrays"
expect_error "criterion missing"        "$(mutate drop-ac '.units[1].contract.criteria |= .[0:1]')" "U2 criteria ids must be exactly its covers (AC2, AC3); got AC2"
expect_error "extra criterion"          "$(mutate extra-ac '.units[0].contract.criteria += [.units[0].contract.criteria[0] | .id = "AC2"]')" "U1 criteria ids must be exactly its covers (AC1); got AC1, AC2"
expect_error "duplicate criterion"      "$(mutate dup-ac '.units[0].contract.criteria += .units[0].contract.criteria')" "U1 criteria ids must be exactly its covers (AC1); got AC1, AC1"
expect_error "statement reworded"       "$(mutate weakened '.units[1].contract.criteria[0].statement = "Picking a saved reply inserts its text."')" "U2 AC2 statement must be copied verbatim from the plan"
expect_error "bad check kind"           "$(mutate kind '.units[1].contract.criteria[0].check.kind = "manual"')" "U2 AC2 check.kind must be test, ui or data"
expect_error "empty check how"          "$(mutate how '.units[1].contract.criteria[1].check.how = "  "')" "U2 AC3 check.how must be a non-empty string"
expect_error "no check"                 "$(mutate no-check 'del(.units[0].contract.criteria[0].check)')" "U1 AC1 check.kind must be test, ui or data"
expect_error "too few personas"         "$(mutate few '.units[0].contract.personas |= .[0:2]')" "U1 has 2 personas; limits.qa_personas allows 3 to 5"
expect_error "too many personas"        "$(mutate many '.units[0].contract.personas += [range(3) | {name: "p\(.)", goals: "g", behaviour: "b"}]')" "U1 has 6 personas; limits.qa_personas allows 3 to 5"
expect_error "no branch"                "$(mutate no-branch 'del(.units[0].contract.branch)')" "U1 contract.branch must be a branch name"
expect_error "branch with spaces"       "$(mutate bad-branch '.units[0].contract.branch = "my branch"')" "U1 contract.branch must be a branch name"
expect_error "same branch twice"        "$(mutate dup-branch '.units[1].contract.branch = .units[0].contract.branch')" "contract.branch must differ between units"
expect_error "no PR title"              "$(mutate no-title '.units[1].contract.pr_title = " "')" "U2 contract.pr_title must be a non-empty title"
expect_error "persona field empty"      "$(mutate persona-empty '.units[1].contract.personas[2].behaviour = ""')" "U2 persona 3 needs non-empty name, goals and behaviour"
expect_error "persona names repeat"     "$(mutate persona-dup '.units[1].contract.personas[1].name = "careless user"')" "U2 persona names must be unique"

jq '.limits.qa_personas = {min: 4, max: 5}' "$fixtures/config.json" >"$work/config-min4.json"
expect_error "config min honoured"      "$fixtures/good.json" "U1 has 3 personas; limits.qa_personas allows 4 to 5" "$work/config-min4.json"

printf '[]' >"$work/config-array.json"
expect_error "config not normalized"    "$fixtures/good.json" "config has no limits.qa_personas min and max; pass read-config.sh output" "$work/config-array.json"

# Every problem is reported, not just the first.
two=$(mutate two '.units[0].contract.personas |= .[0:1] | .units[1].contract.criteria[0].check.how = ""')
bash "$script" "$two" "$fixtures/config.json" "$fixtures/plan.json" >/dev/null 2>"$work/stderr" || true
count=$(grep -c '^units: ' "$work/stderr") || count=0
if [ "$count" = 2 ]; then pass "reports every problem"; else fail "reports every problem" "expected 2 lines, got $count"; fi

echo "validate-units: $passes passed, $failures failed"
[ "$failures" = 0 ]
