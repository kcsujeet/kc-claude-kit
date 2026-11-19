#!/usr/bin/env bash
# PreToolUse guard for Bash: a pull request merges only when every problem its review found is
# solved. On `gh pr merge`, for a pull request the signed-in user authored, it blocks unless the
# head commit has a clean kc-ready-for-review receipt (ready-receipt.sh check <sha> --clean): the
# last gate round found nothing, nothing was left open, and the head is that round's head.
# Someone else's pull request is theirs to merge by their own rules, so it is not checked.
#
# A command containing the literal KC_MERGE_APPROVED=1 passes only when the user's own words approve
# it: the latest message they typed in the session transcript (the payload's transcript_path)
# contains "approve merge" (user_approved in lib/hook-input.sh). The token without those words, no
# transcript, or a session with no typed message (a subagent) stays blocked.
#
# Everything the guard cannot read (no gh, no pull request, a failed lookup) is not blocked.
# Output: the PreToolUse deny JSON on a blocked command, nothing otherwise. Always exits 0.
# Hook schema: https://code.claude.com/docs/en/hooks

# shellcheck disable=SC2329 # walk_segments calls check_segment by name
set -u

scripts_dir=$(dirname "$0")
# shellcheck source=lib/hook-input.sh
. "$scripts_dir/lib/hook-input.sh"

readonly APPROVAL_TOKEN='KC_MERGE_APPROVED=1'
readonly APPROVAL_PHRASE='approve merge'

# Checks one shell segment, run in directory $2.
check_segment() {
  local segment=$1 dir=$2 gh_args_text gh_words_list=() pr_ref pr_fields head author me word
  gh_args_text=$(gh_words "$segment")
  read -ra gh_words_list <<< "$gh_args_text"
  [ "${gh_words_list[0]:-} ${gh_words_list[1]:-}" = "pr merge" ] || return 0
  pr_ref=""
  for word in "${gh_words_list[@]:2}"; do
    case "$word" in -*) ;; *) pr_ref=$word; break ;; esac
  done
  # shellcheck disable=SC2086 # an empty $pr_ref means the current branch's pull request
  pr_fields=$(cd "$dir" && gh pr view $pr_ref --json headRefOid,author --jq '.headRefOid + " " + .author.login' 2>/dev/null) || return 0
  read -r head author <<< "$pr_fields"
  me=$(gh api user --jq .login 2>/dev/null) || return 0
  [ -n "$head" ] && [ "$author" = "$me" ] || return 0
  bash "$scripts_dir/ready-receipt.sh" check "$head" --clean >/dev/null 2>&1 && return 0
  print_pretooluse_deny "Blocked by the kc-gates plugin: this pull request's head ($(printf '%s' "$head" | cut -c1-9)) has no clean review receipt: a pull request merges only when its last gate round found nothing and nothing is left open. Fix what is open and run the next round (kc-ready-for-review), or, past round 3, ask the user about the approach. Ask the user: only their typed words approve a merge with problems left. When their latest message says \"approve merge\", prefix the command with KC_MERGE_APPROVED=1; the token without those words stays blocked."
  return 1
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
