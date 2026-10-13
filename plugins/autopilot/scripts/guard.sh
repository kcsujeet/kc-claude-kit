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
# Most command text the guard checks (any one logical line, and all lines
# outside heredoc bodies together); more is denied. At this size the worst
# case stays well under the hook timeout.
readonly MAX_LINE=65536

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

# Prints $1 as bash would read its commands: backslash-newline continuations
# joined, each heredoc body dropped once its delimiter line is found, then
# quotes, backslashes and backticks stripped and >| read as >. One
# linear awk pass (a per-character bash loop is quadratic on long lines).
# Quote state ('…', "…", $'…', `…`, $( ), $(( ))) carries across lines. When
# the parser is unsure (a line ends inside an open quote, a << inside $( ) or
# backticks, a delimiter that is not a plain word, or no delimiter line), it
# drops nothing and every line is checked as a command.
# Exit 3: a logical line, or all the command text left to check (heredoc
# bodies excluded), is longer than MAX bytes.
# shellcheck disable=SC2016 # $ in the awk program is awk's, not the shell's
readonly READ_COMMANDS_AWK='
function continues(s) { return match(s, /\\+$/) ? RLENGTH % 2 : 0 }
# The logical line starting at line i; sets next_i to the line after it.
function logical_at(i,   s) {
  s = line[i]; i++
  while (continues(s) && i <= n) {
    s = substr(s, 1, length(s) - 1) line[i]; i++
    if (length(s) > MAX) exit 3
  }
  if (length(s) > MAX) exit 3
  next_i = i
  return s
}
# Scans one logical line, updating the carried quote state. Fills tag[],
# tag_quoted[] and tag_dash[] with the heredocs it opens and returns their
# count, or -1 when unsure.
function scan(s,   len, k, c, prev, count, word, plain, singles, doubles) {
  len = split(s, ch, "")
  count = 0; prev = " "
  for (k = 1; k <= len; k++) {
    c = ch[k]
    if (in_single) { if (c == SQ) in_single = 0; continue }
    if (in_ansi) { if (c == BS) { k++; continue }; if (c == SQ) in_ansi = 0; continue }
    if (c == BS) { k++; prev = "x"; continue }
    if (in_double) { if (c == DQ) in_double = 0; continue }
    if (c == SQ) { if (prev == "$") in_ansi = 1; else in_single = 1; prev = c; continue }
    if (c == DQ) { in_double = 1; prev = c; continue }
    if (c == "`") { in_backtick = !in_backtick; prev = c; continue }
    if (c == "#" && prev ~ /^[ \t;&|(]$/) break
    if (c == "(") {
      if (ch[k + 1] == "(") { arith++; k++; prev = "("; continue }
      if (prev == "$") subst++
      prev = c; continue
    }
    if (c == ")") {
      if (arith > 0 && ch[k + 1] == ")") { arith--; k++; prev = ")"; continue }
      if (subst > 0) subst--
      prev = c; continue
    }
    if (c == "<" && ch[k + 1] == "<") {
      if (ch[k + 2] == "<") { k += 2; prev = "<"; continue }
      if (arith > 0) { k++; prev = "<"; continue }
      if (subst > 0 || in_backtick) return -1
      k += 2
      count++
      tag_dash[count] = 0
      if (ch[k] == "-") { tag_dash[count] = 1; k++ }
      while (ch[k] == " " || ch[k] == "\t") k++
      word = ""
      while (k <= len && ch[k] !~ /^[ \t;|&<>()]$/) { word = word ch[k]; k++ }
      k--
      plain = word
      singles = gsub(SQ, "", plain)
      doubles = gsub(DQ, "", plain)
      if (singles % 2 || doubles % 2) return -1
      tag_quoted[count] = (singles + doubles > 0 || index(word, BS) > 0)
      gsub(/\\/, "", plain)
      if (plain !~ /^[A-Za-z0-9_.-]+$/) return -1
      tag[count] = plain
      prev = "x"; continue
    }
    prev = c
  }
  if (in_single || in_double || in_ansi || in_backtick || subst > 0 || arith > 0) return -1
  return count
}
BEGIN { SQ = sprintf("%c", 39); DQ = "\""; BS = "\\" }
{ line[++n] = $0; if (index($0, "<<")) has_heredoc = 1 }
END {
  unsure = 0; i = 1
  while (i <= n && has_heredoc && !unsure) {
    s = logical_at(i); i = next_i
    count = scan(s)
    if (count < 0) { unsure = 1; break }
    j = i
    for (h = 1; h <= count; h++) {
      found = 0
      while (j <= n) {
        start = j
        if (tag_quoted[h]) { body = line[j]; j++ } else { body = logical_at(j); j = next_i }
        for (m = start; m < j; m++) skip[m] = 1
        if (tag_dash[h]) sub(/^\t+/, "", body)
        if (body == tag[h]) { found = 1; break }
      }
      if (!found) { unsure = 1; break }
    }
    if (!unsure) i = j
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
    print s
  }
}'

# Sets $command_text from $1 via READ_COMMANDS_AWK; denies a command too long
# to parse in time (a hook that times out fails open).
read_commands() {
  local status=0
  command_text=$(printf '%s\n' "$1" | LC_ALL=C awk -v MAX="$MAX_LINE" "$READ_COMMANDS_AWK") || status=$?
  if [ "$status" = 3 ]; then deny "command too long for the guard"; fi
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
  local cmd norm base word target next_is_target path_like base_risky=0 base_guarded=0 first
  cmd=$(field .tool_input.command)
  [ -n "$cmd" ] || return 0
  read_commands "$cmd"
  base=${hook_cwd:-/}
  if is_run_file "$base/_"; then base_guarded=1; fi
  while IFS= read -r norm; do

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
      # Inside a risky directory every write target is risky: touch add_col.
      base_risky=0
      if [ "$agent" = autopilot:engineer ] && is_risky "$base/_"; then base_risky=1; fi
      base_guarded=$base_risky
      if is_run_file "$base/_" || is_config_file "$base/autopilot.json"; then base_guarded=1; fi
    fi

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

case "$tool" in
  Edit|Write|MultiEdit) check_file_write ;;
  Bash) check_bash ;;
esac
exit 0
