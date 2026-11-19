# shellcheck shell=bash
# Reads a Bash hook's payload (PreToolUse or PostToolUse) and the command it carries, for the
# kit's hooks. Sourced, never executed.
#
# KC_GUARD_NO_JQ=1 forces the sed fallback (used by the tests).

# Where a `gh` command starts in a segment: `gh` as a whole word, then its subcommand.
readonly GH_COMMAND_START='(^|[^[:alnum:]_.-])gh[[:space:]]+'

# A PR's merge endpoint; a GET on it only asks whether the PR is merged.
readonly PR_MERGE_ENDPOINT='pulls/[0-9]+/merge([^/[:alnum:]]|$)'

# True when the segment merges a PR: `gh pr merge` (not `--disable-auto`, which only cancels a
# queued one), or a `gh api` PUT to a PR's merge endpoint. Read by remind-look-back.sh and
# update-after-merge.sh.
is_merge_segment() {
  local segment=$1
  if printf '%s' "$segment" | grep -Eq "${GH_COMMAND_START}pr[[:space:]]+merge([[:space:]]|$)"; then
    printf '%s' "$segment" | grep -Eq -- '--disable-auto([[:space:]]|$)' && return 1
    return 0
  fi
  printf '%s' "$segment" | grep -Eq "${GH_COMMAND_START}api([[:space:]]|$)" || return 1
  printf '%s' "$segment" | grep -Eq "$PR_MERGE_ENDPOINT" || return 1
  printf '%s' "$segment" | grep -Eq -- "(-X|--method)[[:space:]=]*[\"']?PUT"
}

# What the look-back reminders end with, so a merge, an approval, what the person says and what a
# command's output shows all carry it. No quotes or backslashes: it goes into JSON as it is.
# shellcheck disable=SC2034 # read by the scripts that source this file
readonly LOOK_BACK_TRACKING='The look-back stays on the visible task list until feedback-ledger.sh check passes. A look-back run at an earlier hand-off (such as when the pull request went to review) does not cover feedback that arrived after it. Delete the files this session made only to hand on, without asking.'

# Prints a top-level or tool_input string field of the payload: `command`
# comes from tool_input, `stdout` from tool_response (a string response counts as its stdout),
# `cwd` and `prompt` from the top level.
extract_field() {
  local input="$1" field="$2" path
  case "$field" in
    command) path='.tool_input.command' ;;
    stdout) path='(.tool_response.stdout? // (.tool_response | strings))' ;;
    *) path=".$field" ;;
  esac
  if [ "${KC_GUARD_NO_JQ:-0}" != 1 ] && command -v jq >/dev/null 2>&1; then
    printf '%s' "$input" | jq -r "$path // empty" 2>/dev/null
    return
  fi
  # JSON strings hold no raw newlines, so joining lines is safe. The capture
  # keeps escapes such as \" and \n; the callers tolerate them.
  printf '%s' "$input" \
    | tr '\n' ' ' \
    | sed -nE 's/.*"'"$field"'"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)".*/\1/p' \
    | sed -e 's/\\n/\
/g' -e 's/\\"/"/g'
}

# The words after `gh` in a segment, quotes dropped; empty when it runs no gh.
gh_words() {
  printf '%s' "$1" \
    | tr -d "\"'" \
    | sed -nE 's/^(.*[^[:alnum:]_.-])?gh[[:space:]]+(.*)$/\2/p'
}

# The words after `git` when the segment starts with it (after any VAR=value
# prefixes), quotes dropped; empty otherwise.
git_words() {
  printf '%s' "$1" \
    | tr -d "\"'" \
    | sed -nE 's/^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*git[[:space:]]+(.*)$/\2/p'
}

# parse_git_command <dir> <word>...: reads the words after `git` the way git does, skipping -C <path>
# and -c <key=value>. Sets GIT_DIR to the directory the command runs in and GIT_ARGS to the
# subcommand and its words (empty when there is none).
parse_git_command() {
  GIT_DIR=$1
  shift
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -C)
        case "${2:-}" in
          "") ;;
          /*) GIT_DIR=$2 ;;
          *) GIT_DIR="$GIT_DIR/$2" ;;
        esac
        shift ;;
      -c) shift ;;
      -*) ;;
      *) break ;;
    esac
    shift
  done
  # shellcheck disable=SC2034 # read by the scripts that source this file
  GIT_ARGS=("$@")
}

# walk_segments <command> <dir> <callback>: calls <callback> <segment> <dir> for each shell segment of
# the command, following any `cd` before it (the directory the segment runs in). Stops and fails as
# soon as the callback fails; succeeds when every segment passed.
walk_segments() {
  local command=$1 dir=$2 callback=$3 segment target
  while IFS= read -r segment; do
    target=$(printf '%s' "$segment" | sed -nE 's/^[[:space:]]*cd[[:space:]]+([^[:space:]]+)[[:space:]]*$/\1/p' | tr -d "\"'")
    if [ -n "$target" ]; then
      case "$target" in
        "~"*) target="$HOME${target#"~"}" ;;
        /*) ;;
        *) target="$dir/$target" ;;
      esac
      dir=$target
      continue
    fi
    "$callback" "$segment" "$dir" || return 1
  done <<EOF
$(split_segments "$command")
EOF
}

# print_pretooluse_deny <reason>: the PreToolUse deny JSON for a reason in plain text.
print_pretooluse_deny() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' \
    "$(printf '%s' "$1" | LC_ALL=C tr -d '\000-\037' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
}

# commit_stages_all <word>...: true when the words after `git commit` add every tracked change to the
# commit (-a, --all, or -a inside a cluster such as -am).
commit_stages_all() {
  local word
  for word in "$@"; do
    case "$word" in
      --all) return 0 ;;
      --*) ;;
      -*a*) return 0 ;;
    esac
  done
  return 1
}

# get_commit_diff <dir> "<diff options>" <word>...: the diff a `git commit` with these words after
# `commit` would record: the staged diff, or with -a/--all the working tree against HEAD. A
# repository with no commit yet is diffed against the empty tree.
get_commit_diff() {
  local dir=$1 options=$2 all=false base=HEAD
  shift 2
  commit_stages_all "$@" && all=true
  git -C "$dir" rev-parse -q --verify HEAD >/dev/null 2>&1 || base=4b825dc642cb6eb9a060e54bf8d69288fbee4904
  # shellcheck disable=SC2086 # $options is a list of diff options
  if $all; then
    git -C "$dir" diff $options --no-color --no-ext-diff --no-renames "$base"
  else
    git -C "$dir" diff --cached $options --no-color --no-ext-diff --no-renames "$base"
  fi
}

# user_approved <transcript> <phrase>: succeeds only when the latest message the person typed in the
# session transcript (a JSONL file) contains <phrase>, case-insensitive. A typed message is read the
# way feedback-ledger.sh reads one (lib/typed-message.jq): not a tool result, a relayed or agent
# message, or a system note. No transcript, no jq, or no typed message (a subagent session) means
# not approved: only the person's own words approve what a guard blocks.
user_approved() {
  local transcript=$1 phrase=$2
  [ -n "$transcript" ] && [ -r "$transcript" ] && command -v jq >/dev/null 2>&1 || return 1
  jq -rs -L "$(dirname "${BASH_SOURCE[0]}")" 'include "typed-message";
    (map(is_typed_message) | rindex(true)) as $last
    | if $last == null then empty else .[$last] | typed_texts end' "$transcript" 2>/dev/null \
    | grep -qiF -- "$phrase"
}

# One shell segment per line: split on newlines, ;, &&, || and |.
split_segments() {
  printf '%s\n' "$1" | sed -e 's/&&/\
/g' -e 's/||/\
/g' -e 's/;/\
/g' -e 's/|/\
/g'
}
