#!/usr/bin/env bash
# react §R39: CSS the diff adds that the repo does not already use, and a container-query length
# unit set where it measures the wrong box.
#
# Usage: new-css-features.sh <diff-file|-> [<repo-root> [<base-ref>]]
#
# Two kinds of hit, one `path:line: [reason] text` per added line:
#   - [new to the repo: <feature>]  an added line uses a CSS unit or feature (a viewport or
#     container-query unit such as cqw, dvh or svh; @container; @supports on a property;
#     container-type; :has(); @layer; subgrid; color-mix()) that has zero uses in the repo at the
#     base. The author uses the units and features the repo already uses, or says why they can't.
#     Uses are counted in style and script files (css, scss, less, js, jsx, ts, tsx, mjs, vue,
#     svelte, html) at <base-ref> when given; otherwise in the working tree of <repo-root>
#     (default: the current directory), taken to be the head checkout, minus the lines the diff adds.
#   - [cq unit on the container]  a container-query length unit (cqw, cqh, cqi, cqb, cqmin, cqmax)
#     on the same style object or rule as the container-type that makes its element a container.
#     A cq unit measures the nearest ancestor container, never the element's own box, so there it
#     measures the next container up, often the viewport. Put the unit on a descendant.
# Only lines the diff adds are read; runs of added lines are scoped by their braces. Exits 0 with
# or without hits, 2 on a usage error.
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=../../../scripts/lib/diff-lines.sh
. "$script_dir/../../../scripts/lib/diff-lines.sh"

if [ "$#" -lt 1 ] || [ "$#" -gt 3 ]; then kc_require_diff_arg "$(basename "$0")" "" " [<repo-root> [<base-ref>]]"; fi
kc_require_diff_arg "$(basename "$0")" "$1" " [<repo-root> [<base-ref>]]"
diff_file=$1
repo_root=${2:-.}
base_ref=${3:-}

export KC_PATHS='\.(css|scss|less|js|jsx|ts|tsx|mjs|vue|svelte|html)$'
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
pathspecs=('*.css' '*.scss' '*.less' '*.js' '*.jsx' '*.ts' '*.tsx' '*.mjs' '*.vue' '*.svelte' '*.html')

kc_added_lines "$diff_file" > "$work_dir/added.tsv"

# Written once, read by both awk programs below.
export KC_CQ_UNITS='cqw|cqh|cqi|cqb|cqmin|cqmax'
export KC_CONTAINER_KEY='(containerType|container-type)[^[:alnum:][:space:]:]?[[:space:]]*:'

# Features: <name><TAB><ERE> per added line that uses one, in a style or script file.
awk -F '\t' '
  function add_feature(name, ere) { names[n] = name; eres[n] = ere; n++ }
  function add_unit(unit) { add_feature(unit, "[0-9.]" unit "([^A-Za-z0-9_]|$)") }
  BEGIN {
    n = 0
    cq_count = split(ENVIRON["KC_CQ_UNITS"], cq_list, "|")
    for (i = 1; i <= cq_count; i++) add_unit(cq_list[i])
    viewport_count = split("dvh dvw dvi dvb dvmin dvmax svh svw lvh lvw", viewport_list, " ")
    for (i = 1; i <= viewport_count; i++) add_unit(viewport_list[i])
    add_feature("@container", "@container([^A-Za-z0-9_-]|$)")
    add_feature("container-type", ENVIRON["KC_CONTAINER_KEY"])
    add_feature(":has()", ":has\\(")
    add_feature("@layer", "@layer([^A-Za-z0-9_-]|$)")
    add_feature("subgrid", "subgrid")
    add_feature("color-mix()", "color-mix\\(")
  }
  $1 !~ ENVIRON["KC_PATHS"] { next }
  {
    text = $0
    sub(/^[^\t]*\t[^\t]*\t/, "", text)
    for (i = 0; i < n; i++) if (text ~ eres[i]) printf "%s\t%s\t%s\t%s\t%s\n", names[i], eres[i], $1, $2, text
    if (match(text, /@supports[^{]*\(\(?[[:space:]]*(not[[:space:]]+)?[a-z-]+[[:space:]]*:/)) {
      probe = substr(text, RSTART, RLENGTH)
      sub(/^.*\(/, "", probe); sub(/[[:space:]]*:$/, "", probe); sub(/^not[[:space:]]+/, "", probe)
      printf "@supports (%s)\t@supports[^{]*%s[[:space:]]*:\t%s\t%s\t%s\n", probe, probe, $1, $2, text
    }
  }
' "$work_dir/added.tsv" > "$work_dir/candidates.tsv"

# Zero uses at the base: the feature names to report.
: > "$work_dir/new.txt"
cut -f1,2 "$work_dir/candidates.tsv" | sort -u | while IFS=$'\t' read -r feature_name feature_ere; do
  if [ -n "$base_ref" ]; then
    feature_use_count=$(git -C "$repo_root" grep -I -h -E -e "$feature_ere" "$base_ref" -- "${pathspecs[@]}" 2>/dev/null | wc -l || true)
    feature_use_count_in_diff=0
  else
    feature_use_count=$(git -C "$repo_root" grep -I -h -E -e "$feature_ere" -- "${pathspecs[@]}" 2>/dev/null | wc -l || true)
    feature_use_count_in_diff=$(cut -f1 "$work_dir/candidates.tsv" | grep -cxF "$feature_name" || true)
  fi
  if [ $((feature_use_count - feature_use_count_in_diff)) -le 0 ]; then printf '%s\n' "$feature_name" >> "$work_dir/new.txt"; fi
done
awk -F '\t' 'NR == FNR { new_names[$0] = 1; next }
  ($1 in new_names) { printf "%s:%s: [new to the repo: %s] %s\n", $3, $4, $1, $5 }
' "$work_dir/new.txt" "$work_dir/candidates.tsv"

# A cq unit on the same style object or rule as the container-type that makes it a container.
awk -F '\t' '
  function reset_scopes() { depth = 0; next_id = 1; stack[0] = 0; delete has_container; delete pending }
  function emit_cq_on_container_hit(path, line, text) { printf "%s:%s: [cq unit on the container: it measures the next container up, not this element] %s\n", path, line, text }
  function is_container_type_declaration(segment) { return segment ~ ENVIRON["KC_CONTAINER_KEY"] }
  function is_container_shorthand_with_size(segment) { return segment ~ /(^|[^A-Za-z-])container[^[:alnum:][:space:]:]?[[:space:]]*:[^;]*size/ }
  function scan_segment_for_cq_units(segment, scope, path, line, text) {
    if (is_container_type_declaration(segment) || is_container_shorthand_with_size(segment)) {
      has_container[scope] = 1
      for (key in pending) { split(key, parts, SUBSEP); if (parts[1] == scope) { emit_cq_on_container_hit(path, parts[2], pending[key]); delete pending[key] } }
    }
    if (segment ~ cq_unit_pattern) {
      if (has_container[scope]) emit_cq_on_container_hit(path, line, text)
      else pending[scope, line] = text
    }
  }
  BEGIN { cq_unit_pattern = "[0-9.](" ENVIRON["KC_CQ_UNITS"] ")([^A-Za-z0-9_]|$)"; reset_scopes() }
  {
    path = $1; line = $2 + 0; text = $0; sub(/^[^\t]*\t[^\t]*\t/, "", text)
    if (path !~ ENVIRON["KC_PATHS"]) next
    if (path != last_path || line != last_line + 1) reset_scopes()
    last_path = path; last_line = line
    segment = ""
    for (i = 1; i <= length(text); i++) {
      ch = substr(text, i, 1)
      if (ch == "{") { scan_segment_for_cq_units(segment, stack[depth], path, line, text); segment = ""; depth++; stack[depth] = next_id++ }
      else if (ch == "}") { scan_segment_for_cq_units(segment, stack[depth], path, line, text); segment = ""; if (depth > 0) depth-- }
      else segment = segment ch
    }
    scan_segment_for_cq_units(segment, stack[depth], path, line, text)
  }
' "$work_dir/added.tsv"
