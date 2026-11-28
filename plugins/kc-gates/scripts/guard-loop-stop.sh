#!/usr/bin/env bash
# PreToolUse guard for Bash: the loop-stop rule as a block, armed only inside an agent's review/fix
# loop. A kc-ready-for-human-review pass reviews the change in rounds, and each round's fixes are
# reviewed by the next; a fix that rewrites lines an earlier round's fix wrote is where that loop
# starts going in circles, so such a commit stops until the user says to go on.
#
# The guard is armed while a pass is open on the branch: a pass folder
# (${KC_PASS_ROOT:-${TMPDIR:-/tmp}}/kc-pass-*/round-1/meta.env) whose round-1 head (HEAD_SHA) is HEAD or
# an ancestor of it, with no kc-ready-for-human-review receipt on that head or any commit after it (the
# receipt ends the pass). With no open pass it never blocks: a person's edits, a reviewer's
# requested changes after the hand-off, and lines other work merged are no agent loop.
#
# On a `git commit` inside an open pass it blames the old side of each line the commit changes (the
# staged diff, or the working tree with -a) and blocks when the line was written by a commit of the
# pass's own fix rounds: after its round-1 head, up to HEAD. A fix of round 1's findings edits the
# original change and passes; a later round rewriting an earlier round's fix is blocked. A hunk whose
# changed lines only set a version is left out, and so is a commit concluding a merge of the default
# branch as staged. Everything it cannot read counts as no loop.
#
# A command containing the literal KC_REWORK_APPROVED=1 passes only when the user's own words approve
# it: a message they typed on this branch in the session transcript (the payload's transcript_path)
# contains "approve rework" (user_approved in lib/hook-input.sh).
#
# Output: the PreToolUse deny JSON on a blocked command, nothing otherwise. Always exits 0.
# Hook schema: https://code.claude.com/docs/en/hooks
#
# KC_GUARD_NO_JQ=1 forces the sed fallback for reading the payload (used by the tests).

# shellcheck disable=SC2329 # walk_segments calls check_segment by name, so shellcheck sees nothing below it used
set -u

scripts_dir=$(dirname "$0")
# shellcheck source=lib/hook-input.sh
. "$scripts_dir/lib/hook-input.sh"

readonly APPROVAL_TOKEN='KC_REWORK_APPROVED=1'
readonly APPROVAL_PHRASE='approve rework'
# A changed line that only sets a version: a JSON or TOML key, or a constant, holding a quoted value.
readonly VERSION_LINE='^[-+][[:space:]]*"?(version|VERSION)"?[[:space:]]*[:=][[:space:]]*"[^"]*",?[[:space:]]*$'

# Copies a `git diff -U0`'s file headers and hunk headers from stdin to stdout, leaving out each hunk
# whose changed lines all set a version. Hunk bodies are not copied: the blame reads only the headers.
drop_version_bump_hunks() {
  awk -v version_line="$VERSION_LINE" '
    function flush_hunk(   has_pending_header) {
      has_pending_header = (hunk_header != "")
      if (has_pending_header && !only_version) print hunk_header
      hunk_header = ""; only_version = 1
    }
    /^diff --git / { flush_hunk(); in_hunk = 0; print; next }
    /^@@ / { flush_hunk(); in_hunk = 1; hunk_header = $0; next }
    in_hunk {
      is_changed_line = ($0 ~ /^[-+]/); sets_version = ($0 ~ version_line)
      if (is_changed_line && !sets_version) only_version = 0
      next
    }
    { print }
    END { flush_hunk() }
  '
}

# Prints "<sha> <path>:<line>" for each old-side line a `git diff -U0` (on stdin) changes, blamed at
# the revision $1 in the repository $2. A `--- ` line is a file header only between a `diff --git`
# line and its first hunk; anywhere else it is a removed line that starts with `-- `.
list_blamed_old_lines() {
  local rev=$1 dir=$2 path="" ranges="" in_header=false line start count
  print_blame_of_file() {
    [ -n "$path" ] && [ -n "$ranges" ] || return 0
    # shellcheck disable=SC2086 # $ranges is a list of -L options
    git -C "$dir" blame --line-porcelain $ranges "$rev" -- "$path" 2>/dev/null \
      | awk -v path="$path" '/^[0-9a-f]{40} [0-9]+ [0-9]+/ { print $1, path ":" $2 }'
  }
  while IFS= read -r line; do
    case "$line" in
      "diff --git "*) print_blame_of_file; path=""; ranges=""; in_header=true ;;
      "--- a/"*) if $in_header; then path=${line#--- a/}; fi ;;
      "@@ -"*)
        in_header=false
        start=${line#@@ -}; start=${start%% *}
        count=1
        case "$start" in *,*) count=${start#*,}; start=${start%,*} ;; esac
        [ "$count" -gt 0 ] && ranges="$ranges -L $start,$((start + count - 1))"
        ;;
    esac
  done
  print_blame_of_file
}

# True when commit $2 (in directory $1) has a kc-ready-for-human-review receipt.
has_receipt() { bash "$scripts_dir/ready-receipt.sh" check "$2" >/dev/null 2>&1; }

# Prints the round-1 head of the review pass open on the branch in $1, or nothing: the newest pass
# folder whose round-1 head is HEAD or an ancestor of it and that no receipt has ended yet.
find_open_pass_start() {
  local dir=$1 meta pass_start newest="" sha is_ended
  for meta in "${KC_PASS_ROOT:-${TMPDIR:-/tmp}}"/kc-pass-*/round-1/meta.env; do
    [ -f "$meta" ] || continue
    pass_start=$(sed -n 's/^HEAD_SHA=//p' "$meta" | head -n 1)
    [ -n "$pass_start" ] || continue
    git -C "$dir" merge-base --is-ancestor "$pass_start" HEAD 2>/dev/null || continue
    is_ended=false
    for sha in "$pass_start" $(git -C "$dir" rev-list "$pass_start..HEAD" 2>/dev/null); do
      if has_receipt "$dir" "$sha"; then is_ended=true; break; fi
    done
    $is_ended && continue
    if [ -z "$newest" ] || git -C "$dir" merge-base --is-ancestor "$newest" "$pass_start" 2>/dev/null; then newest=$pass_start; fi
  done
  printf '%s' "$newest"
}

# Prints "<sha> <subject> (<file>:<line>)" of the first blamed line a fix round of the pass wrote:
# a commit after the pass's round-1 head $2, up to HEAD, in directory $1. The diff is on stdin.
find_fix_round_line() {
  local dir=$1 pass_start=$2 round_commits sha location subject
  round_commits=" $(git -C "$dir" rev-list "$pass_start..HEAD" 2>/dev/null | tr '\n' ' ') "
  [ "$round_commits" != "  " ] || return 1
  while read -r sha location; do
    case "$round_commits" in *" $sha "*) ;; *) continue ;; esac
    subject=$(git -C "$dir" show -s --format=%s "$sha" 2>/dev/null)
    printf '%s %s (%s)' "$(printf '%s' "$sha" | cut -c1-9)" "$subject" "$location"
    return 0
  done < <(list_blamed_old_lines HEAD "$dir")
  return 1
}

# $1 is the earlier round's fix, $2 the directory.
deny_fix_of_a_fix() {
  print_pretooluse_deny "Blocked by the kc-gates plugin: inside the open review pass, this fix rewrites lines an earlier round's fix wrote ($1). A fix of a fix is where the review loop goes in circles: the loop-stop rule says stop and question the approach; ask the user: only their typed words approve it. When a message they typed on this branch says \"approve rework\", prefix the command with KC_REWORK_APPROVED=1; the token without those words stays blocked.$(needed_phrases_sentence "$2" "$APPROVAL_PHRASE")"
}

# Checks a `git commit`; $1 is the directory, the rest the words after `git`.
check_commit() {
  local pass_start round_line
  parse_git_command "$@"
  [ "${GIT_ARGS[0]:-}" = commit ] || return 0
  git -C "$GIT_DIR" rev-parse -q --verify HEAD >/dev/null 2>&1 || return 0
  pass_start=$(find_open_pass_start "$GIT_DIR")
  [ -n "$pass_start" ] || return 0
  # Only the merge as staged: `-a` would add edits the merge didn't bring.
  if is_default_branch_merge "$GIT_DIR" && ! is_commit_staging_all "${GIT_ARGS[@]:1}"; then
    return 0
  fi
  if is_commit_unjudgeable "$GIT_DIR" "${GIT_ARGS[@]:1}"; then
    print_pretooluse_deny "Blocked by the kc-gates plugin: $UNJUDGEABLE_COMMIT_REASON"
    return 1
  fi
  round_line=$(get_commit_diff "$GIT_DIR" -U0 "${GIT_ARGS[@]:1}" | drop_version_bump_hunks | find_fix_round_line "$GIT_DIR" "$pass_start") || return 0
  deny_fix_of_a_fix "$round_line" "$GIT_DIR"
  return 1
}

# Checks one shell segment of the command, run in directory $2.
check_segment() {
  local segment=$1 dir=$2 git_args_text git_words_list=()
  note_chain_segment "$segment" "$dir"
  git_args_text=$(git_words "$segment")
  [ -n "$git_args_text" ] || return 0
  read -ra git_words_list <<< "$git_args_text"
  check_commit "$dir" "${git_words_list[@]}"
}

main() {
  local input command dir
  input="$(cat)"
  command="$(extract_field "$input" command)"
  [ -n "$command" ] || exit 0
  dir="$(extract_field "$input" cwd)"
  case "$command" in
    *"$APPROVAL_TOKEN"*) ! user_approved "$(extract_field "$input" transcript_path)" "$APPROVAL_PHRASE" "${dir:-$PWD}" || exit 0 ;;
  esac
  walk_segments "$command" "${dir:-$PWD}" check_segment || true
  exit 0
}

main
