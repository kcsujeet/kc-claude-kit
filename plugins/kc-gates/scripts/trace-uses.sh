#!/usr/bin/env bash
# Where it's used: lists every use, across the repo and any sibling repo named, of each thing a diff
# changes, and the tests that cover those uses. A change's damage usually lands in another file
# that uses the changed thing, not beside the change, and a reviewer who searches for those uses
# misses some; one who is handed the list and judges each item does not.
#
# What counts as changed, read from the diff's added and removed lines and its hunk headers:
#   - a function, method, class, module, type, interface or enum defined there, or the one a hunk
#     sits in (the name git puts after the second @@);
#   - an exported or top-level constant or variable;
#   - a member removed or changed in an object type or literal (a prop, a field, a key);
#   - a column, attribute, association, scope or serializer field named in a schema or model DSL;
#   - a route path;
#   - for a props type (`OrderCardProps`), the component it types (`OrderCard`) as well.
#
# A use is a line, in a file the repo tracks, that holds the name as a whole word (a route as a
# plain string). Lines the diff adds and the name's own definition are left out: the review reads
# those already. Each use gets one verdict from whoever reads the list: breaks, behaviour changes
# or fine.
#
# Usage: trace-uses.sh <diff-file|-> [--also <repo-dir>]...
#        trace-uses.sh --symbols <name>[,<name>...] [--also <repo-dir>]...
#   <diff-file|->  a unified diff (`git diff`); run from the root of the repo it applies to
#   --symbols      trace these names instead of reading a diff (a fix suggested in a comment)
#   --also         a sibling repo whose uses count too (a frontend beside its API); repeatable
#
# Prints one block per name, then the tests and a summary line:
#   name <name> (<kind>, <path>): <n> uses
#     <path>:<line>: <text>
#   tests: <n>
#     <test path>
#   summary: <names> names, <uses> uses, <tests> test files
#
# Portable to bash 3.2 and BSD awk.
set -euo pipefail

usage() {
  echo "usage: trace-uses.sh <diff-file|-> [--also <repo-dir>]..." >&2
  echo "       trace-uses.sh --symbols <name>[,<name>...] [--also <repo-dir>]..." >&2
  exit 2
}

[ "$#" -ge 1 ] || usage
diff_arg=""
symbol_list=""
also_dirs=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --symbols) [ "$#" -ge 2 ] || usage; symbol_list=$2; shift 2 ;;
    --also) [ "$#" -ge 2 ] || usage; also_dirs+=("$2"); shift 2 ;;
    -*) [ "$1" = "-" ] || usage; diff_arg=$1; shift ;;
    *) diff_arg=$1; shift ;;
  esac
done
if [ -z "$diff_arg" ] && [ -z "$symbol_list" ]; then usage; fi
if [ -n "$diff_arg" ] && [ -n "$symbol_list" ]; then usage; fi
if [ -n "$diff_arg" ] && [ "$diff_arg" != "-" ] && [ ! -r "$diff_arg" ]; then
  echo "trace-uses.sh: cannot read diff file: $diff_arg" >&2
  exit 2
fi
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "trace-uses.sh: run it from the root of the repo the diff applies to" >&2
  exit 2
}
for also_dir in ${also_dirs[@]+"${also_dirs[@]}"}; do
  git -C "$also_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo "trace-uses.sh: not a git work tree: $also_dir" >&2
    exit 2
  }
done

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
names_file="$work_dir/names.tsv"     # name<TAB>kind<TAB>path
added_file="$work_dir/added.txt"     # path:line of every line the diff adds

if [ -n "$symbol_list" ]; then
  printf '%s\n' "$symbol_list" | tr ',' '\n' | awk 'NF { gsub(/^[ \t]+|[ \t]+$/, ""); printf "%s\tnamed\t-\n", $0 }' > "$names_file"
  : > "$added_file"
else
  diff_copy="$work_dir/input.diff"
  if [ "$diff_arg" = "-" ]; then cat > "$diff_copy"; else cat "$diff_arg" > "$diff_copy"; fi
  awk -v added_out="$added_file" -v squote="'" '
    function reset_hunk() { old_left = 0; new_left = 0 }
    function is_word(name) {
      return name !~ /^(if|else|elsif|unless|for|while|switch|case|when|return|function|def|class|module|new|this|self|super|true|false|null|nil|undefined|constructor|render|default|export|import|from|async|await|const|let|var|type|interface|do|end|then|catch|try|yield|begin|rescue|ensure|raise|throw|static|public|private|protected|readonly|change|initialize|up|down)$/ && length(name) >= 3
    }
    function emit(name, kind) {
      if (!is_word(name) || path == "") return
      printf "%s\t%s\t%s\n", name, kind, path
      if (name ~ /Props$/ && length(name) > 5) printf "%s\tcomponent\t%s\n", substr(name, 1, length(name) - 5), path
    }
    # The name a definition introduces, or "" when the text defines nothing.
    function defined_name(text,   piece) {
      if (match(text, /(^|[^A-Za-z0-9_$.])(function[*]?|def|class|module|interface|type|enum|struct|trait|fn)[ \t]+(self[.])?[A-Za-z_$][A-Za-z0-9_$]*[?!]?/)) {
        piece = substr(text, RSTART, RLENGTH)
        sub(/^.*(function[*]?|def|class|module|interface|type|enum|struct|trait|fn)[ \t]+(self[.])?/, "", piece)
        return piece
      }
      if (match(text, /(^|[^A-Za-z0-9_])func[ \t]+(\([^)]*\)[ \t]*)?[A-Za-z_][A-Za-z0-9_]*/)) {
        piece = substr(text, RSTART, RLENGTH)
        sub(/^.*func[ \t]+(\([^)]*\)[ \t]*)?/, "", piece)
        return piece
      }
      if (match(text, /^(export[ \t]+)?(const|let|var)[ \t]+[A-Za-z_$][A-Za-z0-9_$]*/)) {
        piece = substr(text, RSTART, RLENGTH)
        sub(/^(export[ \t]+)?(const|let|var)[ \t]+/, "", piece)
        return piece
      }
      if (match(text, /^[A-Za-z_][A-Za-z0-9_]*[ \t]*=[^=>]/)) {
        piece = substr(text, RSTART, RLENGTH)
        sub(/[ \t]*=.*$/, "", piece)
        return piece
      }
      if (match(text, /^[ \t]+((async|static|public|private|protected|override|get|set)[ \t]+)*[A-Za-z_$][A-Za-z0-9_$]*[ \t]*\([^)]*\)[ \t]*(:[^{]*)?\{[ \t]*$/)) {
        piece = text
        sub(/^[ \t]+((async|static|public|private|protected|override|get|set)[ \t]+)*/, "", piece)
        sub(/[ \t]*\(.*$/, "", piece)
        return piece
      }
      return ""
    }
    # Symbols a schema, model or serializer DSL line names: `t.string :email`,
    # `add_column :orders, :status`, `has_many :items, dependent: :destroy`, `attributes :a, :b`.
    function emit_dsl(text,   rest, keyword, wanted, position, symbol) {
      if (text !~ /^[ \t]*(t[.][a-z_]+|attribute|attributes|attr_accessor|attr_reader|column|add_column|remove_column|rename_column|change_column|add_reference|remove_reference|add_index|scope|has_many|has_one|belongs_to|has_and_belongs_to_many|delegate|validates|field|fields|resources|resource)[ \t(]/) return
      rest = text
      sub(/^[ \t]*/, "", rest)
      keyword = rest
      sub(/[ \t(].*$/, "", keyword)
      # A migration call names the table first and a type after the column: keep the column (and
      # the new name of a renamed one). Every other keyword names only fields.
      wanted = 0
      if (keyword ~ /^(add_column|remove_column|change_column|add_reference|remove_reference)$/) wanted = 2
      if (keyword == "rename_column") wanted = 23
      if (keyword == "add_index") wanted = -1
      position = 0
      sub(/^[^ \t(]+[ \t(]*/, "", rest)
      sub(/[A-Za-z_]+:[ \t].*$/, "", rest)
      while (match(rest, /(^|[^:A-Za-z0-9_]):[A-Za-z_][A-Za-z0-9_]*[?!]?/)) {
        symbol = substr(rest, RSTART, RLENGTH)
        rest = substr(rest, RSTART + RLENGTH)
        sub(/^[^:]*:/, "", symbol)
        position++
        if (wanted == -1 && position == 1) continue
        if (wanted > 0 && index(wanted "", position "") == 0) continue
        emit(symbol, "field")
      }
    }
    function emit_route(text,   piece, quotes) {
      quotes = "[\"" squote "]"
      if (match(text, "(^|[^A-Za-z0-9_])(get|post|put|patch|delete|match|route|path)[ \t]*(:|[(]|[ \t])[ \t]*" quotes "/[^\"" squote "]*" quotes)) {
        piece = substr(text, RSTART, RLENGTH)
        sub("^[^\"" squote "]*" quotes, "", piece)
        sub(quotes "$", "", piece)
        if (length(piece) > 1 && path != "") printf "%s\troute\t%s\n", piece, path
      }
    }
    function read_line(text, side,   name) {
      name = defined_name(text)
      if (name != "") emit(name, "definition")
      emit_dsl(text)
      emit_route(text)
      if (side == "-" && is_code && match(text, /^[ \t]+(readonly[ \t]+)?[A-Za-z_$][A-Za-z0-9_$]*[?]?:[ \t]/)) {
        name = substr(text, RSTART, RLENGTH)
        sub(/^[ \t]+(readonly[ \t]+)?/, "", name)
        sub(/[?]?:[ \t]$/, "", name)
        emit(name, "member")
      }
    }
    BEGIN { path = ""; reset_hunk() }
    old_left > 0 || new_left > 0 {
      marker = substr($0, 1, 1)
      if (marker == "+") {
        if (path != "") print path ":" new_line > added_out
        read_line(substr($0, 2), "+")
        new_line++; new_left--
      } else if (marker == "-") {
        read_line(substr($0, 2), "-")
        old_left--
      } else if (marker != "\\") {
        new_line++; new_left--; old_left--
      }
      next
    }
    /^diff --git / { path = ""; old_path = ""; next }
    /^--- / {
      old_path = substr($0, 5); sub(/\t.*$/, "", old_path); sub(/^a\//, "", old_path)
      next
    }
    /^\+\+\+ / {
      path = substr($0, 5); sub(/\t.*$/, "", path)
      if (path == "/dev/null") path = old_path
      else sub(/^b\//, "", path)
      is_code = path ~ /\.(js|jsx|ts|tsx|mjs|cjs|vue|svelte|rb|py|swift|go|java|kt|php|cs|rs|sh)$/
      next
    }
    /^@@ / {
      header = $0
      if (match(header, /^@@ -[0-9]+(,[0-9]+)? \+[0-9]+(,[0-9]+)? @@/)) {
        counts = substr(header, 4, RLENGTH - 6)
        split(counts, sides, " ")
        old_spec = substr(sides[1], 2); new_spec = substr(sides[2], 2)
        old_left = (old_spec ~ /,/) ? substr(old_spec, index(old_spec, ",") + 1) + 0 : 1
        split(new_spec, new_parts, ",")
        new_line = new_parts[1] + 0
        new_left = (new_spec ~ /,/) ? new_parts[2] + 0 : 1
        context = substr(header, RLENGTH + 1)
        sub(/^[ \t]+/, "", context)
        name = defined_name(context)
        if (name == "" && match(context, /^[ \t]*((async|static|public|private|protected|override)[ \t]+)*[A-Za-z_$][A-Za-z0-9_$]*[ \t]*\(/)) {
          name = substr(context, RSTART, RLENGTH)
          sub(/^[ \t]*((async|static|public|private|protected|override)[ \t]+)*/, "", name)
          sub(/[ \t]*\($/, "", name)
        }
        if (name != "") emit(name, "enclosing")
      }
      next
    }
  ' "$diff_copy" | awk -F '\t' '!seen[$1]++' > "$names_file"
fi

# Prints `<prefix><path>:<line>:<text>` for every line in <repo-dir> holding <name>: as a whole
# word, or as a plain string for a route.
grep_uses() {
  local repo_dir=$1 prefix=$2 name=$3 kind=$4
  local word_flag=-w
  if [ "$kind" = route ]; then word_flag=; fi
  # shellcheck disable=SC2086  # word_flag is one flag or nothing
  git -C "$repo_dir" grep -n -I -F $word_flag -e "$name" -- . 2>/dev/null | sed "s|^|$prefix|" || true
}

uses_file="$work_dir/uses.txt"
: > "$uses_file"
name_count=0
use_count=0
output="$work_dir/output.txt"
: > "$output"

while IFS="$(printf '\t')" read -r name kind source_path; do
  [ -n "$name" ] || continue
  name_count=$((name_count + 1))
  hits="$work_dir/hits.txt"
  {
    grep_uses . "" "$name" "$kind"
    for also_dir in ${also_dirs[@]+"${also_dirs[@]}"}; do
      grep_uses "$also_dir" "${also_dir%/}/" "$name" "$kind"
    done
  } | awk -v name="$name" -v added_list="$added_file" '
    BEGIN { while ((getline line < added_list) > 0) added[line] = 1 }
    {
      first = index($0, ":"); rest = substr($0, first + 1); second = index(rest, ":")
      where = substr($0, 1, first + second - 1)
      text = substr(rest, second + 1)
      if (where in added) next
      # The name being defined, not used.
      if (index(text, name) > 0) {
        probe = text
        gsub(/[][().*+?^$|{}\\]/, " ", probe)
        quoted = name
        gsub(/[][().*+?^$|{}\\]/, "", quoted)
        if (probe ~ ("(^|[^A-Za-z0-9_$.])(function[*]?|def|class|module|interface|type|enum|struct|trait|fn|func|const|let|var)[ \t]+(self[.])?" quoted "([^A-Za-z0-9_$]|$)")) next
      }
      print where ": " text
    }
  ' > "$hits"
  hit_count=$(wc -l < "$hits" | tr -d ' ')
  use_count=$((use_count + hit_count))
  printf 'name %s (%s, %s): %s uses\n' "$name" "$kind" "$source_path" "$hit_count" >> "$output"
  sed 's/^/  /' "$hits" >> "$output"
  cat "$hits" >> "$uses_file"
done < "$names_file"

# Tests that cover the uses: a use that is itself in a test file, and the test files named after a
# file holding a use (`cart.ts` -> `cart.test.ts`, `cart_spec.rb`, `test_cart.py`).
test_paths='(\.(test|spec)\.[A-Za-z0-9]+$|_(test|spec)\.[A-Za-z0-9]+$|(^|/)test_[^/]*\.py$|(^|/)(test|tests|spec|__tests__|e2e)/)'
tests_file="$work_dir/tests.txt"
{
  sed 's/:[0-9][0-9]*: .*$//' "$uses_file" | sort -u > "$work_dir/use-files.txt"
  grep -E "$test_paths" "$work_dir/use-files.txt" || true
  {
    git ls-files
    for also_dir in ${also_dirs[@]+"${also_dirs[@]}"}; do
      git -C "$also_dir" ls-files | sed "s|^|${also_dir%/}/|"
    done
  } | grep -E "$test_paths" > "$work_dir/all-tests.txt" || true
  { grep -vE "$test_paths" "$work_dir/use-files.txt" || true; } | while IFS= read -r use_path; do
    stem=$(basename "$use_path"); stem=${stem%%.*}
    awk -v stem="$stem" '{
      base = $0; sub(/^.*\//, "", base)
      if (index(base, stem ".test.") == 1 || index(base, stem ".spec.") == 1 || index(base, stem "_test.") == 1 || index(base, stem "_spec.") == 1 || base == "test_" stem ".py") print
    }' "$work_dir/all-tests.txt"
  done
} | sort -u > "$tests_file"
test_count=$(wc -l < "$tests_file" | tr -d ' ')

cat "$output"
echo "tests: $test_count"
sed 's/^/  /' "$tests_file"
echo "summary: $name_count names, $use_count uses, $test_count test files"
