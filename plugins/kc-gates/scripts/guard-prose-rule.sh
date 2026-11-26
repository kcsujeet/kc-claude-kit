#!/usr/bin/env bash
# PreToolUse guard for Bash: a new rule needs a check in the same commit. On `git commit` it reads
# the diff the commit records (the staged diff; `git commit -a` reads the working tree against
# HEAD). When the commit adds more non-blank lines than it removes in instruction files and adds or
# changes no check file, it is denied: a rule written as prose alone is not accepted.
#
#   - An instruction file is CLAUDE.md or AGENTS.md, anything under a .claude/rules/ folder,
#     .claude/review-conventions.md, .claude/hand-off-checklist.md, a SKILL.md under a skills/
#     folder, or a Markdown file directly in a rules/ folder.
#   - A check file is a script, hook, test, eval, CI workflow or lint-rule file (KC_CHECK_PATHS in
#     lib/risk-paths.sh, the list feedback-ledger.sh check reads too).
#   - Deletions and rewording pass: the count is added minus removed non-blank lines, over every
#     instruction file in the commit, and it must be above 0 to block.
#
# A commit staged by the same command (`git add -A && git commit`, `git commit <paths>`) is judged on
# what it will commit (get_commit_diff in lib/hook-input.sh), not on the index as it is now.
#
# While concluding a merge, added lines the default branch already has are not counted: only lines
# this branch itself introduces (drop_carried_in_lines).
#
# A command containing the literal KC_PROSE_APPROVED=1 passes only when the user's own words approve
# it: the latest message they typed in the session transcript (the payload's transcript_path)
# contains "approve prose" (user_approved in lib/hook-input.sh). The token without those words, no
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
# shellcheck source=lib/risk-paths.sh
. "$scripts_dir/lib/risk-paths.sh"

readonly APPROVAL_TOKEN='KC_PROSE_APPROVED=1'
readonly APPROVAL_PHRASE='approve prose'
readonly INSTRUCTION_PATHS='(^|/)(CLAUDE|AGENTS)\.md$|(^|/)\.claude/(rules/|review-conventions\.md$|hand-off-checklist\.md$)|(^|/)skills/(.*/)?SKILL\.md$|(^|/)rules/[^/]+\.md$'

# $1 is the repository the commit runs in.
deny_prose_only_rule() {
  print_pretooluse_deny "Blocked by the kc-gates plugin: a new rule needs a check that blocks the mistake in the same commit (script, hook, test or CI); prose alone is not accepted. This commit adds rule lines to an instruction file and adds or changes no check file. Add the check, or ask the user: only their typed words approve prose alone. When their latest message says \"approve prose\", prefix the command with KC_PROSE_APPROVED=1; the token without those words stays blocked.$(needed_phrases_sentence "$1" "$APPROVAL_PHRASE")"
}

# Drops the added lines of a `git diff -U0` (stdin) that a merge only carries in: lines already in that
# file at the default branch, or at the merged commit when the default branch has it. Git reads each
# reviewed file into a scratch file, so a path reaches no shell.
drop_carried_in_lines() {
  local dir=$1 reviewed_refs ref scratch changed_path file_number=0
  if ! git -C "$dir" rev-parse -q --verify MERGE_HEAD > /dev/null 2>&1; then
    cat
    return
  fi
  reviewed_refs=$(get_default_branch_ref "$dir")
  if is_default_branch_merge "$dir"; then
    reviewed_refs="$reviewed_refs $(git -C "$dir" rev-parse MERGE_HEAD)"
  fi
  scratch=$(mktemp -d)
  cat > "$scratch/diff"
  while IFS= read -r changed_path; do
    file_number=$((file_number + 1))
    # shellcheck disable=SC2086 # $reviewed_refs is a list of refs
    for ref in $reviewed_refs; do git -C "$dir" show "$ref:$changed_path" 2> /dev/null; done > "$scratch/$file_number"
  # The awk below numbers the files by the same header test, so both lists stay in step.
  done < <(awk '/^diff --git / { in_header = 1 } /^@@/ { in_header = 0 } in_header && /^\+\+\+ b\// { print substr($0, 7) }' "$scratch/diff")
  awk -v scratch="$scratch" '
    /^diff --git / { in_header = 1; delete reviewed_lines }
    /^@@/ { in_header = 0 }
    in_header && /^\+\+\+ b\// {
      reviewed_file = scratch "/" ++file_number
      while ((getline line < reviewed_file) > 0) reviewed_lines[line] = 1
      close(reviewed_file)
    }
    !in_header && /^\+/ {
      line_text = substr($0, 2)
      is_carried_in = line_text in reviewed_lines
      if (is_carried_in) next
    }
    { print }' "$scratch/diff"
  rm -rf "$scratch"
}

# Succeeds when the `git diff -U0` on stdin adds net non-blank lines to instruction files and
# changes no check file. A `--- ` or `+++ ` line is a file header only between a `diff --git` line and
# its first hunk; anywhere else it is a removed or added line that starts with `-- ` or `++ `.
is_prose_only_rule() {
  KC_INSTRUCTIONS=$INSTRUCTION_PATHS KC_CHECKS=$KC_CHECK_PATHS awk '
    /^diff --git / { in_header = 1; is_instruction_file = 0; next }
    /^@@/ { in_header = 0; next }
    in_header && /^--- / { if (substr($0, 5) ~ ENVIRON["KC_CHECKS"]) changes_check_file = 1; next }
    in_header && /^\+\+\+ / {
      path = substr($0, 5); sub(/^b\//, "", path)
      is_instruction_file = (path ~ ENVIRON["KC_INSTRUCTIONS"])
      if (path ~ ENVIRON["KC_CHECKS"]) changes_check_file = 1
      next
    }
    in_header { next }
    /^\+/ { if (is_instruction_file && substr($0, 2) ~ /[^[:space:]]/) net_added++; next }
    /^-/ { if (is_instruction_file && substr($0, 2) ~ /[^[:space:]]/) net_added-- }
    END { has_net_addition = (net_added > 0); exit !(has_net_addition && !changes_check_file) }'
}

# Checks one shell segment of the command, run in directory $2.
check_segment() {
  local segment=$1 dir=$2 git_args_text git_words_list=()
  note_chain_segment "$segment" "$dir"
  git_args_text=$(git_words "$segment")
  [ -n "$git_args_text" ] || return 0
  read -ra git_words_list <<< "$git_args_text"
  parse_git_command "$dir" "${git_words_list[@]}"
  [ "${GIT_ARGS[0]:-}" = commit ] || return 0
  if is_commit_unjudgeable; then
    print_pretooluse_deny "Blocked by the kc-gates plugin: $UNJUDGEABLE_COMMIT_REASON"
    return 1
  fi
  if get_commit_diff "$GIT_DIR" -U0 "${GIT_ARGS[@]:1}" | drop_carried_in_lines "$GIT_DIR" | is_prose_only_rule; then
    deny_prose_only_rule "$GIT_DIR"
    return 1
  fi
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
