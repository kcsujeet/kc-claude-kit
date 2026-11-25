#!/usr/bin/env bash
# PreToolUse guard for Bash: a lesson PR ships with its ledger. In a repo whose
# .claude/hand-off-checklist.md front matter says `ledger: true`, `git push`, `gh pr create` and
# `gh pr merge` on a branch other than the default are denied until the branch's ledger folder
# passes `feedback-ledger.sh check` and ticks every box of kc-look-back's "## Gate checklist".
#
# The ledger folder is $KC_LEDGER_DIR, or <git dir>/kc-ledger/<branch, with / as ->/ and holds
# feedback.tsv (`feedback-ledger.sh list`), ledger.tsv (a verdict per item) and checklist.md (the
# gate checklist with each box ticked, `- [x] §LB1 ...`). The boxes are read from the kc-conventions
# plugin installed beside this one; with none found, checklist.md must hold a ticked box and no
# unticked one. The block names each missing file, unticked box or ledger problem.
#
# Output: the PreToolUse deny JSON on a blocked command, nothing otherwise. Always exits 0.
# KC_GUARD_NO_JQ=1 forces the sed fallback for reading the payload (used by the tests).

# shellcheck disable=SC2329 # walk_segments calls check_segment by name
set -u

scripts_dir=$(dirname "$0")
# shellcheck source=lib/hook-input.sh
. "$scripts_dir/lib/hook-input.sh"

# True when the repo's hand-off checklist front matter has `ledger: true`.
is_lesson_repo() {
  local checklist="$1/.claude/hand-off-checklist.md"
  [ -f "$checklist" ] || return 1
  awk '
    { is_first_line = (NR == 1); is_fence = ($0 == "---") }
    is_first_line && !is_fence { exit 1 }
    !is_first_line && is_fence { exit !found }
    /^ledger:[[:space:]]*true/ { found = 1 }' "$checklist"
}

# Prints the box ids ("§LB1" ...) of kc-look-back's Gate checklist, or nothing when it is not installed.
get_gate_checklist_ids() {
  local skill
  for skill in "$scripts_dir"/../../kc-conventions/skills/kc-look-back/SKILL.md "$scripts_dir"/../../../kc-conventions/*/skills/kc-look-back/SKILL.md; do
    [ -f "$skill" ] || continue
    awk '/^## Gate checklist/ { in_list = 1; next } /^## / { in_list = 0 } in_list && /^- \[[ xX]\] §/ { if (match($0, /§[A-Za-z]+[0-9]+/)) print substr($0, RSTART, RLENGTH) }' "$skill" | sort -u
    return 0
  done
}

# Prints each problem with the ledger folder $2 of the repo $1 on its own line.
get_ledger_problems() {
  local dir=$1 ledger_dir=$2 base_ref merge_base diff_file check_output check_summary check_args=() box_id missing_files="" file_name
  for file_name in feedback.tsv ledger.tsv checklist.md; do
    [ -f "$ledger_dir/$file_name" ] || missing_files="$missing_files $file_name"
  done
  if [ -n "$missing_files" ]; then
    echo "the ledger folder $ledger_dir is missing:$missing_files (run feedback-ledger.sh list, give each item a verdict, and tick the kc-look-back Gate checklist in checklist.md)"
    return 0
  fi
  for base_ref in origin/HEAD origin/main origin/master main master; do
    git -C "$dir" rev-parse --verify -q "$base_ref" > /dev/null && break
    base_ref=""
  done
  diff_file=$(mktemp)
  if [ -n "$base_ref" ]; then
    merge_base=$(git -C "$dir" merge-base "$base_ref" HEAD 2>/dev/null || echo "$base_ref")
    git -C "$dir" diff "$merge_base" HEAD > "$diff_file"
    check_args+=(--repo "$dir" --base "$merge_base")
  fi
  if ! check_output=$(cd "$dir" && bash "$scripts_dir/feedback-ledger.sh" check "$ledger_dir/feedback.tsv" "$ledger_dir/ledger.tsv" --diff "$diff_file" "${check_args[@]}" 2>&1); then
    check_summary=$(printf '%s' "$check_output" | tr '\n' ' ' | cut -c1-500)
    echo "feedback-ledger.sh check: $check_summary"
  fi
  rm -f "$diff_file"
  local ids
  ids=$(get_gate_checklist_ids)
  if [ -n "$ids" ]; then
    for box_id in $ids; do
      grep -Eq "^[[:space:]]*-[[:space:]]+\[[xX]\][[:space:]]+$box_id([^0-9]|$)" "$ledger_dir/checklist.md" || echo "box $box_id of the kc-look-back Gate checklist is not ticked in $ledger_dir/checklist.md"
    done
  else
    grep -Eq '^[[:space:]]*-[[:space:]]+\[[xX]\]' "$ledger_dir/checklist.md" || echo "no box is ticked in $ledger_dir/checklist.md"
    ! grep -Eq '^[[:space:]]*-[[:space:]]+\[ \]' "$ledger_dir/checklist.md" || echo "a box is unticked in $ledger_dir/checklist.md"
  fi
}

# Checks one shell segment of the command, run in directory $2.
check_segment() {
  local segment=$1 dir=$2 git_args_text git_words_list=() is_target=false repo_dir branch ledger_dir problems problem_summary
  git_args_text=$(git_words "$segment")
  if [ -n "$git_args_text" ]; then
    read -ra git_words_list <<< "$git_args_text"
    parse_git_command "$dir" "${git_words_list[@]}"
    [ "${GIT_ARGS[0]:-}" = push ] && is_target=true
    repo_dir=$GIT_DIR
  else
    repo_dir=$dir
  fi
  if printf '%s' "$segment" | grep -Eq "${GH_COMMAND_START}pr[[:space:]]+create([[:space:]]|$)" || is_merge_segment "$segment"; then is_target=true; fi
  $is_target || return 0
  is_lesson_repo "$repo_dir" || return 0
  branch=$(git -C "$repo_dir" rev-parse --abbrev-ref HEAD 2>/dev/null) || return 0
  case "$branch" in main | master | HEAD) return 0 ;; esac
  ledger_dir=${KC_LEDGER_DIR:-$(git -C "$repo_dir" rev-parse --absolute-git-dir)/kc-ledger/${branch//\//-}}
  problems=$(get_ledger_problems "$repo_dir" "$ledger_dir")
  [ -n "$problems" ] || return 0
  problem_summary=$(printf '%s' "$problems" | tr '\n' ' ' | sed 's/["\\]//g' | cut -c1-900)
  print_pretooluse_deny "Blocked by the kc-gates plugin: this is a lesson PR (the repo's hand-off checklist has ledger: true), and its ledger is not complete. $problem_summary"
  return 1
}

main() {
  local input command dir
  input="$(cat)"
  command="$(extract_field "$input" command)"
  [ -n "$command" ] || exit 0
  dir="$(extract_field "$input" cwd)"
  walk_segments "$command" "${dir:-$PWD}" check_segment || true
  exit 0
}

main
