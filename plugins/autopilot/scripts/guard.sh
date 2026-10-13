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
# Output: the PreToolUse deny JSON on a block, nothing otherwise.
# Exit: always 0. Fails closed for autopilot:* agents when jq is missing,
# the input cannot be parsed, or the guard itself errors.
#
# Only `set -u`: a failing command must never abort the guard and let the
# tool call through (a hook that errors is non-blocking).
set -u

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

# macOS file systems are case-insensitive: DB/Migrate is db/migrate.
shopt -s nocasematch

readonly TEST_PATH='(^|/)(test|tests|spec|__tests__)/|[._-](test|spec)\.[[:alnum:]]+$|_spec\.rb$|_test\.(go|py|rb|exs)$|(^|/)test_[^/]+\.py$'
# A delete target: a test file, or a whole test directory.
readonly TEST_TARGET="$TEST_PATH"'|(^|/)(test|tests|spec|__tests__)/?$'
readonly SKIP_MARKER='\.(skip|only|skipIf|fixme)([^[:alnum:]_]|$)|(^|[^[:alnum:]_])x(it|describe|test|context|specify)([[:space:]]*\(|[[:space:]]+["'"'"'])|@pytest\.mark\.(skip|xfail)|pytest\.skip\(|unittest\.skip|\.Skip(Now|f)?\(|^[[:space:]]*(skip|pending)([[:space:]]|\(|$)|[,(][[:space:]]*:?(skip|pending)[[:space:]]*(:|=>)'
readonly LOCKFILE='(^|/)(package-lock\.json|npm-shrinkwrap\.json|yarn\.lock|pnpm-lock\.yaml|bun\.lockb?|Gemfile|Gemfile\.lock|poetry\.lock|uv\.lock|Pipfile|Pipfile\.lock|requirements[^/]*\.txt|Cargo\.lock|go\.mod|go\.sum|composer\.lock)$'
readonly WRITE_VERB='>|(^|[^[:alnum:]_.-])(tee|cp|mv|rm|ln|install|truncate|touch|dd|rsync|unlink|shred|python[0-9.]*|node|ruby|perl)([[:space:]]|$)|(^|[[:space:]])sed[[:space:]].*-i'
readonly DELETE_VERB='(^|[^[:alnum:]_.-])(rm|unlink|shred)([[:space:]]|$)'
readonly ADD_DEPENDENCY='(^|[^[:alnum:]_-])((npm|pnpm|yarn|bun)[[:space:]]+(add|install|i)([[:space:]]+-[^[:space:]]*)*[[:space:]]+[^-[:space:]]|bundle[[:space:]]+add|gem[[:space:]]+install|pip[0-9.]*[[:space:]]+install|uv[[:space:]]+add|poetry[[:space:]]+add|cargo[[:space:]]+add|go[[:space:]]+get)'

# Collapse //, /./ and /../ so a .. cannot step out of an allowed directory.
normalize() {
  local out="" seg
  local IFS=/
  set -f
  for seg in $1; do
    case "$seg" in
      ''|.) ;;
      ..) out=${out%/*} ;;
      *) out="$out/$seg" ;;
    esac
  done
  set +f
  printf '%s' "${out:-/}"
}

# Absolute, normalized form of $1 relative to directory $2.
resolve() {
  case "$1" in
    /*) normalize "$1" ;;
    *) normalize "$2/$1" ;;
  esac
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

# Path of $1 relative to its repo or worktree, and that top directory, on two
# lines. Uses git's prefix rather than string-stripping the top level, which
# breaks when the top resolves through a symlink (/var -> /private/var).
repo_relative() {
  local path=$1 dir prefix top
  dir=$(dirname "$path")
  while [ ! -d "$dir" ] && [ "$dir" != / ]; do dir=$(dirname "$dir"); done
  prefix=$(git -C "$dir" rev-parse --show-prefix 2>/dev/null) || return 1
  top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || return 1
  if [ "$dir" = / ]; then
    printf '%s%s\n%s' "$prefix" "${path#/}" "$top"
  else
    printf '%s%s\n%s' "$prefix" "${path#"$dir"/}" "$top"
  fi
}

# Engineer only: deny a write to a risky_paths glob from the worktree's
# .claude/autopilot.json (falling back to the launch repo's).
check_risky() {
  local path=$1 rel_and_top rel top config pattern
  rel_and_top=$(repo_relative "$path") || return 0
  rel=$(printf '%s' "$rel_and_top" | sed -n 1p)
  top=$(printf '%s' "$rel_and_top" | sed -n 2p)
  config="$top/.claude/autopilot.json"
  [ -f "$config" ] || config="$hook_cwd/.claude/autopilot.json"
  [ -f "$config" ] || return 0
  while IFS= read -r pattern; do
    [ -n "$pattern" ] || continue
    # In [[ == ]], * also matches /, so db/migrate/** and **/payments/** work.
    # shellcheck disable=SC2053
    if [[ $rel == $pattern || $rel == ${pattern#\*\*/} ]]; then
      deny "risky path $rel: stop and return status risky"
    fi
  done < <(jq -r '.risky_paths // [] | .[] | strings' "$config" 2>/dev/null)
}

# Rules for any write to $1, an absolute normalized path.
check_path_write() {
  local path=$1
  if is_run_file "$path"; then deny "run files are written by the staff engineer only"; fi
  if is_config_file "$path"; then deny "the autopilot config is written by the user only"; fi
  [ "$agent" = autopilot:engineer ] || return 0
  if printf '%s' "$path" | grep -Eiq "$LOCKFILE"; then
    deny "new dependency: stop and return status risky"
  fi
  check_risky "$path"
}

check_file_write() {
  local path text
  path=$(field .tool_input.file_path)
  [ -n "$path" ] || return 0
  path=$(resolve "$path" "${hook_cwd:-/}")
  text=$(printf '%s' "$input" | jq -r '[.tool_input.new_string, .tool_input.content, (.tool_input.edits // [] | .[]? | .new_string?)] | map(select(type == "string")) | join("\n")' 2>/dev/null)
  if printf '%s' "$path" | grep -Eq "$TEST_PATH" && printf '%s' "$text" | grep -Eq "$SKIP_MARKER"; then
    deny "tests are never skipped to make them pass"
  fi
  check_path_write "$path"
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

# Strip quotes and backslashes so "gh" pr merge or g\it push read as written.
unquote() { printf '%s' "$1" | tr -d "\"'\\\\\`"; }

# A word with leading redirection operators (>, 2>, &>, <) removed.
strip_redirect() {
  local word=$1
  while :; do
    case "$word" in
      [0-9\&\<\>]*[\<\>]*|[\<\>]*) word=${word#?} ;;
      *) break ;;
    esac
  done
  printf '%s' "$word"
}

check_bash() {
  local cmd segment norm base word target
  cmd=$(field .tool_input.command)
  [ -n "$cmd" ] || return 0
  base=${hook_cwd:-/}
  while IFS= read -r segment; do
    norm=$(unquote "$segment")

    if printf '%s' "$norm" | grep -Eq '(^|[^[:alnum:]_-])pr[[:space:]]+merge([[:space:]]|$)|pulls/[^[:space:]]*/merge|mergePullRequest|enablePullRequestAutoMerge'; then
      deny "agents never merge; the user merges"
    fi

    if printf '%s' "$norm" | grep -Eq '(^|[^[:alnum:]_-])push([[:space:]]|$)'; then
      if printf '%s' "$norm" | grep -Eq '(^|[[:space:]])(--fo[[:alnum:]-]*|--mirror|-[[:alpha:]]*f[[:alpha:]]*)([[:space:]=]|$)|[[:space:]]\+[^[:space:]]|(^|[[:space:]:/+])(main|master)([[:space:]]|$)'; then
        deny "no force-push and no pushes to main/master"
      fi
    fi

    if printf '%s' "$norm" | grep -Eq "$DELETE_VERB" \
      && printf '%s' "$norm" | tr '[:space:]' '\n' | grep -Eq "$TEST_TARGET"; then
      deny "tests are never deleted to make them pass"
    fi

    if [ "$agent" = autopilot:engineer ] && printf '%s' "$norm" | grep -Eq "$ADD_DEPENDENCY"; then
      deny "new dependency: stop and return status risky"
    fi

    # Track `cd DIR` so relative paths after it resolve where they will land.
    if printf '%s' "$norm" | grep -Eq '^[[:space:]]*(builtin[[:space:]]+)?(cd|pushd)[[:space:]]+[^-[:space:]]'; then
      word=$(printf '%s' "$norm" | sed -E 's/^[[:space:]]*(builtin[[:space:]]+)?(cd|pushd)[[:space:]]+([^[:space:]]+).*/\3/')
      base=$(resolve "$word" "$base")
    fi

    if printf '%s' "$norm" | grep -Eq "$WRITE_VERB"; then
      set -f
      for word in $norm; do
        word=$(strip_redirect "$word")
        word=${word#*=}
        case "$word" in ''|-*) continue ;; esac
        target=$(resolve "$word" "$base")
        check_path_write "$target"
      done
      set +f
    fi
  done < <(split_segments "$cmd")
}

case "$tool" in
  Edit|Write|MultiEdit) check_file_write ;;
  Bash) check_bash ;;
esac
exit 0
