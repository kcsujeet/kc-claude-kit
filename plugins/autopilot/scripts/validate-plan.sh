#!/usr/bin/env bash
# Parses a plan written to skills/run/references/plan-template.md and checks
# its rules. Prints the parsed plan as JSON on stdout.
#
# Usage: validate-plan.sh <plan.md>
# Exit: 0 valid; 1 invalid (one "plan: <problem>" line per problem on
# stderr); 2 jq missing.
set -euo pipefail

command -v jq >/dev/null 2>&1 || { echo "autopilot: jq is required" >&2; exit 2; }
plan=${1:?usage: validate-plan.sh <plan.md>}
[ -f "$plan" ] || { echo "plan: $plan not found" >&2; exit 1; }

# awk emits tab-separated records: kind<TAB>field…; jq assembles them.
# POSIX awk only (BSD awk on macOS, gawk/mawk on Ubuntu).
records=$(awk '
  function trim(s) { sub(/^[ \t\r]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
  /^# / && title == "" { title = trim(substr($0, 3)); print "title\t" title; next }
  /^## / { section = trim(substr($0, 4)); print "section\t" section; unit = ""; next }
  section == "Goal" && NF { print "goal\t" trim($0); next }
  section == "Out of scope" && NF { print "oos\t" trim($0); next }
  section == "Acceptance criteria" && /^[0-9]+\. / {
    n++; line = $0; sub(/^[0-9]+\. /, "", line); print "criterion\tAC" n "\t" trim(line); next
  }
  section == "Work units" && /^### U[0-9]+:/ {
    line = $0; sub(/^### /, "", line)
    unit = line; sub(/:.*/, "", unit)
    t = line; sub(/^U[0-9]+:[ \t]*/, "", t)
    print "unit\t" unit "\t" trim(t); next
  }
  section == "Work units" && unit != "" && /^- Depends on:/ {
    line = $0; sub(/^- Depends on:[ \t]*/, "", line); print "depends\t" unit "\t" trim(line); next
  }
  section == "Work units" && unit != "" && /^- Covers:/ {
    line = $0; sub(/^- Covers:[ \t]*/, "", line); print "covers\t" unit "\t" trim(line); next
  }
  section == "Work units" && unit != "" && NF { print "scope\t" unit "\t" trim($0); next }
' "$plan")

parsed=$(printf '%s\n' "$records" | jq -R -s '
  def list: if . == "" or (ascii_downcase == "none") then [] else split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(. != "")) end;
  split("\n") | map(select(. != "") | split("\t")) as $r
  | ($r | map(select(.[0] == "unit")) | to_entries | map({id: .value[1], index: .key, title: .value[2]})) as $units
  | {
      title: ($r | map(select(.[0] == "title"))[0][1] // ""),
      sections: ($r | map(select(.[0] == "section") | .[1])),
      goal: ($r | map(select(.[0] == "goal") | .[1]) | join(" ")),
      criteria: ($r | map(select(.[0] == "criterion") | {id: .[1], statement: .[2]})),
      units: ($units | map(. as $u | . + {
        depends_on: ([$r[] | select(.[0] == "depends" and .[1] == $u.id) | .[2]][0] // "none" | list),
        covers: ([$r[] | select(.[0] == "covers" and .[1] == $u.id) | .[2]][0] // "" | list),
        scope: ([$r[] | select(.[0] == "scope" and .[1] == $u.id) | .[2]] | join(" "))
      })),
      out_of_scope: ($r | map(select(.[0] == "oos") | .[1]) | join("\n"))
    }')

# Stacked PRs are linear, so a unit with several dependencies must have one
# that (transitively) depends on all the others; the unit stacks on that one.
# Ancestors are a bounded fixed point, so a dependency cycle cannot hang jq.
problems=$(printf '%s' "$parsed" | jq -r '
  def ancestors($m; $id): reduce range(0; $m | length) as $_ ($m[$id] // []; (. + [.[] | ($m[.] // [])[]]) | unique);
  . as $p
  | ($p.units | map({key: .id, value: .depends_on}) | from_entries) as $deps
  | ($p.criteria | map(.id)) as $ids
  | ($p.units | map(.id)) as $uids
  | [
      (if $p.title == "" then "missing title: a \"# <Plan title>\" line" else empty end),
      (["Goal", "Acceptance criteria", "Work units", "Out of scope"][] | select(. as $s | $p.sections | index($s) | not) | "missing section: ## \(.)"),
      (if ($p.sections | index("Acceptance criteria")) and ($ids | length) == 0 then "## Acceptance criteria has no numbered criteria" else empty end),
      (if ($p.sections | index("Work units")) and ($uids | length) == 0 then "## Work units has no ### U<n>: units" else empty end),
      ($p.units | to_entries[] | select(.value.id != "U\(.key + 1)") | "units must be numbered U1, U2, … in order; found \(.value.id)"),
      ($p.units[] | . as $u | .covers[] | select(. as $c | $ids | index($c) | not) | "\($u.id) covers unknown criterion \(.)"),
      ($p.units[] | . as $u | .depends_on[] | select(. as $d | ($uids[0:$u.index] | index($d)) | not) | "\($u.id) depends on \(.), which is not an earlier unit"),
      ($p.units[] | select(.depends_on | length > 1) | . as $u
        | select([.depends_on[] as $d | ($u.depends_on - [$d] - ancestors($deps; $d)) | length == 0] | any | not)
        | [range(0; .depends_on | length) as $i | range($i + 1; .depends_on | length) as $j | [.depends_on[$i], .depends_on[$j]]
           | select(([.[0]] - ancestors($deps; .[1]) | length) > 0 and ([.[1]] - ancestors($deps; .[0]) | length) > 0)][0]
        | select(. != null) | "\($u.id) depends on independent units \(.[0]) and \(.[1]); make one depend on the other"),
      ($p.units[] | select(.covers | length == 0) | "\(.id) has no - Covers: line"),
      ($ids[] | select(. as $c | [$p.units[].covers[]] | index($c) | not) | "\(.) is not covered by any unit")
    ] | .[]')

if [ -n "$problems" ]; then
  printf '%s\n' "$problems" | sed 's/^/plan: /' >&2
  exit 1
fi
printf '%s' "$parsed" | jq -c 'del(.sections)'
