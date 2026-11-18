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
#     request for it that merged in the last 7 days (gh api commits/<sha>/pulls). A lookup that
#     fails counts as not merged: the guard never blocks what it can't read.
# Lines the change only adds have no old side, and neither do new files.
#
# A command containing the literal KC_LOOP_APPROVED=1 passes. Like KC_READY_SKIP=1 it is added only
# when the user's latest message says to go on with the fix; the guard checks the literal, not the
# message.
#
# Output: the PreToolUse deny JSON on a blocked command, nothing otherwise. Always exits 0.
# Hook schema: https://code.claude.com/docs/en/hooks
#
# KC_GUARD_NO_JQ=1 forces the sed fallback for reading the payload (used by the tests).

set -u

scripts_dir=$(dirname "$0")
# shellcheck source=lib/hook-input.sh
. "$scripts_dir/lib/hook-input.sh"

readonly APPROVAL_TOKEN='KC_LOOP_APPROVED=1'
readonly HANDED_OFF_DAYS=7
readonly HANDED_OFF_SECONDS=$((HANDED_OFF_DAYS * 24 * 60 * 60))

# Prints "<sha> <path>:<line>" for each old-side line a diff changes, read as `git diff -U0`
# output on stdin; the blame is made at the revision $1 in the repository $2.
blamed_old_lines() {
  local rev=$1 dir=$2 path="" ranges="" line start count
  flush_file() {
    [ -n "$path" ] && [ -n "$ranges" ] || return 0
    # shellcheck disable=SC2086 # $ranges is a list of -L options
    git -C "$dir" blame --line-porcelain $ranges "$rev" -- "$path" 2>/dev/null \
      | awk -v path="$path" '/^[0-9a-f]{40} [0-9]+ [0-9]+/ { print $1, path ":" $2 }'
  }
  while IFS= read -r line; do
    case "$line" in
      "--- a/"*) flush_file; path=${line#--- a/}; ranges="" ;;
      "--- "*) flush_file; path=""; ranges="" ;;
      "@@ -"*)
        start=${line#@@ -}; start=${start%% *}
        count=1
        case "$start" in *,*) count=${start#*,}; start=${start%,*} ;; esac
        [ "$count" -gt 0 ] && ranges="$ranges -L $start,$((start + count - 1))"
        ;;
    esac
  done
  flush_file
}

# The default branch of the repository in $1 as a ref that exists, or nothing.
default_ref() {
  local dir=$1 ref
  ref=$(git -C "$dir" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null) || ref=""
  for ref in $ref origin/main origin/master main master; do
    git -C "$dir" rev-parse -q --verify "$ref^{commit}" >/dev/null 2>&1 && { printf '%s' "$ref"; return; }
  done
}

# True when commit $2 (in directory $1) reached the default branch $3 through a pull request that
# merged in the last HANDED_OFF_DAYS days.
merged_recently() {
  local dir=$1 sha=$2 default=$3 committed merged
  [ -n "$default" ] || return 1
  git -C "$dir" merge-base --is-ancestor "$sha" "$default" 2>/dev/null || return 1
  committed=$(git -C "$dir" show -s --format=%ct "$sha" 2>/dev/null) || return 1
  [ $(($(date +%s) - committed)) -le "$HANDED_OFF_SECONDS" ] || return 1
  merged=$(cd "$dir" && gh api "repos/{owner}/{repo}/commits/$sha/pulls" \
    --jq "[.[] | select(.merged_at != null and (.merged_at | fromdateiso8601) > (now - $HANDED_OFF_SECONDS))] | length" 2>/dev/null) || return 1
  [ "${merged:-0}" -gt 0 ]
}

# Prints "<sha> <subject>" of the first blamed commit that was already handed off, with the file
# and line, or nothing. $1 is the directory, $2 the revision to blame at, the diff is on stdin.
find_handed_off_fix() {
  local dir=$1 rev=$2 default sha location seen=" " subject
  default=$(default_ref "$dir")
  while read -r sha location; do
    case "$seen" in *" $sha "*) continue ;; esac
    seen="$seen$sha "
    if bash "$scripts_dir/ready-receipt.sh" check "$sha" >/dev/null 2>&1 || merged_recently "$dir" "$sha" "$default"; then
      subject=$(git -C "$dir" show -s --format=%s "$sha" 2>/dev/null)
      printf '%s %s (%s)' "$(printf '%s' "$sha" | cut -c1-9)" "$subject" "$location"
      return 0
    fi
  done < <(blamed_old_lines "$rev" "$dir")
  return 1
}

print_deny() {
  local reason="Blocked by the kc-gates plugin: this edits lines an earlier, already-handed-off fix wrote ($1): the loop-stop rule says stop and question the approach; ask the user. Only when the user has said in their latest message to go on, prefix the command with KC_LOOP_APPROVED=1; never add it on your own."
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' \
    "$(printf '%s' "$reason" | LC_ALL=C tr -d '\000-\037' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
}

# Checks a `git commit`; $1 is the directory, the rest the words after `git`.
check_commit() {
  local found
  parse_git_command "$@"
  [ "${GIT_ARGS[0]:-}" = commit ] || return 0
  # An unborn branch has no old side to blame.
  git -C "$GIT_DIR" rev-parse -q --verify HEAD >/dev/null 2>&1 || return 0
  found=$(commit_diff "$GIT_DIR" -U0 "${GIT_ARGS[@]:1}" | find_handed_off_fix "$GIT_DIR" HEAD) || return 0
  print_deny "$found"
  return 1
}

# Checks a `gh pr create`; $1 is the directory, the rest the words after `gh pr create`.
check_pr_create() {
  local dir=$1 word base="" take=false merge_base found ref
  shift
  for word in "$@"; do
    if $take; then base=$word; take=false; continue; fi
    case "$word" in
      -B | --base) take=true ;;
      --base=*) base=${word#--base=} ;;
    esac
  done
  ref=""
  for ref in ${base:+origin/$base $base} $(default_ref "$dir"); do
    git -C "$dir" rev-parse -q --verify "$ref^{commit}" >/dev/null 2>&1 && break
    ref=""
  done
  [ -n "$ref" ] || return 0
  merge_base=$(git -C "$dir" merge-base "$ref" HEAD 2>/dev/null) || return 0
  found=$(git -C "$dir" diff -U0 --no-color --no-ext-diff --no-renames "$merge_base" HEAD | find_handed_off_fix "$dir" "$merge_base") || return 0
  print_deny "$found"
  return 1
}

main() {
  local input command dir segment rest target words
  input="$(cat)"
  command="$(extract_field "$input" command)"
  [ -n "$command" ] || exit 0
  case "$command" in
    *"$APPROVAL_TOKEN"*) exit 0 ;;
  esac
  dir="$(extract_field "$input" cwd)"
  dir=${dir:-$PWD}
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
    rest=$(git_words "$segment")
    if [ -n "$rest" ]; then
      read -ra words <<< "$rest"
      check_commit "$dir" "${words[@]}" || exit 0
      continue
    fi
    rest=$(gh_words "$segment")
    read -ra words <<< "$rest"
    if [ "${words[0]:-} ${words[1]:-}" = "pr create" ]; then
      check_pr_create "$dir" "${words[@]:2}" || exit 0
    fi
  done <<EOF
$(split_segments "$command")
EOF
  exit 0
}

main
