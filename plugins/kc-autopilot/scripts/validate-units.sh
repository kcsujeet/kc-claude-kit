#!/usr/bin/env bash
# Checks the units.json /kc-autopilot:kc-run writes before it starts the deliver
# workflow: every unit is the plan's unit unchanged plus a contract that
# skills/kc-run/references/contract-format.md allows.
#   - unit ids, order and plan fields (index, title, depends_on, covers,
#     scope) equal the plan's;
#   - criteria ids are exactly the unit's covers, statements copied verbatim;
#   - every check has kind test|ui|data and a non-empty how;
#   - personas: limits.qa_personas.min..max, each with name, goals and
#     behaviour, names unique (the workflow keys QA results by name);
#   - contract.branch is a plain branch name, unique across units, and
#     contract.pr_title is non-empty (both in the repo's own convention).
#
# Usage: validate-units.sh <units.json> <config.json> <plan.json>
#   units.json  {"architecture": "...", "units": [plan unit + "contract"]}
#   config.json read-config.sh output
#   plan.json   validate-plan.sh output
# Output: nothing on stdout.
# Exit: 0 valid; 1 invalid (one "units: <problem>" line per problem on
# stderr); 2 jq missing.
set -euo pipefail

command -v jq >/dev/null 2>&1 || { echo "autopilot: jq is required" >&2; exit 2; }
[ $# = 3 ] || { echo "usage: validate-units.sh <units.json> <config.json> <plan.json>" >&2; exit 1; }

for file in "$@"; do
  [ -f "$file" ] || { echo "units: $file not found" >&2; exit 1; }
  jq empty "$file" >/dev/null 2>&1 || { echo "units: $file is not valid JSON" >&2; exit 1; }
done

# jq program: $-variables are jq's, not the shell's.
# shellcheck disable=SC2016
readonly PROBLEMS='
  def nonempty: type == "string" and (gsub("^\\s+|\\s+$"; "") | length) > 0;
  def arr: if type == "array" then . else [] end;
  def obj: if type == "object" then . else {} end;
  def ids: map(if type == "object" then .id else null end | tostring) | join(", ");
  . as $u
  | ($plan | obj | .criteria | arr | map({key: .id, value: .statement}) | from_entries) as $statements
  | ($plan | obj | .units | arr) as $planUnits
  | ($config | obj | .limits | obj | .qa_personas | obj) as $qa
  | $qa.min as $min
  | $qa.max as $max
  | [
      (if ($u | type) != "object" then "units.json must be a JSON object" else empty end),
      (if ($u | type) == "object" and ($u.architecture | nonempty | not) then "architecture must be a non-empty string" else empty end),
      (if ($u | type) == "object" and ($u.architecture | nonempty) and ($u.architecture | test("Design review") | not) then "architecture has no Design review section (see run step 2)" else empty end),
      (if ($u | type) == "object" and ($u.units | type) != "array" then "units must be an array" else empty end),
      (if ($min | type) != "number" or ($max | type) != "number" then "config has no limits.qa_personas min and max; pass read-config.sh output" else empty end),
      (if ($u | type) == "object" and ($u.units | type) == "array" then
        ($u.units | map(select(type == "object"))) as $units
        | (if ($units | map(.contract.branch? // empty) | (unique | length) != length)
            then "contract.branch must differ between units" else empty end),
          (if ($u.units | ids) != ($planUnits | ids)
            then "unit ids must be \($planUnits | ids) (the plan'"'"'s, in order); got \($u.units | ids)" else empty end),
          ($units[] | . as $unit
            | ($planUnits | map(select(.id == $unit.id))[0]) as $p
            | select($p != null)
            | (["index", "title", "depends_on", "covers", "scope"][] | select($unit[.] != $p[.]) | "\($unit.id) \(.) differs from the plan"),
              (if ($unit.contract | type) != "object" or ($unit.contract.criteria | type) != "array" or ($unit.contract.personas | type) != "array"
                then "\($unit.id) contract must be an object with criteria and personas arrays"
                else
                  ($unit.contract.criteria) as $criteria
                  | ($unit.contract.personas) as $personas
                  | (if ($criteria | map(if type == "object" then .id else null end) | sort) != ($p.covers | sort)
                      then "\($unit.id) criteria ids must be exactly its covers (\($p.covers | join(", "))); got \($criteria | ids)" else empty end),
                    ($criteria[] | select(type == "object") | . as $c
                      | (if ($p.covers | index($c.id)) and $c.statement != $statements[$c.id]
                          then "\($unit.id) \($c.id) statement must be copied verbatim from the plan" else empty end),
                        (if (["test", "ui", "data"] | index($c.check.kind? // null)) == null
                          then "\($unit.id) \($c.id) check.kind must be test, ui or data" else empty end),
                        (if ($c.check.how? // null | nonempty | not)
                          then "\($unit.id) \($c.id) check.how must be a non-empty string" else empty end)),
                    (if ($min | type) == "number" and ($max | type) == "number" and (($personas | length) < $min or ($personas | length) > $max)
                      then "\($unit.id) has \($personas | length) personas; limits.qa_personas allows \($min) to \($max)" else empty end),
                    ($personas | to_entries[]
                      | select((.value | type) != "object" or ([.value.name, .value.goals, .value.behaviour] | all(nonempty) | not))
                      | "\($unit.id) persona \(.key + 1) needs non-empty name, goals and behaviour"),
                    (if ($personas | map(if type == "object" then .name else null end) | unique | length) != ($personas | length)
                      then "\($unit.id) persona names must be unique" else empty end),
                    (if ($unit.contract.branch | type) != "string" or ($unit.contract.branch | test("^[A-Za-z0-9][A-Za-z0-9._/-]*$") | not)
                      then "\($unit.id) contract.branch must be a branch name in the repo'"'"'s convention (letters, digits, . _ / -)" else empty end),
                    (if ($unit.contract.pr_title | nonempty | not)
                      then "\($unit.id) contract.pr_title must be a non-empty title in the repo'"'"'s convention" else empty end)
                end))
      else empty end)
    ] | .[]'

problems=$(jq -r --slurpfile config "$2" --slurpfile plan "$3" \
  '($config[0]) as $config | ($plan[0]) as $plan | '"$PROBLEMS" "$1" 2>/dev/null) || {
  echo "units: could not check $1 (jq failed)" >&2
  exit 1
}

if [ -n "$problems" ]; then
  printf '%s\n' "$problems" | sed 's/^/units: /' >&2
  exit 1
fi
