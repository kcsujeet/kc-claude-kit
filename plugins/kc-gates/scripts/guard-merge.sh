#!/usr/bin/env bash
# PreToolUse guard for Bash: a pull request merges only when every problem its review found is
# solved. On `gh pr merge`, for a pull request the signed-in user authored, it blocks unless the
# head commit has a clean kc-ready-for-review receipt (ready-receipt.sh check <sha> --clean): the
# last gate round found nothing, nothing was left open, and the head is that round's head.
# Someone else's pull request is theirs to merge by their own rules, so it is not checked.
#
# A command containing the literal KC_MERGE_APPROVED=1 passes only when the user's own words approve
# it: a message they typed on this branch in the session transcript (the payload's transcript_path)
# contains "approve merge" (user_approved in lib/hook-input.sh). The token without those words, no
# transcript, or a session with no typed message (a subagent) stays blocked.
#
# A pull request whose change from its base is prose_small (change-class.sh: a few prose lines and
# nothing else) or code_small (small, no risk: line), its head and base read in this clone, needs
# no receipt: it merges once every check
# GitHub lists for it has passed (or with --auto, which waits for them). A head this clone doesn't
# have is classed full.
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
readonly SHORT_SHA_LENGTH=9
readonly MERGE_SUBCOMMAND_WORDS=2 # "pr merge"
# The checks of the pull request that have not passed: failed, cancelled or still running.
readonly UNPASSED_CHECKS='[.statusCheckRollup[]? | (.conclusion // .state // "") | ascii_upcase | select(. != "SUCCESS" and . != "NEUTRAL" and . != "SKIPPED")] | length | tostring'

# Prints the class (change-class.sh) of the pull request's change in directory $1: head $2, base
# branch $3. full when this clone lacks either.
read_pull_request_class() {
  local dir=$1 head=$2 base_branch=$3 base_ref merge_base
  git -C "$dir" rev-parse -q --verify "$head^{commit}" >/dev/null 2>&1 || { printf full; return; }
  for base_ref in "origin/$base_branch" "$base_branch"; do
    merge_base=$(git -C "$dir" merge-base "$base_ref" "$head" 2>/dev/null) && break
    merge_base=""
  done
  [ -n "$merge_base" ] || { printf full; return; }
  read_change_class "$dir" --base "$merge_base" --head "$head"
}

# Prints "<pr ref>|<repo>" for a merge segment's words (after `gh`): the pull request's number or
# branch (empty: the current branch's) and the -R/--repo value (empty: the directory's repo).
# A flag's value is never read as the ref; a `gh api` merge reads both from its endpoint.
get_merge_target() {
  local words=("$@") word pending_flag="" pr_ref="" repo="" endpoint
  if [ "${words[0]:-}" = api ]; then
    endpoint=$(printf '%s\n' "${words[@]}" | grep -Eo 'repos/[^/[:space:]]+/[^/[:space:]]+/pulls/[0-9]+/merge' | head -n 1)
    endpoint=${endpoint#repos/}
    repo=${endpoint%%/pulls/*}
    # gh api fills {owner}/{repo} from the directory, gh pr view does not: leave the repo to it.
    [[ $repo != *"{"* ]] || repo=""
    pr_ref=${endpoint#*/pulls/}
    pr_ref=${pr_ref%/merge}
    printf '%s|%s' "$pr_ref" "$repo"
    return
  fi
  for word in "${words[@]:MERGE_SUBCOMMAND_WORDS}"; do
    if [ -n "$pending_flag" ]; then
      [ "$pending_flag" != repo ] || repo=$word
      pending_flag=""
      continue
    fi
    case "$word" in
      -R | --repo) pending_flag=repo ;;
      -t | --subject | -b | --body | -F | --body-file | -A | --author-email | --match-head-commit) pending_flag=value ;;
      --repo=*) repo=${word#--repo=} ;;
      -*) ;;
      *) [ -n "$pr_ref" ] || pr_ref=$word ;;
    esac
  done
  printf '%s|%s' "$pr_ref" "$repo"
}

# Checks one shell segment, run in directory $2.
check_segment() {
  local segment=$1 dir=$2 gh_words_list=() merge_target pr_ref repo pr_fields head author base_branch unpassed_checks me has_head=false is_by_me=false is_own_pull_request=false change_class
  is_merge_segment "$segment" || return 0
  read -ra gh_words_list <<< "$(gh_words "$segment")"
  # Split on the separator by hand: an empty ref before a --repo value stays empty.
  merge_target=$(get_merge_target "${gh_words_list[@]}")
  pr_ref=${merge_target%%|*}
  repo=${merge_target#*|}
  # shellcheck disable=SC2086 # an empty $pr_ref means the current branch's pull request
  pr_fields=$(cd "$dir" && gh pr view $pr_ref ${repo:+--repo "$repo"} --json headRefOid,author,baseRefName,statusCheckRollup --jq ".headRefOid + \" \" + .author.login + \" \" + .baseRefName + \" \" + ($UNPASSED_CHECKS)" 2>/dev/null) || return 0
  read -r head author base_branch unpassed_checks <<< "$pr_fields"
  me=$(gh api user --jq .login 2>/dev/null) || return 0
  [ -n "$head" ] && has_head=true
  [ "$author" = "$me" ] && is_by_me=true
  $has_head && $is_by_me && is_own_pull_request=true
  $is_own_pull_request || return 0
  change_class=$(read_pull_request_class "$dir" "$head" "${base_branch:-}")
  if is_small_class "$change_class"; then
    [ "${unpassed_checks:-0}" = 0 ] && return 0
    printf '%s\n' "${gh_words_list[@]}" | grep -qx -- '--auto' && return 0
    print_pretooluse_deny "Blocked by the kc-gates plugin: this pull request is small with no risk line (change-class.sh: $change_class), so it merges with no review receipt, but only once its checks pass: $unpassed_checks of them have not passed yet. Wait for them (gh pr checks), fix a failure, then merge; or merge with --auto, which waits for them. No user approval is needed."
    return 1
  fi
  # In the pull request's repo: a merge of the default branch into a clean head counts as clean.
  (cd "$dir" && bash "$scripts_dir/ready-receipt.sh" check "$head" --clean >/dev/null 2>&1) && return 0
  print_pretooluse_deny "Blocked by the kc-gates plugin: this pull request's head (${head:0:$SHORT_SHA_LENGTH}) has no clean review receipt: a pull request merges only when its last gate round found nothing and nothing is left open. Fix what is open and review the fixes as the next round (kc-ready-for-review), or, when the rounds are used up, ask the user about the approach. Ask the user: only their typed words approve a merge with problems left. When a message they typed on this branch says \"approve merge\", prefix the command with KC_MERGE_APPROVED=1; the token without those words stays blocked.$(needed_phrases_sentence "$dir" "$APPROVAL_PHRASE")"
  return 1
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
