#!/usr/bin/env bash
# PreToolUse guard for writing source code (kc-shape-the-change). An edit or write to a non-test
# source file is denied while the checkout's current branch has no shape file that passes
# check-shape.sh, with the problems in the reason. The shape file is
# $(git rev-parse --git-path kc-shape)/<branch>.md; a change with no new storage, no new unit and
# no behaviour move declares itself in the file's first line ("trivial: no new storage, no new
# unit, no behaviour move: <why>").
#
# Writes it reads: the Edit, Write and MultiEdit tools (file_path); Bash redirects (> and >>), tee,
# sed -i and perl -i, cp, mv, install and rsync (the last argument); a REPL call to write( or edit(
# or a fs write naming a source path in quotes. Shell and REPL reading is best effort: it reads
# the command text, not what a script it starts writes.
# Never denied: the default branch (main, master, develop, trunk, or origin/HEAD's), a detached
# head, a path outside any git checkout, test files (a tests, spec, e2e, fixtures or mocks folder,
# or a name like x.test.ts, x_spec.rb, test_x.py, XTests.swift) and anything that is not source
# code (the extensions below). Without jq it reads nothing and lets every call through. Output:
# the deny JSON or nothing; always exits 0.
set -u

hook_dir=$(cd "$(dirname "$0")" && pwd)
checker="$hook_dir/../skills/kc-shape-the-change/scripts/check-shape.sh"

readonly SOURCE_EXTENSIONS='(ts|tsx|js|jsx|mjs|cjs|rb|py|swift|go|java|kt|php|cs|rs)'
readonly TEST_PATH_PATTERN='(^|/)(tests?|specs?|__tests__|__mocks__|e2e|fixtures|testdata)/|\.(test|spec)\.[a-z]+$|_(test|spec)\.[a-z]+$|(^|/)test_[^/]*\.py$|(Test|Tests|Spec)\.(java|kt|swift|cs)$'
readonly DEFAULT_BRANCHES='^(main|master|develop|trunk)$'

get_field() {
  printf '%s' "$1" | jq -r "$2 // empty" 2>/dev/null
}

is_source_path() {
  [[ "$1" =~ \.${SOURCE_EXTENSIONS}$ ]]
}

is_test_path() {
  printf '%s' "$1" | grep -Eq "$TEST_PATH_PATTERN"
}

# Prints the destination of a cp, mv, install or rsync segment starting at token index $1.
get_last_argument() {
  local end=$1
  while [ "$end" -lt "$token_count" ] && [ "${tokens[$end]}" != ';' ]; do end=$((end + 1)); done
  printf '%s\n' "${tokens[$((end - 1))]//[\'\"]/}"
}

# Prints the write targets a shell command names, one per line (source and test paths alike).
get_shell_write_targets() {
  local command=$1 token prev='' word cmd_name='' in_place=0 index
  command=${command//$'\n'/ ; }
  command=${command//&&/ ; }
  command=${command//|/ ; }
  read -ra tokens <<< "$command"
  token_count=${#tokens[@]}
  for ((index = 0; index < token_count; index++)); do
    token=${tokens[$index]//[\'\"]/}
    if [ "$token" = ';' ]; then cmd_name=''; in_place=0; prev=''; continue; fi
    if [ -z "$cmd_name" ]; then
      case "$token" in
        [A-Za-z_]*=* | sudo | env | time | command | exec | nohup | do | then | else | '{' | '(') continue ;;
      esac
      cmd_name=${token##*/}
      continue
    fi
    case "$token" in
      '>' | '>>' | [0-9]'>' | [0-9]'>>' | '&>') prev=redirect; continue ;;
      '>'?*) word=${token#>}; word=${word#>}; printf '%s\n' "$word"; continue ;;
    esac
    if [ "$prev" = redirect ]; then printf '%s\n' "$token"; prev=''; continue; fi
    case "$cmd_name" in
      tee) case "$token" in -*) ;; *) printf '%s\n' "$token" ;; esac ;;
      sed | perl)
        if [[ "$token" =~ ^-[A-Za-z]*i ]] || [[ "$token" == --in-place* ]]; then in_place=1; fi
        if [ "$in_place" = 1 ]; then printf '%s\n' "$token"; fi ;;
      cp | mv | install | rsync) get_last_argument "$index"; cmd_name=copied ;;
    esac
  done
}

# Prints the quoted source paths a REPL script names when it writes with write(, edit( or a fs write.
get_repl_write_targets() {
  local code=$1 quote_chars
  printf '%s' "$code" | grep -Eq '(^|[^A-Za-z0-9_.])(write|edit)\(|writeFile|appendFile' || return 0
  quote_chars="\"'$(printf '\140')"
  printf '%s' "$code" | grep -oE "[${quote_chars}][^${quote_chars}[:space:]]+\.${SOURCE_EXTENSIONS}[${quote_chars}]" | tr -d "${quote_chars}"
}

escape_json() {
  local text=$1
  text=${text//\\/\\\\}
  text=${text//\"/\\\"}
  text=${text//$'\t'/ }
  printf '%s' "$text" | awk 'BEGIN { ORS = "" } { if (NR > 1) print "\\n"; print }'
}

# Returns 0 when the path needs a shape file and has no valid one, setting shape_problems and
# shape_file; returns 1 when the write is allowed.
needs_shape_file() {
  local path=$1 base_dir branch default_ref
  base_dir=$(dirname "$path")
  while [ ! -d "$base_dir" ] && [ "$base_dir" != / ] && [ "$base_dir" != . ]; do base_dir=$(dirname "$base_dir"); done
  [ -d "$base_dir" ] || return 1
  git -C "$base_dir" rev-parse --show-toplevel >/dev/null 2>&1 || return 1
  branch=$(git -C "$base_dir" symbolic-ref --quiet --short HEAD 2>/dev/null) || return 1
  [[ "$branch" =~ $DEFAULT_BRANCHES ]] && return 1
  default_ref=$(git -C "$base_dir" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)
  [ "$branch" = "${default_ref#origin/}" ] && return 1
  shape_file=$(cd "$base_dir" && git rev-parse --path-format=absolute --git-path "kc-shape/$branch.md" 2>/dev/null) || return 1
  if [ ! -f "$shape_file" ]; then
    shape_problems="no shape file for branch $branch"
    return 0
  fi
  shape_problems=$(bash "$checker" "$shape_file" 2>&1) && return 1
  return 0
}

handle_shape_hook() {
  local hook_input tool_name dir command target path targets=''
  command -v jq >/dev/null 2>&1 || exit 0
  hook_input=$(cat)
  tool_name=$(get_field "$hook_input" '.tool_name')
  dir=$(get_field "$hook_input" '.cwd')
  [ -n "$dir" ] || dir=$PWD
  case "$tool_name" in
    Edit | Write | MultiEdit)
      target=$(get_field "$hook_input" '.tool_input.file_path')
      [ -n "$target" ] && targets=$target
      ;;
    Bash)
      command=$(get_field "$hook_input" '.tool_input.command')
      if [[ "$command" =~ ^[[:space:]]*cd[[:space:]]+([^[:space:]\;\&]+)[[:space:]]*\&\& ]]; then
        dir=${BASH_REMATCH[1]}
        dir=${dir//[\'\"]/}
      fi
      targets=$(get_shell_write_targets "$command")
      ;;
    REPL) targets=$(get_repl_write_targets "$(get_field "$hook_input" '.tool_input.code')") ;;
    *) exit 0 ;;
  esac
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    is_source_path "$path" || continue
    is_test_path "$path" && continue
    case "$path" in /*) ;; \~/*) path=$HOME/${path#\~/} ;; *) path=$dir/$path ;; esac
    needs_shape_file "$path" || continue
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked by the kc-conventions plugin: this writes source code (%s) on a branch whose shape is not written down. Write the shape file (%s) with kc-conventions:kc-shape-the-change: where each fact lives, two shapes compared, rollout, failure modes and the persons approval words; or, for a change with no new storage, no new unit and no behaviour move, make its first line one that starts with trivial: and says so. Test files are never blocked. Problems:\\n%s"}}\n' \
      "$(escape_json "$path")" "$(escape_json "$shape_file")" "$(escape_json "$shape_problems")"
    exit 0
  done <<< "$targets"
  exit 0
}

shape_problems=''
shape_file=''
token_count=0
tokens=()
handle_shape_hook
