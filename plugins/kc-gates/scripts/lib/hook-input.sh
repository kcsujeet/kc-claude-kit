# shellcheck shell=bash
# shellcheck disable=SC2034 # the globals set here are read by the guards that source this file
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

# is_commit_staging_all <word>...: true when the words after `git commit` add every tracked change to the
# commit (-a, --all, or -a inside a cluster such as -am; -u<mode> is the untracked-files option, not -a).
is_commit_staging_all() {
  local word
  for word in "$@"; do
    case "$word" in
      --all) return 0 ;;
      --* | -u*) ;;
      -*a*) return 0 ;;
    esac
  done
  return 1
}

# The default branch of the repository in $1 as a ref that exists, or nothing.
get_default_branch_ref() {
  local dir=$1 remote_default candidate
  remote_default=$(git -C "$dir" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null) || remote_default=""
  for candidate in $remote_default origin/main origin/master main master; do
    git -C "$dir" rev-parse -q --verify "$candidate^{commit}" >/dev/null 2>&1 && { printf '%s' "$candidate"; return; }
  done
}

# True when the repository in $1 is concluding a merge (MERGE_HEAD) of a commit the default branch
# already has: its staged diff carries the default branch's own changes, not this branch's.
is_default_branch_merge() {
  local dir=$1 merge_head default_branch_ref
  merge_head=$(git -C "$dir" rev-parse -q --verify MERGE_HEAD 2>/dev/null) || return 1
  default_branch_ref=$(get_default_branch_ref "$dir")
  # With no default branch the ref is empty and merge-base fails, so nothing is skipped.
  git -C "$dir" merge-base --is-ancestor "$merge_head" "$default_branch_ref" 2>/dev/null
}

# State a command's earlier segments leave for the guard of a later one. A guard runs before the whole
# command, so it sees the index, HEAD and the working tree as they are now, not as the command's own
# `git add`, `git commit` or other steps leave them. note_chain_segment records those steps for the
# guards; get_commit_diff replays the staging.
CHAIN_STAGING=()
CHAIN_PENDING_COMMAND=false
CHAIN_RAN_COMMAND_BEFORE_STAGING=false
CHAIN_MOVED_HEAD=false
readonly UNJUDGEABLE_COMMIT_REASON='this one command runs other commands before it stages or commits, so what it commits cannot be known before it runs. Stage in one command, then commit in the next.'
readonly MOVED_HEAD_REASON='this one command commits, merges, switches branch or otherwise moves HEAD and then publishes, so the guard would judge the branch from before it. Commit in one command, then run this one.'

# note_chain_segment <segment> <dir>: call for each segment, in order, before judging it. Records a
# `git add` in CHAIN_STAGING; a commit, switch or other HEAD move in CHAIN_MOVED_HEAD; and any command
# other than a git subcommand that leaves the index and working tree alone in CHAIN_PENDING_COMMAND,
# which becomes CHAIN_RAN_COMMAND_BEFORE_STAGING when staging follows it. A git subcommand that
# rewrites the index or working tree some other way (rm, checkout, merge --squash, stash pop...) is
# recorded as `add -A` that ran after a command, so a commit after it is unjudgeable.
note_chain_segment() {
  local segment=$1 dir=$2 words_text words=()
  words_text=$(git_words "$segment")
  if [ -n "$words_text" ]; then
    read -ra words <<< "$words_text"
    parse_git_command "$dir" "${words[@]}"
    case "${GIT_ARGS[0]:-}" in
      commit | merge | cherry-pick | rebase | am | pull | revert | reset | checkout | switch) CHAIN_MOVED_HEAD=true ;;
    esac
    case "${GIT_ARGS[0]:-}" in
      add)
        CHAIN_STAGING+=("$GIT_DIR"$'\t'"${GIT_ARGS[*]}")
        if $CHAIN_PENDING_COMMAND; then CHAIN_RAN_COMMAND_BEFORE_STAGING=true; fi
        CHAIN_PENDING_COMMAND=false
        return ;;
      rm | mv | apply | stash | restore | merge | cherry-pick | revert | am | pull | reset | checkout | switch | rebase)
        CHAIN_STAGING+=("$GIT_DIR"$'\t'"add -A")
        CHAIN_RAN_COMMAND_BEFORE_STAGING=true
        return ;;
      commit | status | diff | log | show | rev-parse | fetch | branch | remote | config | ls-files | describe | worktree) return ;;
    esac
  fi
  printf '%s' "$segment" | grep -q '[^[:space:]]' || return 0
  CHAIN_PENDING_COMMAND=true
}

# is_commit_unjudgeable <dir> <word>...: true when the words after `git commit` commit something an
# earlier command of this one command may still change: what it stages (a command ran before the
# staging), or the working tree it reads (-a, or paths).
is_commit_unjudgeable() {
  local dir=$1
  shift
  if $CHAIN_RAN_COMMAND_BEFORE_STAGING; then return 0; fi
  if $CHAIN_PENDING_COMMAND; then
    is_commit_staging_all "$@" || [ -n "$(get_commit_paths "$dir" "$@")" ]
    return
  fi
  return 1
}

# get_commit_paths <dir> <word>...: the paths named on a `git commit` (words after `commit`), which it
# commits as the working tree has them, ignoring the index. Option values are skipped; a word that
# isn't an existing path is not one.
get_commit_paths() {
  local dir=$1 word skip=false after_dashes=false
  shift
  for word in "$@"; do
    if $skip; then skip=false; continue; fi
    if ! $after_dashes; then
      case "$word" in
        --) after_dashes=true; continue ;;
        --message | --file | --author | --date | --reuse-message | --reedit-message | --template | --cleanup | --fixup | --squash) skip=true; continue ;;
        --*) continue ;;
        -*[mFCct]) skip=true; continue ;;
        -*) continue ;;
      esac
    fi
    [ -e "$dir/$word" ] && printf '%s\n' "$word"
  done
}

# get_commit_diff <dir> "<diff options>" <word>...: the diff a `git commit` with these words after
# `commit` would record. The staged diff; with -a/--all, the working tree against HEAD; with paths,
# those paths in the working tree; after a `git add` earlier in the same command, the index (and the
# paths, and -a) with that add replayed on a copy. A repository with no commit yet is diffed against
# the empty tree.
get_commit_diff() {
  local dir=$1 options=$2 base=HEAD commit_path commit_paths=() staging_record staging_record_dir staging_record_words staging_words=() scratch_dir temp_index index_file
  shift 2
  git -C "$dir" rev-parse -q --verify HEAD >/dev/null 2>&1 || base=$(git -C "$dir" hash-object -t tree /dev/null)
  while IFS= read -r commit_path; do commit_paths+=("$commit_path"); done < <(get_commit_paths "$dir" "$@")
  # shellcheck disable=SC2086 # $options is a list of diff options
  if [ "${#CHAIN_STAGING[@]}" -gt 0 ]; then
    scratch_dir=$(mktemp -d)
    temp_index="$scratch_dir/index"
    index_file=$(git -C "$dir" rev-parse --git-path index)
    case "$index_file" in /*) ;; *) index_file="$dir/$index_file" ;; esac
    cp "$index_file" "$temp_index" 2>/dev/null || true
    for staging_record in "${CHAIN_STAGING[@]}"; do
      staging_record_dir=${staging_record%%$'\t'*}
      staging_record_words=${staging_record#*$'\t'}
      [ "$staging_record_dir" = "$dir" ] || continue
      read -ra staging_words <<< "$staging_record_words"
      # A replay git rejects is treated as add -A, so the diff errs toward more than the commit will hold.
      GIT_INDEX_FILE=$temp_index git -C "$dir" "${staging_words[@]}" >/dev/null 2>&1 \
        || GIT_INDEX_FILE=$temp_index git -C "$dir" add -A >/dev/null 2>&1
    done
    if is_commit_staging_all "$@"; then GIT_INDEX_FILE=$temp_index git -C "$dir" add -u >/dev/null 2>&1; fi
    if [ "${#commit_paths[@]}" -gt 0 ]; then GIT_INDEX_FILE=$temp_index git -C "$dir" add -- "${commit_paths[@]}" >/dev/null 2>&1; fi
    GIT_INDEX_FILE=$temp_index git -C "$dir" diff --cached $options --no-color --no-ext-diff --no-renames "$base" -- ${commit_paths[@]+"${commit_paths[@]}"}
    rm -rf "$scratch_dir"
  elif [ "${#commit_paths[@]}" -gt 0 ]; then
    git -C "$dir" diff $options --no-color --no-ext-diff --no-renames "$base" -- "${commit_paths[@]}"
  elif is_commit_staging_all "$@"; then
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

# read_change_class <dir> <change-class.sh option>...: prints prose_small, code_small or full for the
# change (change-class.sh); full when it cannot be read.
read_change_class() {
  local dir=$1 class
  shift
  class=$(bash "$(dirname "${BASH_SOURCE[0]}")/../change-class.sh" --dir "$dir" "$@" 2>/dev/null | sed -n 's/^CLASS=//p')
  printf '%s' "${class:-full}"
}

# is_small_class <class>: succeeds for a class that needs no review pass receipt: prose_small, or
# code_small (pass-size.sh small with no risk: line). full, and anything unreadable, fails.
is_small_class() {
  case "${1:-}" in
    prose_small | code_small) return 0 ;;
    *) return 1 ;;
  esac
}

# needed_phrases_sentence <dir> <this guard's phrase>: the sentence a block that needs the user's typed
# words ends with: every phrase the remaining steps need (approvals-needed.sh, this guard's first),
# so the user types one message. Prints nothing in check-only mode (KC_CHECK_ONLY=1), where
# approvals-needed.sh runs the guards.
needed_phrases_sentence() {
  local dir=$1 own=$2 phrases
  [ "${KC_CHECK_ONLY:-0}" != 1 ] || return 0
  phrases=$({ printf '%s\n' "$own"; bash "$(dirname "${BASH_SOURCE[0]}")/../approvals-needed.sh" --dir "$dir" 2>/dev/null; } | awk 'NF && !seen[$0]++ { printf "%s\"%s\"", (n++ ? ", " : ""), $0 }')
  printf ' Every phrase the remaining steps (commit, pull request, merge) need, so the user types one message: %s.' "$phrases"
}

# One shell segment per line: split on newlines, ;, &&, || and |.
split_segments() {
  printf '%s\n' "$1" | sed -e 's/&&/\
/g' -e 's/||/\
/g' -e 's/;/\
/g' -e 's/|/\
/g'
}
