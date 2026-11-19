#!/usr/bin/env bash
# PreToolUse guard for Bash: the loop-stop rule as a block. A fix of an earlier fix is where a
# change starts going in circles, so a commit or a PR whose changed lines were written by a commit
# that was already handed off stops until the user says to go on.
#
# On `git commit` and `gh pr create` it lists the lines the change touches (the staged diff for a
# commit, `git commit -a` reading the working tree against HEAD; the branch's diff from its
# merge-base with the base branch for a PR) and `git blame`s the old side of each changed line (at
# HEAD for a commit, at the merge-base for a PR). It blocks when a blamed commit was already handed
# off:
#   - it has a kc-ready-for-review receipt (ready-receipt.sh check), or
#   - it is on the default branch, was committed in the last 7 days, and GitHub lists a pull
#     request for it that merged in the last 7 days (gh api commits/<sha>/pulls).
# Everything the guard cannot read (no receipt folder, a failed lookup, no default branch) counts as
# not handed off: it never blocks what it can't read. Lines the change only adds have no old side,
# and neither do new files. A hunk whose changed lines only set a version (`"version": "1.2.0"`,
# `version = "1.2.0"`, `VERSION = "1.2.0"`) is left out: every release raises it, so it is not a
# fix being redone. A commit that concludes a merge of the default branch into a branch, taking the
# index as staged, is left out too: its staged diff is the default branch's own work, already handed
# off through its own PRs, plus any conflict resolutions, which are not checked. With -a it is checked.
#
# A command containing the literal KC_REWORK_APPROVED=1 passes only when the user's own words approve
# it: the latest message they typed in the session transcript (the payload's transcript_path)
# contains "approve rework" (user_approved in lib/hook-input.sh). The token without those words, no
# transcript, or a session with no typed message (a subagent) stays blocked.
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
readonly HANDED_OFF_DAYS=7
readonly HANDED_OFF_SECONDS=$((HANDED_OFF_DAYS * 24 * 60 * 60))
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

# The default branch of the repository in $1 as a ref that exists, or nothing.
get_default_branch_ref() {
  local dir=$1 remote_default candidate
  remote_default=$(git -C "$dir" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null) || remote_default=""
  for candidate in $remote_default origin/main origin/master main master; do
    git -C "$dir" rev-parse -q --verify "$candidate^{commit}" >/dev/null 2>&1 && { printf '%s' "$candidate"; return; }
  done
}

# True when commit $2 (in directory $1) reached the default branch $3 through a pull request that
# merged in the last HANDED_OFF_DAYS days. Each step fails to "not merged": a lookup that can't be
# made never blocks.
was_merged_recently() {
  local dir=$1 sha=$2 default_branch_ref=$3 committed merged_pull_count
  [ -n "$default_branch_ref" ] || return 1
  git -C "$dir" merge-base --is-ancestor "$sha" "$default_branch_ref" 2>/dev/null || return 1
  committed=$(git -C "$dir" show -s --format=%ct "$sha" 2>/dev/null) || return 1
  [ $(($(date +%s) - committed)) -le "$HANDED_OFF_SECONDS" ] || return 1
  merged_pull_count=$(cd "$dir" && gh api "repos/{owner}/{repo}/commits/$sha/pulls" \
    --jq "def merged_in_window: .merged_at != null and ((.merged_at | fromdateiso8601) > (now - $HANDED_OFF_SECONDS)); [.[] | select(merged_in_window)] | length" 2>/dev/null) || return 1
  [ "${merged_pull_count:-0}" -gt 0 ]
}

# Prints "<sha> <subject> (<file>:<line>)" of the first blamed commit that was already handed off,
# or nothing. $1 is the directory, $2 the revision to blame at; the diff is on stdin.
find_handed_off_fix() {
  local dir=$1 rev=$2 default_branch_ref sha location seen=" " subject
  default_branch_ref=$(get_default_branch_ref "$dir")
  while read -r sha location; do
    case "$seen" in *" $sha "*) continue ;; esac
    seen="$seen$sha "
    if bash "$scripts_dir/ready-receipt.sh" check "$sha" >/dev/null 2>&1 || was_merged_recently "$dir" "$sha" "$default_branch_ref"; then
      subject=$(git -C "$dir" show -s --format=%s "$sha" 2>/dev/null)
      printf '%s %s (%s)' "$(printf '%s' "$sha" | cut -c1-9)" "$subject" "$location"
      return 0
    fi
  done < <(list_blamed_old_lines "$rev" "$dir")
  return 1
}

deny_edit_of_handed_off_fix() {
  print_pretooluse_deny "Blocked by the kc-gates plugin: this edits lines an earlier, already-handed-off fix wrote ($1): the loop-stop rule says stop and question the approach; ask the user. Ask the user: only their typed words approve it. When their latest message says \"approve rework\", prefix the command with KC_REWORK_APPROVED=1; the token without those words stays blocked."
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

# Checks a `git commit`; $1 is the directory, the rest the words after `git`.
check_commit() {
  local handed_off_fix
  parse_git_command "$@"
  [ "${GIT_ARGS[0]:-}" = commit ] || return 0
  # An unborn branch has no old side to blame.
  git -C "$GIT_DIR" rev-parse -q --verify HEAD >/dev/null 2>&1 || return 0
  # Only the merge as staged: `-a` would add edits the merge didn't bring.
  if is_default_branch_merge "$GIT_DIR" && ! is_commit_staging_all "${GIT_ARGS[@]:1}"; then
    return 0
  fi
  handed_off_fix=$(get_commit_diff "$GIT_DIR" -U0 "${GIT_ARGS[@]:1}" | drop_version_bump_hunks | find_handed_off_fix "$GIT_DIR" HEAD) || return 0
  deny_edit_of_handed_off_fix "$handed_off_fix"
  return 1
}

# Checks a `gh pr create`; $1 is the directory, the rest the words after `gh pr create`.
check_pr_create() {
  local dir=$1 word base="" take=false merge_base handed_off_fix base_ref="" candidate_refs
  shift
  for word in "$@"; do
    if $take; then base=$word; take=false; continue; fi
    case "$word" in
      -B | --base) take=true ;;
      --base=*) base=${word#--base=} ;;
    esac
  done
  candidate_refs="${base:+origin/$base $base} $(get_default_branch_ref "$dir")"
  for base_ref in $candidate_refs; do
    git -C "$dir" rev-parse -q --verify "$base_ref^{commit}" >/dev/null 2>&1 && break
    base_ref=""
  done
  # No base or merge-base to compare with: nothing to blame, so nothing to block.
  [ -n "$base_ref" ] || return 0
  merge_base=$(git -C "$dir" merge-base "$base_ref" HEAD 2>/dev/null) || return 0
  handed_off_fix=$(git -C "$dir" diff -U0 --no-color --no-ext-diff --no-renames "$merge_base" HEAD | drop_version_bump_hunks | find_handed_off_fix "$dir" "$merge_base") || return 0
  deny_edit_of_handed_off_fix "$handed_off_fix"
  return 1
}

# Checks one shell segment of the command, run in directory $2.
check_segment() {
  local segment=$1 dir=$2 git_args_text gh_args_text git_words_list=() gh_words_list=()
  git_args_text=$(git_words "$segment")
  if [ -n "$git_args_text" ]; then
    read -ra git_words_list <<< "$git_args_text"
    check_commit "$dir" "${git_words_list[@]}"
    return
  fi
  gh_args_text=$(gh_words "$segment")
  read -ra gh_words_list <<< "$gh_args_text"
  if [ "${gh_words_list[0]:-} ${gh_words_list[1]:-}" = "pr create" ]; then
    check_pr_create "$dir" "${gh_words_list[@]:2}"
    return
  fi
  return 0
}

main() {
  local input command dir
  input="$(cat)"
  command="$(extract_field "$input" command)"
  [ -n "$command" ] || exit 0
  case "$command" in
    *"$APPROVAL_TOKEN"*) ! user_approved "$(extract_field "$input" transcript_path)" "$APPROVAL_PHRASE" || exit 0 ;;
  esac
  dir="$(extract_field "$input" cwd)"
  walk_segments "$command" "${dir:-$PWD}" check_segment || true
  exit 0
}

main
