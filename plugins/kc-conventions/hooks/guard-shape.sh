#!/usr/bin/env bash
# PreToolUse guard (kc-shape-the-change): denies a write to a non-test source file on a branch whose
# shape file ($(git rev-parse --git-path kc-shape)/<branch>.md) is missing or fails check-shape.sh.
# Reads the Edit, Write and MultiEdit tools, and best effort the text of a Bash command or REPL
# script (redirects, tee, sed -i, cp, mv, install, rsync, write( and edit( calls), never what a
# script it starts writes. Never denies the default branch, a detached head, a path outside a
# checkout, a test file or a non-source file. Without jq it allows. Prints the deny JSON or nothing.
set -u

hook_dir=$(cd "$(dirname "$0")" && pwd)
checker="$hook_dir/../skills/kc-shape-the-change/scripts/check-shape.sh"

readonly SOURCE_EXTENSIONS='(ts|tsx|js|jsx|mjs|cjs|rb|py|swift|go|java|kt|php|cs|rs)'
readonly TEST_PATH_PATTERN='(^|/)(tests?|specs?|__tests__|__mocks__|e2e|fixtures|testdata)/|\.(test|spec)\.[a-z]+$|_(test|spec)\.[a-z]+$|(^|/)test_[^/]*\.py$|(Test|Tests|Spec)\.(java|kt|swift|cs)$'
readonly DEFAULT_BRANCHES='^(main|master|develop|trunk)$'
# Options of sed and perl that may come before an in-place flag (-i, -pi, -ni).
readonly BEFORE_IN_PLACE_FLAG='[nEeprlsaWu0]*'
# A quoted span holding a space, redirect, separator or pipe: text, not a path.
readonly QUOTED_TEXT_PATTERN='s/"[^"]*[[:space:]<>;|&][^"]*"/__quoted__/g; s/'"'"'[^'"'"']*[[:space:]<>;|&][^'"'"']*'"'"'/__quoted__/g'

# Prints the value of a jq path in the hook payload, empty when absent.
get_field() {
  printf '%s' "$1" | jq -r "$2 // empty" 2>/dev/null
}

# Succeeds when the token is a redirect operator that takes its target from the next token.
is_redirect_operator() {
  case $1 in '>' | '>>' | [0-9]'>' | [0-9]'>>' | '&>') ;; *) return 1 ;; esac
}

# Prints the destination of a cp, mv, install or rsync: the last argument that is not a redirect,
# reading the segment's arguments (passed here) up to the next ';'.
get_last_argument() {
  local argument previous_is_redirect=false destination=''
  for argument in "$@"; do
    [ "$argument" = ';' ] && break
    if [ "$previous_is_redirect" = true ]; then previous_is_redirect=false; continue; fi
    if is_redirect_operator "$argument"; then previous_is_redirect=true; continue; fi
    case "$argument" in
      '>'* | [0-9]'>'* | '&>'*) ;;
      *) destination=$argument ;;
    esac
  done
  printf '%s\n' "${destination//[\'\"]/}"
}

# Prints the write targets a shell command names, one per line (source and test paths alike).
get_shell_write_targets() {
  local shell_command=$1 raw_token token redirect_target pending_redirect=false command_name='' in_place=false index
  local command_tokens=()
  shell_command=$(printf '%s' "$shell_command" | sed -E "$QUOTED_TEXT_PATTERN")
  shell_command=${shell_command//$'\n'/ ; }
  shell_command=${shell_command//&&/ ; }
  shell_command=${shell_command//|/ ; }
  shell_command=${shell_command//;/ ; }
  read -ra command_tokens <<< "$shell_command"
  for ((index = 0; index < ${#command_tokens[@]}; index++)); do
    raw_token=${command_tokens[$index]}
    token=${raw_token//[\'\"]/}
    if [ "$token" = ';' ]; then command_name=''; in_place=false; pending_redirect=false; continue; fi
    if [ -z "$command_name" ]; then
      case "$token" in
        [A-Za-z_]*=* | sudo | env | time | command | exec | nohup | do | then | else | '{' | '(') continue ;;
      esac
      command_name=${token##*/}
      continue
    fi
    if [ "$pending_redirect" = true ]; then printf '%s\n' "$token"; pending_redirect=false; continue; fi
    if is_redirect_operator "$raw_token"; then pending_redirect=true; continue; fi
    case "$raw_token" in
      '>'?*) redirect_target=${token#>}; printf '%s\n' "${redirect_target#>}"; continue ;;
    esac
    case "$command_name" in
      tee) case "$token" in -*) ;; *) printf '%s\n' "$token" ;; esac ;;
      sed | perl)
        if [[ "$token" =~ ^-${BEFORE_IN_PLACE_FLAG}i ]] || [[ "$token" == --in-place* ]]; then in_place=true; fi
        if [ "$in_place" = true ]; then printf '%s\n' "$token"; fi ;;
      cp | mv | install | rsync)
        # Later arguments of this command must not match again: the destination is the last one.
        get_last_argument "${command_tokens[@]:$index}"
        command_name=handled ;;
    esac
  done
}

# Prints the quoted source paths a REPL script names when it writes with write(, edit( or a fs write.
get_repl_write_targets() {
  local code=$1 quote_chars backtick
  backtick=$(printf '\140') # a literal backtick would end this file's own quoting
  quote_chars="\"'$backtick"
  printf '%s' "$code" | grep -Eq '(^|[^A-Za-z0-9_.])(write|edit)\(|writeFile|appendFile' || return 0
  printf '%s' "$code" | grep -oE "[${quote_chars}][^${quote_chars}[:space:]]+\.${SOURCE_EXTENSIONS}[${quote_chars}]" | tr -d "${quote_chars}"
}

escape_json() {
  local text=$1
  text=${text//\\/\\\\}
  text=${text//\"/\\\"}
  text=${text//$'\t'/ }
  printf '%s' "$text" | awk 'BEGIN { ORS = "" } { if (NR > 1) print "\\n"; print }'
}

# Prints the nearest existing folder of a path, to run git from.
get_existing_folder() {
  local folder
  folder=$(dirname "$1")
  while [ ! -d "$folder" ] && [ "$folder" != / ] && [ "$folder" != . ]; do folder=$(dirname "$folder"); done
  printf '%s\n' "$folder"
}

# Prints the shape file the branch of the path's checkout needs; prints nothing when none is
# needed: no checkout, a detached head, or the default branch.
get_required_shape_file() {
  local folder branch default_ref
  folder=$(get_existing_folder "$1")
  [ -d "$folder" ] || return 0
  git -C "$folder" rev-parse --show-toplevel >/dev/null 2>&1 || return 0
  branch=$(git -C "$folder" symbolic-ref --quiet --short HEAD 2>/dev/null) || return 0
  [[ "$branch" =~ $DEFAULT_BRANCHES ]] && return 0
  default_ref=$(git -C "$folder" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)
  [ "$branch" = "${default_ref#origin/}" ] && return 0
  (cd "$folder" && git rev-parse --path-format=absolute --git-path "kc-shape/$branch.md" 2>/dev/null)
}

# Reads the payload, collects the files it writes and prints the deny JSON for the first source,
# non-test path whose branch has no valid shape file.
handle_shape_hook() {
  local hook_input tool_name dir shell_command target path shape_file problems escaped_path escaped_shape_file escaped_problems targets=''
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
      shell_command=$(get_field "$hook_input" '.tool_input.command')
      if [[ "$shell_command" =~ ^[[:space:]]*cd[[:space:]]+([^[:space:]\;\&]+)[[:space:]]*\&\& ]]; then
        dir=${BASH_REMATCH[1]}
        dir=${dir//[\'\"]/}
        case "$dir" in
          '~' | "\$HOME" | "\${HOME}") dir=$HOME ;;
          \~/* | \$HOME/* | \$\{HOME\}/*) dir=$HOME/${dir#*/} ;;
        esac
      fi
      targets=$(get_shell_write_targets "$shell_command")
      ;;
    REPL) targets=$(get_repl_write_targets "$(get_field "$hook_input" '.tool_input.code')") ;;
    *) exit 0 ;;
  esac
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    [[ "$path" =~ \.${SOURCE_EXTENSIONS}$ ]] || continue
    printf '%s' "$path" | grep -Eq "$TEST_PATH_PATTERN" && continue
    case "$path" in /*) ;; \~/*) path=$HOME/${path#\~/} ;; *) path=$dir/$path ;; esac
    shape_file=$(get_required_shape_file "$path")
    [ -n "$shape_file" ] || continue
    if [ -f "$shape_file" ]; then
      problems=$(bash "$checker" "$shape_file" 2>&1) && continue
    else
      problems="no shape file at $shape_file"
    fi
    escaped_path=$(escape_json "$path")
    escaped_shape_file=$(escape_json "$shape_file")
    escaped_problems=$(escape_json "$problems")
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked by the kc-conventions plugin: this writes source code (%s) on a branch whose shape is not written down. Write the shape file (%s) with kc-conventions:kc-shape-the-change: where each fact lives, two shapes compared, rollout, failure modes and the persons approval words; or, for a change with no new storage, no new unit and no behaviour move, make its first line one that starts with trivial: and says so. Test files are never blocked. Problems:\\n%s"}}\n' \
      "$escaped_path" "$escaped_shape_file" "$escaped_problems"
    exit 0
  done <<< "$targets"
  exit 0
}

handle_shape_hook
