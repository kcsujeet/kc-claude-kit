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
# backslash-newline continuations are joined, and the bodies of allowlisted
# heredocs are data, not commands (anything else is checked line by line).
# Per-segment checks use builtins only, so long commands stay fast.
#
# A hook that times out is non-blocking, i.e. it fails open, so for an
# autopilot:* agent the decision runs as a background job under a deadline
# (AUTOPILOT_GUARD_DEADLINE_S, default 8, below hooks.json's timeout of 60):
# past it the job's whole process group is killed and the call is denied.
# Command size and path complexity are capped as well (deny), so the
# deadline is a backstop rather than the normal way long input is handled.
#
# Output: the PreToolUse deny JSON on a block, nothing otherwise.
# Exit: always 0. Fails closed for autopilot:* agents when jq is missing,
# the input cannot be parsed, the deadline passes, or the guard itself errors.
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

# Exit codes of the decision job (see the end of the file). Allow is the one
# verdict that must be proven: only EXIT_ALLOW allows, every other status,
# a plain 0 included, denies.
readonly EXIT_ALLOW=42 EXIT_DENY=10
in_job=0
verdict_file=""

decided=0
deny() {
  local json
  decided=1
  if [ "$in_job" = 1 ]; then
    # The reason is best effort; the verdict itself is the exit status, so a
    # file that cannot be written (disk full, size limit) still denies.
    printf '%s' "$1" > "$verdict_file" 2>/dev/null
    exit "$EXIT_DENY"
  fi
  json=""
  if command -v jq >/dev/null 2>&1; then
    json=$(jq -cn --arg reason "autopilot: $1" \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}' 2>/dev/null)
  fi
  if [ -n "$json" ]; then
    printf '%s\n' "$json"
  else
    # Only fixed reasons reach this branch; strip anything JSON-unsafe anyway.
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"autopilot: %s"}}\n' \
      "${1//[\"\\]/}"
  fi
  exit 0
}

# An unexpected error (e.g. an unbound variable under set -u) denies instead
# of exiting non-zero, which Claude Code would treat as "allow". Any decision
# job or timer still running (see the end of the file) is killed first.
job=""
timer=""
# shellcheck disable=SC2329 # invoked by the EXIT trap
on_exit() {
  local status=$?
  [ -n "$job" ] && kill -KILL -- "-$job" 2>/dev/null
  [ -n "$timer" ] && kill -KILL -- "-$timer" 2>/dev/null
  [ -n "$verdict_file" ] && rm -f "$verdict_file"
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

readonly NL=$'\n' TAB=$'\t'

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
# A file-descriptor duplication (2>&1, 1>&2, >&2, 2>&-) writes no file.
readonly FD_DUP='(^|[[:space:]])[0-9]*>&([0-9]+-?|-)([[:space:]]|$)'
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
  'stacks/[^[:space:]]*merge'                              # REST: any /stacks/.../merge path
)
MERGE=$(alternatives "${merge_parts[@]}")

# gh stack (the built-in stacked-PR command) is denied except read-only
# subcommands; autopilot agents stack through the REST API instead. stack
# counts only as gh's subcommand, after any global flags (and their values),
# so "Stack" in a PR title is not one. After it, -R/--repo and its value may
# come before the read-only subcommand; any other word there denies.
readonly GH_STACK='(^|[^[:alnum:]_-])gh([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+stack([[:space:]]|$)'
readonly GH_STACK_REPO_FLAG='^[[:space:]]+(-R|--repo)([[:space:]]+|=)[^-[:space:]][^[:space:]]*'
readonly GH_STACK_READ_ONLY='^([[:space:]]+(view|list|status|--help|-h))([[:space:]]|$)'

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
# Most command text the guard checks (any one logical line, and all lines
# outside heredoc bodies together); more is denied. At this size the worst
# case stays well under the hook timeout.
readonly MAX_LINE=65536
# Most shell segments (and continuation lines in one logical line) checked.
readonly MAX_SEGMENTS=2000
# Most path parts a resolved path (a write target, or the directory tracked
# through cd) may have, and most bytes that directory may take; more is
# denied. Keeps path work linear in the command: each resolve walks at most
# this many parts, and the tracked directory never grows past a real path.
readonly MAX_PATH_PARTS=256
readonly MAX_PATH_BYTES=4096

# Sets $resolved to $1 made absolute against directory $2, with //, /./ and
# /../ collapsed so a .. cannot step out of an allowed directory. A path
# that is already in that form is returned as is, without a walk.
resolve() {
  local path=$1 out="" seg parts
  case "$path" in /*) ;; *) path="$2/$path" ;; esac
  parts=${path//[!\/]/}
  if [ "${#parts}" -gt "$MAX_PATH_PARTS" ]; then deny "command too complex for the guard"; fi
  case "$path" in
    *//*|*/./*|*/../*|*/.|*/..) ;;
    *) path=${path%/}; resolved=${path:-/}; return ;;
  esac
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

# True when $1 matches a risky_paths glob from the worktree's
# .claude/autopilot.json (falling back to the launch repo's); sets $risky_rel.
# The globs are read once per repo top.
config_top=$NL
config_patterns=""
is_risky() {
  local rel repo_top config pattern
  repo_info "$1" || return 1
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
      risky_rel=$rel
      return 0
    fi
  done
  return 1
}

# Engineer only: deny a write to a risky path.
check_risky() {
  if is_risky "$1"; then deny "risky path $risky_rel: stop and return status risky"; fi
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

# Prints $1 as the lines the guard checks, in one linear awk pass:
# backslash-newline continuations joined (a comment line never continues);
# quotes, backslashes and backticks stripped; >| read as >. A heredoc body is dropped only when bash certainly
# reads it as data, which this guard decides by allowlist rather than by
# modelling bash quoting:
# - the opener line is exactly `[cd P && ](cat|tee [-a] [P]) [> P] <<TAG
#   [> P]` or `[cd P && ]git commit [-flags] -F - <<TAG`, where P is a
#   plain path and TAG is 'TAG', "TAG" or TAG;
# - every line before it is blank, a comment, or `cd P` (an allowlist: any
#   other line could open a multi-line string or construct, or change what
#   the opener's command word runs, as alias, hash, enable, PATH=, printf -v
#   PATH, read PATH < f, a function definition and many more do);
# - its terminator line is exactly TAG (leading tabs allowed for <<-);
# - an unquoted TAG's body has no $( or backtick (bash would run those).
# Any other line containing << means nothing is dropped and every line is
# checked as a command.
# Exit 3: a logical line, or all the text left to check, is over MAX bytes.
# Exit 4: over MAX_SEGMENTS segments, or a logical line over that many lines.
# shellcheck disable=SC2016 # $ in the awk program is awk's, not the shell's
readonly READ_COMMANDS_AWK='
# A comment line never continues: bash reads its trailing backslash as part
# of the comment, so the next line stays a command of its own.
function continues(s) { if (s ~ /^[ \t]*#/) return 0; return match(s, /\\+$/) ? RLENGTH % 2 : 0 }
# The logical line starting at line i; sets next_i to the line after it.
function logical_at(i,   s, parts) {
  s = line[i]; i++; parts = 1
  while (continues(s) && i <= n) {
    s = substr(s, 1, length(s) - 1) line[i]; i++
    if (++parts > MAX_SEGMENTS || length(s) > MAX) exit 4
  }
  if (length(s) > MAX) exit 3
  next_i = i
  return s
}
# Sets tag, tag_quoted and tag_dash when s is an allowlisted opener.
function allowlisted_opener(s,   rest) {
  if (s !~ OPENER_CAT && s !~ OPENER_COMMIT) return 0
  rest = substr(s, index(s, "<<") + 2)
  tag_dash = (substr(rest, 1, 1) == "-")
  sub(/^-?[ \t]*/, "", rest)
  tag_quoted = (substr(rest, 1, 1) == SQ || substr(rest, 1, 1) == DQ)
  match(rest, /[A-Za-z_][A-Za-z0-9_]*/)
  tag = substr(rest, RSTART, RLENGTH)
  return 1
}
BEGIN {
  SQ = sprintf("%c", 39); DQ = "\""
  P = "[A-Za-z0-9_./~-]+"
  TAG = "(" SQ "[A-Za-z_][A-Za-z0-9_]*" SQ "|" DQ "[A-Za-z_][A-Za-z0-9_]*" DQ "|[A-Za-z_][A-Za-z0-9_]*)"
  CD = "(cd[ \t]+" P "[ \t]*&&[ \t]*)?"
  HEREDOC = "<<-?[ \t]*" TAG
  OPENER_CAT = "^[ \t]*" CD "(cat|tee([ \t]+-a)?([ \t]+" P ")?)[ \t]*(>>?[ \t]*" P "[ \t]*)?" HEREDOC "([ \t]*>>?[ \t]*" P ")?[ \t]*$"
  OPENER_COMMIT = "^[ \t]*" CD "git[ \t]+commit([ \t]+-[A-Za-z]+)*[ \t]+-F[ \t]+-[ \t]*" HEREDOC "[ \t]*$"
  CLEAN = "^[ \t]*(#.*)?$|^[ \t]*cd[ \t]+" P "[ \t]*$"
}
{ line[++n] = $0; if (index($0, "<<")) has_heredoc = 1 }
END {
  unsure = 0; i = 1
  while (i <= n && has_heredoc && !unsure) {
    s = logical_at(i); i = next_i
    if (!index(s, "<<")) { if (s !~ CLEAN) dirty = 1; continue }
    if (dirty || !allowlisted_opener(s)) { unsure = 1; break }
    found = 0; j = i
    while (j <= n) {
      start = j
      if (tag_quoted) { body = line[j]; j++ } else { body = logical_at(j); j = next_i }
      if (!tag_quoted && (index(body, "$(") || index(body, "`"))) break
      for (m = start; m < j; m++) skip[m] = 1
      if (tag_dash) sub(/^\t+/, "", body)
      if (body == tag) { found = 1; break }
    }
    if (!found) { unsure = 1; break }
    i = j
  }
  i = 1
  while (i <= n) {
    if (!unsure && skip[i]) { i++; continue }
    s = logical_at(i); i = next_i
    # >| is a redirect (noclobber override), not a pipe. Quotes, backslashes
    # and backticks go, so "gh" pr merge reads as written.
    gsub(/>\|/, ">", s)
    gsub(SQ, "", s)
    gsub(/["`\\]/, "", s)
    total += length(s) + 1
    if (total > MAX) exit 3
    segments += gsub(/&&|\|\||;|\|/, "&", s) + 1
    if (segments > MAX_SEGMENTS) exit 4
    print s
  }
}'

# Sets $command_text from $1 via READ_COMMANDS_AWK; denies a command too long
# or too complex to check in time (a hook that times out fails open).
read_commands() {
  local status=0
  command_text=$(printf '%s\n' "$1" | LC_ALL=C awk -v MAX="$MAX_LINE" -v MAX_SEGMENTS="$MAX_SEGMENTS" "$READ_COMMANDS_AWK") || status=$?
  if [ "$status" = 3 ]; then deny "command too long for the guard"; fi
  if [ "$status" = 4 ]; then deny "command too complex for the guard"; fi
  if [ "$status" != 0 ]; then deny "guard error; refusing the tool call"; fi
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
  local stack_rest cmd norm base word target next_is_target path_like base_risky=0 base_guarded=0 first
  cmd=$(field .tool_input.command)
  [ -n "$cmd" ] || return 0
  read_commands "$cmd"
  base=${hook_cwd:-/}
  if is_run_file "$base/_"; then base_guarded=1; fi
  while IFS= read -r norm; do

    if [[ $norm =~ $MERGE ]]; then deny "agents never merge; the user merges"; fi

    if [[ $norm =~ $GH_STACK ]]; then
      stack_rest=" ${norm#*"${BASH_REMATCH[0]}"}"
      while [[ $stack_rest =~ $GH_STACK_REPO_FLAG ]]; do stack_rest=${stack_rest#"${BASH_REMATCH[0]}"}; done
      [[ $stack_rest =~ $GH_STACK_READ_ONLY ]] || deny "gh stack is limited to view, list and status; stack through the REST API"
    fi

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
      if [ "${#base}" -gt "$MAX_PATH_BYTES" ]; then deny "command too complex for the guard"; fi
      # Inside a risky directory every write target is risky: touch add_col.
      base_risky=0
      if [ "$agent" = autopilot:engineer ] && is_risky "$base/_"; then base_risky=1; fi
      base_guarded=$base_risky
      if is_run_file "$base/_" || is_config_file "$base/autopilot.json"; then base_guarded=1; fi
    fi

    while [[ $norm =~ $FD_DUP ]]; do norm=${norm/"${BASH_REMATCH[0]}"/ }; done
    [[ $norm =~ $WRITE_VERB ]] || continue
    next_is_target=0
    first=1
    for word in $norm; do
      path_like=$next_is_target
      # The command word itself is not a target.
      if [ "$first" = 1 ]; then first=0; else [ "$base_risky" = 1 ] && path_like=1; fi
      next_is_target=0
      case "$word" in
        [0-9\&]'>'|[0-9\&]'>>'|'>'|'>>') next_is_target=1; continue ;;
        [0-9\&]'>'*|'>'*) path_like=1 ;;
      esac
      # Leading redirection operators (>, 2>, &>, <) off; dd of=PATH to PATH.
      while [[ $word == [0-9\&\<\>]*[\<\>]* || $word == [\<\>]* ]]; do word=${word#?}; done
      word=${word#*=}
      case "$word" in
        ''|-*) continue ;;
        */*|*.*) path_like=1 ;;
        Gemfile|Pipfile) ;;
        # A bare word (no / or .) can only land on a guarded path when it
        # is a redirect target or the cd directory itself is guarded.
        *) [ "$path_like" = 1 ] || [ "$base_guarded" = 1 ] || continue ;;
      esac
      resolve "$word" "$base"
      target=$resolved
      check_path_write "$target" "$path_like"
    done
  done < <(split_segments "$command_text")
}

decide() {
  # Test hook: a delay inside the job, so the deadline can be exercised.
  if [ -n "${AUTOPILOT_GUARD_TEST_DELAY_S:-}" ]; then sleep "$AUTOPILOT_GUARD_TEST_DELAY_S"; fi
  case "$tool" in
    Edit|Write|MultiEdit) check_file_write ;;
    Bash) check_bash ;;
  esac
}

# The decision runs as a job in its own process group (set -m gives each
# background job one, tty or not); a timer job kills the whole group at the
# deadline. The verdict travels in the job's exit status: EXIT_ALLOW when
# decide() ran to the end without a deny, EXIT_DENY from deny() with the
# reason in the verdict file (best effort), anything else is an error or
# the kill. The parent alone prints, and allows only on EXIT_ALLOW. Both
# groups are killed and reaped whichever finishes first, so nothing outlives
# the guard, not even a child of a job shell that died abnormally. The jobs
# drop the EXIT trap and job control so their children share their group
# and nothing they do touches the verdict file.
deadline=${AUTOPILOT_GUARD_DEADLINE_S:-8}
case "$deadline" in ''|*[!0-9]*) deadline=8 ;; esac
verdict_file=$(mktemp "${TMPDIR:-/tmp}/autopilot-guard.XXXXXX") || deny "guard error; refusing the tool call"
set -m
( trap - EXIT; set +m; in_job=1; decide; exit "$EXIT_ALLOW" ) > /dev/null &
job=$!
( trap - EXIT; set +m; sleep "$deadline"; kill -KILL -- "-$job" ) 2>/dev/null &
timer=$!
wait "$job" 2>/dev/null
job_status=$?
kill -KILL -- "-$job" 2>/dev/null
kill -KILL -- "-$timer" 2>/dev/null
wait "$timer" 2>/dev/null
job=""
timer=""
set +m
case "$job_status" in
  "$EXIT_ALLOW") ;;
  "$EXIT_DENY")
    reason=""
    [ -r "$verdict_file" ] && IFS= read -r -d '' reason < "$verdict_file"
    deny "${reason:-tool call denied}" ;;
  137) deny "guard timed out; command denied" ;;
  *) deny "guard error; refusing the tool call" ;;
esac
exit 0
