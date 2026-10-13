#!/usr/bin/env bash
# PreToolUse guard for autopilot's own agents (agent_type "autopilot:*").
# Keeps them from editing run files or the autopilot config, merging,
# force-pushing, pushing to main/master, skipping or deleting tests, and
# (engineer only) touching risky paths or adding dependencies. Other agents
# and the main session (no agent_type) pass untouched.
#
# Input: PreToolUse JSON on stdin: tool_name, tool_input (Bash: command;
# Edit: file_path, new_string; Write: file_path, content; MultiEdit:
# file_path, edits[].new_string), agent_type, cwd. Subagent hook input
# carries agent_type "<plugin>:<agent>"; the hook's cwd is the launch repo,
# not the agent's worktree, so path decisions use tool_input paths.
# Hook schema and deny JSON: https://code.claude.com/docs/en/hooks
#
# Bash commands are read the way bash reads them where it matters:
# backslash-newline continuations are joined, and heredoc bodies are data,
# not commands. Per-segment checks use builtins only, so long commands stay
# fast (a hook that times out is non-blocking, i.e. it fails open).
#
# Output: the PreToolUse deny JSON on a block, nothing otherwise.
# Exit: always 0. Fails closed for autopilot:* agents when jq is missing,
# the input cannot be parsed, or the guard itself errors.
#
# Only `set -u`: a failing command must never abort the guard and let the
# tool call through (a hook that errors is non-blocking). `set -f`: words
# split out of commands must never glob-expand.
set -u
set -f

# Builtins only up to the agent check, so even a broken PATH fails closed.
input=""
IFS= read -r -d '' input || true

readonly AUTOPILOT_AGENT='"agent_type"[[:space:]]*:[[:space:]]*"autopilot:'
looks_like_autopilot() { [[ $input =~ $AUTOPILOT_AGENT ]]; }

decided=0
deny() {
  decided=1
  if command -v jq >/dev/null 2>&1; then
    jq -cn --arg reason "autopilot: $1" \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}'
  else
    # Only fixed reasons reach this branch; strip anything JSON-unsafe anyway.
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"autopilot: %s"}}\n' \
      "${1//[\"\\]/}"
  fi
  exit 0
}

# An unexpected error (e.g. an unbound variable under set -u) denies instead
# of exiting non-zero, which Claude Code would treat as "allow".
# shellcheck disable=SC2329 # invoked by the EXIT trap
on_exit() {
  local status=$?
  if [ "$status" != 0 ] && [ "$decided" = 0 ] && looks_like_autopilot; then
    deny "guard error; refusing the tool call"
  fi
  exit 0
}
trap on_exit EXIT

if ! command -v jq >/dev/null 2>&1; then
  if looks_like_autopilot; then deny "jq is required for autopilot guard"; fi
  exit 0
fi

if ! agent=$(printf '%s' "$input" | jq -r '.agent_type // empty' 2>/dev/null); then
  if looks_like_autopilot; then deny "unreadable hook input"; fi
  exit 0
fi
case "$agent" in autopilot:*) ;; *) exit 0 ;; esac

field() { printf '%s' "$input" | jq -r "$1 // empty" 2>/dev/null; }
tool=$(field .tool_name)
hook_cwd=$(field .cwd)

# macOS file systems are case-insensitive: DB/Migrate is db/migrate and
# Picker.Test.tsx is a test. Applies to every [[ ]] and case below.
shopt -s nocasematch

readonly NL=$'\n' TAB=$'\t' SQ="'"

# Joins its arguments into one ERE alternation.
alternatives() { local IFS='|'; printf '%s' "$*"; }

test_path_parts=(
  '(^|/)(test|tests|spec|__tests__|e2e|cypress)/'  # a test directory
  '[._-](test|spec|cy)\.[[:alnum:]]+$'             # a.test.tsx a.spec.ts a_spec.rb a_test.go a.cy.ts
  '(^|/)test_[^/]+\.py$'                           # pytest test_reply.py
  '(^|/)tests\.py$'                                # Django tests.py
)
TEST_PATH=$(alternatives "${test_path_parts[@]}")
# A delete target: a test file, or a whole test directory.
TEST_TARGET=$(alternatives "$TEST_PATH" '(^|/)(test|tests|spec|__tests__|e2e|cypress)/?$')

# Skip markers in any test file. Each needs a call or decorator form, so
# test code that merely uses a "skip" property or variable passes.
skip_marker_parts=(
  '\.(skip|only|fixme)(\.each)?[[:space:]]*[(`]'          # it.skip( describe.only( test.fixme( it.skip.each(
  '\.skipIf[[:space:]]*\('                                 # vitest it.skipIf(
  '(^|[^[:alnum:]_.$])x(it|describe|test|context|specify)[[:space:]]*\('  # xit( xdescribe(
  '(^|[^[:alnum:]_.$])x(it|describe|context|specify)[[:space:]]+["'"'"']'  # RSpec xit 'works' do
  '@pytest\.mark\.(skip|skipif|xfail)'                     # pytest decorators
  'pytest\.(skip|xfail)[[:space:]]*\('                     # pytest.skip("...") inside a test
  'unittest\.(skip|expectedFailure)'                       # unittest decorators
  '\.Skip(Now|f)?\('                                       # Go t.Skip()
)
SKIP_MARKER=$(alternatives "${skip_marker_parts[@]}")
# RSpec-only forms; in other languages these are ordinary code.
ruby_skip_parts=(
  '^[[:space:]]*(skip|pending)([[:space:]]|\(|$)'          # a bare skip 'flaky' / pending line
  '[,(][[:space:]]*:?(skip|pending)[[:space:]]*(:|=>)'     # it 'x', skip: true
  '[,(][[:space:]]*:(skip|pending)([[:space:]]|,|\)|$)'    # it 'x', :skip
)
RUBY_SKIP_MARKER=$(alternatives "${ruby_skip_parts[@]}")

readonly LOCKFILE='(^|/)(package-lock\.json|npm-shrinkwrap\.json|yarn\.lock|pnpm-lock\.yaml|bun\.lockb?|Gemfile|Gemfile\.lock|poetry\.lock|uv\.lock|Pipfile|Pipfile\.lock|requirements[^/]*\.txt|Cargo\.lock|go\.mod|go\.sum|composer\.lock)$'
readonly WRITE_VERB='>|(^|[^[:alnum:]_.-])(tee|cp|mv|rm|ln|install|truncate|touch|dd|rsync|unlink|shred|python[0-9.]*|node|ruby|perl)([[:space:]]|$)|(^|[[:space:]])sed[[:space:]].*-i'

delete_parts=(
  '(^|[^[:alnum:]_.-])(rm|unlink|shred)([[:space:]]|$)'    # rm, git rm, find -exec rm
  '(^|[^[:alnum:]_-])git[[:space:]].*clean([[:space:]]|$)'  # git clean -f <path>
  '(^|[[:space:]])-delete([[:space:]]|$)'                  # find ... -delete
)
DELETE_VERB=$(alternatives "${delete_parts[@]}")

merge_parts=(
  # pr merge, with any flags (and their values) between: gh pr -R a/b merge
  '(^|[^[:alnum:]_-])pr([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+merge([[:space:]]|$)'
  'pulls/[^[:space:]]*/merge'                              # REST merge endpoint
  'mergePullRequest|enablePullRequestAutoMerge'            # GraphQL merge and auto-merge
)
MERGE=$(alternatives "${merge_parts[@]}")

readonly PUSH_WORD='(^|[^[:alnum:]_-])push([[:space:]]|$)'
bad_push_parts=(
  '(^|[[:space:]])--for[[:alnum:]-]*([[:space:]=]|$)'      # --force, --force-with-lease, abbreviations (--forc)
  '(^|[[:space:]])--mirror([[:space:]]|$)'                 # --mirror force-updates every ref
  '(^|[[:space:]])-[[:alpha:]]*f[[:alpha:]]*([[:space:]]|$)'  # -f and clusters like -fu
  '[[:space:]]\+[^[:space:]]'                              # +refspec forces that ref
  '(^|[[:space:]:/+])(main|master)([[:space:]]|$)'         # main/master as a refspec or destination
)
BAD_PUSH=$(alternatives "${bad_push_parts[@]}")

readonly ADD_DEPENDENCY='(^|[^[:alnum:]_-])((npm|pnpm|yarn|bun)[[:space:]]+(add|install|i)([[:space:]]+-[^[:space:]]*)*[[:space:]]+[^-[:space:]]|bundle[[:space:]]+add|gem[[:space:]]+install|pip[0-9.]*[[:space:]]+install|uv[[:space:]]+add|poetry[[:space:]]+add|cargo[[:space:]]+add|go[[:space:]]+get)'
readonly CD_DIR='^[[:space:]]*(builtin[[:space:]]+)?(cd|pushd)[[:space:]]+([^-[:space:]][^[:space:]]*)'
readonly HEREDOC_TAG='^[A-Za-z0-9_.-]+$'

# Sets $resolved to $1 made absolute against directory $2, with //, /./ and
# /../ collapsed so a .. cannot step out of an allowed directory.
resolve() {
  local path=$1 out="" seg
  case "$path" in /*) ;; *) path="$2/$path" ;; esac
  local IFS=/
  for seg in $path; do
    case "$seg" in
      ''|.) ;;
      ..) out=${out%/*} ;;
      *) out="$out/$seg" ;;
    esac
  done
  resolved=${out:-/}
}

# Run-root files and anything under .autopilot/ outside a unit directory.
# .autopilot/runs/<id>/<unit>/** is the unit's scratch and stays writable.
is_run_file() {
  case "$1" in
    */.autopilot/runs/*/*/*) return 1 ;;
    */.autopilot|*/.autopilot/*) return 0 ;;
  esac
  return 1
}

is_config_file() {
  case "$1" in */.claude/autopilot.json) return 0 ;; esac
  return 1
}

# Sets $rel (path relative to its repo or worktree) and $repo_top. Uses git's
# prefix rather than stripping the top level as a string, which breaks when
# the top resolves through a symlink (/var -> /private/var). One git call per
# directory; results are cached in $repo_cache as "dir TAB ok TAB prefix TAB top".
repo_cache=$NL
repo_info() {
  local path=$1 dir entry out
  dir=${path%/*}
  [ -n "$dir" ] || dir=/
  while [ ! -d "$dir" ] && [ "$dir" != / ]; do
    dir=${dir%/*}
    [ -n "$dir" ] || dir=/
  done
  entry=${repo_cache#*"$NL$dir$TAB"}
  if [ "$entry" != "$repo_cache" ]; then
    entry=${entry%%"$NL"*}
  else
    if out=$(git -C "$dir" rev-parse --show-prefix --show-toplevel 2>/dev/null); then
      entry="1$TAB${out%%"$NL"*}$TAB${out#*"$NL"}"
    else
      entry=0
    fi
    repo_cache="$repo_cache$dir$TAB$entry$NL"
  fi
  [ "${entry%%"$TAB"*}" = 1 ] || return 1
  entry=${entry#*"$TAB"}
  repo_top=${entry#*"$TAB"}
  if [ "$dir" = / ]; then
    rel="${entry%%"$TAB"*}${path#/}"
  else
    rel="${entry%%"$TAB"*}${path#"$dir"/}"
  fi
}

# Engineer only: deny a write to a risky_paths glob from the worktree's
# .claude/autopilot.json (falling back to the launch repo's). The globs are
# read once per repo top.
config_top=$NL
config_patterns=""
check_risky() {
  local rel repo_top config pattern
  repo_info "$1" || return 0
  if [ "$repo_top" != "$config_top" ]; then
    config_top=$repo_top
    config="$repo_top/.claude/autopilot.json"
    [ -f "$config" ] || config="$hook_cwd/.claude/autopilot.json"
    config_patterns=""
    if [ -f "$config" ]; then
      config_patterns=$(jq -r '.risky_paths // [] | .[] | strings' "$config" 2>/dev/null)
    fi
  fi
  local IFS=$NL
  for pattern in $config_patterns; do
    [ -n "$pattern" ] || continue
    # In [[ == ]], * also matches /, so db/migrate/** and **/payments/** work.
    # "$rel/" catches a directory target: cp x db/migrate.
    # shellcheck disable=SC2053
    if [[ $rel == $pattern || $rel == ${pattern#\*\*/} || $rel/ == $pattern || $rel/ == ${pattern#\*\*/} ]]; then
      deny "risky path $rel: stop and return status risky"
    fi
  done
}

# Rules for any write to $1, an absolute normalized path. $2 is 1 when the
# risky-path check applies (file tools, and path-like words in Bash).
check_path_write() {
  if is_run_file "$1"; then deny "run files are written by the staff engineer only"; fi
  if is_config_file "$1"; then deny "the autopilot config is written by the user only"; fi
  [ "$agent" = autopilot:engineer ] || return 0
  if [[ $1 =~ $LOCKFILE ]]; then deny "new dependency: stop and return status risky"; fi
  [ "$2" = 1 ] || return 0
  check_risky "$1"
}

check_file_write() {
  local path text markers
  path=$(field .tool_input.file_path)
  [ -n "$path" ] || return 0
  resolve "$path" "${hook_cwd:-/}"
  path=$resolved
  if [[ $path =~ $TEST_PATH ]]; then
    text=$(printf '%s' "$input" | jq -r '[.tool_input.new_string, .tool_input.content, (.tool_input.edits // [] | .[]? | .new_string?)] | map(select(type == "string")) | join("\n")' 2>/dev/null)
    markers=$SKIP_MARKER
    case "$path" in *.rb) markers="$markers|$RUBY_SKIP_MARKER" ;; esac
    if printf '%s' "$text" | grep -Eq "$markers"; then
      deny "tests are never skipped to make them pass"
    fi
  fi
  check_path_write "$path" 1
}

# True when $1 ends in an odd number of backslashes (a line continuation).
continues() {
  local line=$1 count=0
  while [ "${line%\\}" != "$line" ]; do
    line=${line%\\}
    count=$((count + 1))
  done
  [ $((count % 2)) = 1 ]
}

# Sets $heredocs to the heredocs opened on logical line $1, in order, as
# "quoted:dash:TAG" words; empty when there are none. A heredoc operator
# inside quotes, a comment, $(( )) or after a backslash is not one. When a
# delimiter is anything but a plain word, $heredocs is emptied so the lines
# after it are checked as commands (the safe direction).
scan_heredocs() {
  local line=$1 len=${#1} k=0 char prev=' ' single=0 double=0 arith=0 word quoted dash
  heredocs=""
  case "$line" in *'<<'*) ;; *) return ;; esac
  while [ "$k" -lt "$len" ]; do
    char=${line:k:1}
    if [ "$single" = 1 ]; then
      [ "$char" = "$SQ" ] && single=0
      k=$((k + 1)); continue
    fi
    if [ "$char" = "\\" ]; then
      k=$((k + 2)); prev=x; continue
    fi
    if [ "$double" = 1 ]; then
      [ "$char" = '"' ] && double=0
      k=$((k + 1)); continue
    fi
    case "$char" in
      "$SQ") single=1 ;;
      '"') double=1 ;;
      '#')
        case "$prev" in ' '|"$TAB"|';'|'&'|'|'|'(') return ;; esac ;;
      '(')
        if [ "${line:k:2}" = '((' ]; then arith=$((arith + 1)); k=$((k + 2)); prev='('; continue; fi ;;
      ')')
        if [ "${line:k:2}" = '))' ] && [ "$arith" -gt 0 ]; then arith=$((arith - 1)); k=$((k + 2)); prev=')'; continue; fi ;;
      '<')
        if [ "${line:k:3}" = '<<<' ]; then k=$((k + 3)); prev='<'; continue; fi
        if [ "${line:k:2}" = '<<' ] && [ "$arith" = 0 ]; then
          k=$((k + 2)); dash=0
          if [ "${line:k:1}" = - ]; then dash=1; k=$((k + 1)); fi
          while [ "$k" -lt "$len" ] && { [ "${line:k:1}" = ' ' ] || [ "${line:k:1}" = "$TAB" ]; }; do k=$((k + 1)); done
          word=""
          while [ "$k" -lt "$len" ]; do
            char=${line:k:1}
            case "$char" in ' '|"$TAB"|';'|'|'|'&'|'<'|'>'|'('|')') break ;; esac
            word="$word$char"; k=$((k + 1))
          done
          quoted=0
          case "$word" in *[\"\'\\]*) quoted=1 ;; esac
          word=${word//[\"$SQ\\]/}
          if ! [[ $word =~ $HEREDOC_TAG ]]; then heredocs=""; return; fi
          heredocs="$heredocs $quoted:$dash:$word"
          prev=x; continue
        fi ;;
    esac
    prev=$char
    k=$((k + 1))
  done
}

# Sets $command_text to $1 as bash would read its commands: continuations
# joined, and each heredoc body dropped once its delimiter line is found. A
# heredoc whose delimiter never appears keeps its lines (checked as commands).
read_commands() {
  local lines=() count=0 line i=0 j logical body found all_found entry quoted dash tag
  while IFS= read -r line || [ -n "$line" ]; do
    lines[count]=$line
    count=$((count + 1))
  done <<EOF
$1
EOF
  command_text=""
  while [ "$i" -lt "$count" ]; do
    logical=${lines[i]}
    i=$((i + 1))
    while continues "$logical" && [ "$i" -lt "$count" ]; do
      logical="${logical%\\}${lines[i]}"
      i=$((i + 1))
    done
    command_text="$command_text$logical$NL"
    scan_heredocs "$logical"
    [ -n "$heredocs" ] || continue
    j=$i
    all_found=1
    for entry in $heredocs; do
      quoted=${entry%%:*}; entry=${entry#*:}
      dash=${entry%%:*}; tag=${entry#*:}
      found=0
      while [ "$j" -lt "$count" ]; do
        body=${lines[j]}
        j=$((j + 1))
        # An unquoted delimiter means bash also joins continuations in the body.
        if [ "$quoted" = 0 ]; then
          while continues "$body" && [ "$j" -lt "$count" ]; do
            body="${body%\\}${lines[j]}"
            j=$((j + 1))
          done
        fi
        if [ "$dash" = 1 ]; then body=${body#"${body%%[!"$TAB"]*}"}; fi
        if [ "$body" = "$tag" ]; then found=1; break; fi
      done
      if [ "$found" = 0 ]; then all_found=0; break; fi
    done
    if [ "$all_found" = 1 ]; then i=$j; fi
  done
}

# One shell segment per line; literal newlines in the replacement work in
# both GNU and BSD sed (same as code-review/scripts/guard-github-post.sh).
split_segments() {
  printf '%s\n' "$1" | sed -e 's/&&/\
/g' -e 's/||/\
/g' -e 's/;/\
/g' -e 's/|/\
/g'
}

check_bash() {
  local cmd segment norm base word target next_is_target path_like
  cmd=$(field .tool_input.command)
  [ -n "$cmd" ] || return 0
  read_commands "$cmd"
  # >| is a redirect (noclobber override), not a pipe.
  command_text=${command_text//'>|'/'>'}
  base=${hook_cwd:-/}
  while IFS= read -r segment; do
    # Strip quotes, backslashes and backticks so "gh" pr merge reads as written.
    norm=${segment//[\"$SQ\\\`]/}

    if [[ $norm =~ $MERGE ]]; then deny "agents never merge; the user merges"; fi

    if [[ $norm =~ $PUSH_WORD ]] && [[ $norm =~ $BAD_PUSH ]]; then
      deny "no force-push and no pushes to main/master"
    fi

    if [[ $norm =~ $DELETE_VERB ]]; then
      for word in $norm; do
        if [[ $word =~ $TEST_TARGET ]]; then deny "tests are never deleted to make them pass"; fi
      done
    fi

    if [ "$agent" = autopilot:engineer ] && [[ $norm =~ $ADD_DEPENDENCY ]]; then
      deny "new dependency: stop and return status risky"
    fi

    # Track `cd DIR` so relative paths after it resolve where they will land.
    if [[ $norm =~ $CD_DIR ]]; then
      resolve "${BASH_REMATCH[3]}" "$base"
      base=$resolved
    fi

    [[ $norm =~ $WRITE_VERB ]] || continue
    next_is_target=0
    for word in $norm; do
      path_like=$next_is_target
      next_is_target=0
      case "$word" in
        [0-9\&]'>'|[0-9\&]'>>'|'>'|'>>') next_is_target=1; continue ;;
        [0-9\&]'>'*|'>'*) path_like=1 ;;
      esac
      # Leading redirection operators (>, 2>, &>, <) off; dd of=PATH to PATH.
      while [[ $word == [0-9\&\<\>]*[\<\>]* || $word == [\<\>]* ]]; do word=${word#?}; done
      word=${word#*=}
      case "$word" in ''|-*) continue ;; */*|*.*) path_like=1 ;; esac
      resolve "$word" "$base"
      target=$resolved
      check_path_write "$target" "$path_like"
    done
  done < <(split_segments "$command_text")
}

case "$tool" in
  Edit|Write|MultiEdit) check_file_write ;;
  Bash) check_bash ;;
esac
exit 0
