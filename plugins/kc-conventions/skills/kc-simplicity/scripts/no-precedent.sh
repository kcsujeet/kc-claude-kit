#!/usr/bin/env bash
# simplicity §P19: tokens the diff's added lines introduce that the repo does not use anywhere at
# the base, so each new way of doing a job is checked against how the codebase already does it.
#
# Usage: no-precedent.sh <diff-file|-> [<repo-root>] [--base <ref>]
#
# Prints `path:line: [no precedent: <kind> <token>] text` per added line. The kinds:
#   package    a bare module an added line imports (import ... from 'x', require('x'), python
#              `import x`); relative and alias paths are the repo's own files and are skipped
#   unit       a CSS length, angle or container unit after a number (20cqw, 100dvh, 2fr)
#   at-rule    a CSS at-rule (@container, @supports, @layer, @scope, @property)
#   css-prop   a property declared in a stylesheet (css, scss, less)
#   global-api a browser global's member (navigator.clipboard, document.startViewTransition)
#   test-mock  a mocking or stubbing call (vi.mock, jest.spyOn, sinon.stub, cy.intercept)
#   config-key a key added to a config file (yaml, toml, ini, *rc, *.config.*, tsconfig, package.json)
#   file-name  the compound suffix of an added file (*.spec.tsx, *.stories.tsx, *.module.css)
# A hit means no other file in the repo does that: use the way the codebase already does the job,
# or say why it can't. Without --base the repo's tracked files are read as the head checkout and
# the diff's own added lines are subtracted; with --base the tree at that ref is read. Markdown
# files are not counted as uses. Exits 0 with or without hits, 2 on a usage error.
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=../../../scripts/lib/diff-lines.sh
. "$script_dir/../../../scripts/lib/diff-lines.sh"

usage_tail=" [<repo-root>] [--base <ref>]"
[ "$#" -ge 1 ] || kc_require_diff_arg "$(basename "$0")" "" "$usage_tail"
diff_file=$1
shift
repo_root=.
base_ref=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --base) [ "$#" -ge 2 ] || kc_require_diff_arg "$(basename "$0")" "" "$usage_tail"; base_ref=$2; shift 2 ;;
    *) repo_root=$1; shift ;;
  esac
done
kc_require_diff_arg "$(basename "$0")" "$diff_file" "$usage_tail"

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
export KC_STYLE_PATHS='\.(css|scss|less)$'
export KC_CONFIG_PATHS='(\.(ya?ml|toml|ini)$|(^|/)\.[a-z]+rc(\.json)?$|\.config\.[a-z]+$|(^|/)tsconfig[^/]*\.json$|(^|/)package\.json$)'
export KC_SOURCE_PATHS='\.(css|scss|less|js|jsx|ts|tsx|mjs|cjs|vue|svelte|html|py|rb|go|rs|java|kt|swift|php|cs|sh)$'

kc_added_lines "$diff_file" > "$work_dir/added.tsv"

# Candidates: <kind> <token> <ERE that finds a use of the token> <path> <line> <text>, tab-separated.
awk -F '\t' '
  function emit_candidate(kind, token, ere, path, line, text) { printf "%s\t%s\t%s\t%s\t%s\t%s\n", kind, token, ere, path, line, text }
  function escape_ere(token) { gsub(/[][\\.^$*+?(){}|\/-]/, "\\\\&", token); return token }
  function add_rule(kind, pattern, strip_lead, strip_trail, use_template) {
    rule_kind[rule_count] = kind; rule_pattern[rule_count] = pattern; rule_lead[rule_count] = strip_lead
    rule_trail[rule_count] = strip_trail; rule_use[rule_count] = use_template; rule_count++
  }
  # A bare package name from an import source; empty for the own files of a repo (relative, alias, url).
  function get_package_name(source,   parts, part_count, is_relative_source, is_alias_source, has_url_scheme, is_node_builtin, is_own_file, is_scoped) {
    is_relative_source = (source ~ /^[.\/~#$]/)
    is_alias_source = (source ~ /^@\//)
    has_url_scheme = (source ~ /^[a-z]+:/)
    is_node_builtin = (source ~ /^node:/)
    is_own_file = (is_relative_source || is_alias_source)
    if (is_own_file || (has_url_scheme && !is_node_builtin)) return ""
    part_count = split(source, parts, "/")
    is_scoped = (source ~ /^@/)
    if (!is_scoped) return parts[1]
    if (part_count < 2) return ""
    return parts[1] "/" parts[2]
  }
  function scan_rules(text, path, line,   rule, rest, found, token) {
    for (rule = 0; rule < rule_count; rule++) {
      rest = text
      while (match(rest, rule_pattern[rule])) {
        found = substr(rest, RSTART, RLENGTH)
        rest = substr(rest, RSTART + RLENGTH - 1)
        token = found; sub(rule_lead[rule], "", token); sub(rule_trail[rule], "", token)
        if (rule_kind[rule] == "package") token = get_package_name(token)
        if (token == "") continue
        use_ere = rule_use[rule]; sub(/%s/, escape_ere(token), use_ere)
        emit_candidate(rule_kind[rule], token, use_ere, path, line, text)
      }
    }
  }
  BEGIN {
    rule_count = 0
    add_rule("package", "(from|import|require\\(?)[[:space:]]*[\047\"][^\047\"]+[\047\"]", "^[^\047\"]*[\047\"]", "[\047\"]$", "(^|[^A-Za-z0-9_@/.-])%s([^A-Za-z0-9_-]|$)")
    add_rule("unit", "[0-9.](cqw|cqh|cqi|cqb|cqmin|cqmax|dvh|dvw|dvi|dvb|dvmin|dvmax|svh|svw|svi|svb|svmin|svmax|lvh|lvw|lvi|lvb|lvmin|lvmax|vmin|vmax|vh|vw|rem|em|ex|ch|fr|deg|rad|turn)([^A-Za-z0-9_]|$)", "^[0-9.]", "[^A-Za-z0-9_]$", "[0-9.]%s([^A-Za-z0-9_]|$)")
    add_rule("at-rule", "@(container|supports|layer|scope|property|starting-style)([^A-Za-z0-9_-]|$)", "^$", "[^A-Za-z0-9_-]$", "%s([^A-Za-z0-9_-]|$)")
    add_rule("global-api", "(^|[^A-Za-z0-9_.])(navigator|window|document|screen|localStorage|sessionStorage|indexedDB|crypto)\\.[A-Za-z_]+", "^[^A-Za-z]", "^$", "(^|[^A-Za-z0-9_.])%s([^A-Za-z0-9_]|$)")
    add_rule("test-mock", "(^|[^A-Za-z0-9_.])(vi|jest|sinon|cy|nock)\\.[A-Za-z_]+", "^[^A-Za-z]", "^$", "(^|[^A-Za-z0-9_.])%s([^A-Za-z0-9_]|$)")
  }
  {
    path = $1; line = $2; text = $0; sub(/^[^\t]*\t[^\t]*\t/, "", text)
    is_source_file = (path ~ ENVIRON["KC_SOURCE_PATHS"])
    is_config_file = (path ~ ENVIRON["KC_CONFIG_PATHS"])
    is_style_file = (path ~ ENVIRON["KC_STYLE_PATHS"])
    if (!is_source_file && !is_config_file) next
    if (is_source_file) scan_rules(text, path, line)
    is_python_file = (path ~ /\.py$/)
    if (is_python_file && match(text, /^[[:space:]]*(import|from)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*/)) {
      module = substr(text, RSTART, RLENGTH); sub(/^[[:space:]]*(import|from)[[:space:]]+/, "", module)
      emit_candidate("package", module, "(import|from)[[:space:]]+" module "([^A-Za-z0-9_]|$)", path, line, text)
    }
    if (is_style_file) {
      rest = text
      while (match(rest, /(^|[{;])[[:space:]]*[a-z][a-z-]*[[:space:]]*:[^;{}]*;/)) {
        prop = substr(rest, RSTART, RLENGTH); sub(/^[{;]?[[:space:]]*/, "", prop); sub(/[[:space:]]*:.*$/, "", prop)
        emit_candidate("css-prop", prop, "(^|[^A-Za-z0-9_-])" prop "[[:space:]]*:", path, line, text)
        rest = substr(rest, RSTART + RLENGTH - 1)
      }
    }
    if (is_config_file && match(text, /^[[:space:]]*[\047\"]?[A-Za-z_][A-Za-z0-9_.-]*[\047\"]?[[:space:]]*:/)) {
      key = substr(text, RSTART, RLENGTH); gsub(/^[[:space:]]*[\047\"]?|[\047\"]?[[:space:]]*:$/, "", key)
      emit_candidate("config-key", key, "(^|[^A-Za-z0-9_.-])[\047\"]?" escape_ere(key) "[\047\"]?[[:space:]]*:", path, line, text)
    }
  }
' "$work_dir/added.tsv" > "$work_dir/candidates.tsv"

# File-name suffixes: the compound suffix of every added file (Card.spec.tsx gives *.spec.tsx).
kc_added_files "$diff_file" | while IFS= read -r added_path; do
  base_name=${added_path##*/}
  case "$base_name" in
    *.*.*) suffix=".${base_name#*.}" ;;
    *) continue ;;
  esac
  printf 'file-name\t*%s\t-\t%s\t1\t%s\n' "$suffix" "$added_path" "$base_name" >> "$work_dir/candidates.tsv"
done

# Uses at the base per distinct token; the diff's own distinct added lines are subtracted when the
# head is checked out. Zero uses are reported.
: > "$work_dir/new.txt"
tree_ref=()
if [ -n "$base_ref" ]; then tree_ref=("$base_ref"); fi
cut -f1,2,3 "$work_dir/candidates.tsv" | sort -u | while IFS=$'\t' read -r kind token ere; do
  token_lines_in_diff=0
  if [ -z "$base_ref" ]; then
    token_lines_in_diff=$(awk -F '\t' -v kind="$kind" -v token="$token" '{ is_kind_match = ($1 == kind); is_token_match = ($2 == token) } is_kind_match && is_token_match { print $4 ":" $5 }' "$work_dir/candidates.tsv" | sort -u | grep -c . || true)
  fi
  if [ "$kind" = file-name ]; then
    if [ -n "$base_ref" ]; then token_uses=$(git -C "$repo_root" ls-tree -r --name-only "$base_ref" | grep -cF -e "${token#\*}" || true)
    else token_uses=$(git -C "$repo_root" ls-files | grep -cF -e "${token#\*}" || true); fi
  else
    token_uses=$(git -C "$repo_root" grep -I -h -E -e "$ere" ${tree_ref[@]+"${tree_ref[@]}"} -- . ':!*.md' 2>/dev/null | wc -l || true)
  fi
  if [ $((token_uses - token_lines_in_diff)) -le 0 ]; then printf '%s\t%s\n' "$kind" "$token" >> "$work_dir/new.txt"; fi
done
awk -F '\t' 'NR == FNR { new_tokens[$1 "\t" $2] = 1; next }
  (($1 "\t" $2) in new_tokens) { printf "%s:%s: [no precedent: %s %s] %s\n", $4, $5, $1, $2, $6 }
' "$work_dir/new.txt" "$work_dir/candidates.tsv"
