#!/usr/bin/env bash
# PreToolUse guard for Bash: a new rule needs a check in the same commit. On `git commit` it reads
# the diff the commit records (the staged diff; `git commit -a` reads the working tree against
# HEAD). When the commit adds more non-blank lines than it removes in instruction files and adds or
# changes no check file, it is denied: a rule written as prose alone is not accepted.
#
#   - An instruction file is CLAUDE.md or AGENTS.md, anything under a .claude/rules/ folder,
#     .claude/review-conventions.md, .claude/hand-off-checklist.md, a SKILL.md under a skills/
#     folder, or a Markdown file directly in a rules/ folder.
#   - A check file is a script, hook, test, eval, CI workflow or lint-rule file (the same paths
#     feedback-ledger.sh check counts).
#   - Deletions and rewording pass: the count is added minus removed non-blank lines, over every
#     instruction file in the commit, and it must be above 0 to block.
#
# A command containing the literal KC_PROSE_APPROVED=1 passes. Like KC_READY_SKIP=1 it is added
# only when the user's latest message says prose alone is fine for this commit; the guard checks
# the literal, not the message.
#
# Output: the PreToolUse deny JSON on a blocked command, nothing otherwise. Always exits 0.
# Hook schema: https://code.claude.com/docs/en/hooks
#
# KC_GUARD_NO_JQ=1 forces the sed fallback for reading the payload (used by the tests).

set -u

# shellcheck source=lib/hook-input.sh
. "$(dirname "$0")/lib/hook-input.sh"

readonly APPROVAL_TOKEN='KC_PROSE_APPROVED=1'
readonly INSTRUCTION_PATHS='(^|/)(CLAUDE|AGENTS)\.md$|(^|/)\.claude/(rules/|review-conventions\.md$|hand-off-checklist\.md$)|(^|/)skills/(.*/)?SKILL\.md$|(^|/)rules/[^/]+\.md$'
readonly CHECK_PATHS='(^|/)(tests?|evals|hooks|scripts)/|(^|/)\.github/workflows/|\.(sh|bats)$|\.(test|spec)\.[A-Za-z]+$|_(test|spec)\.[A-Za-z]+$|(^|/)(biome\.json|eslint[^/]*|\.rubocop\.yml)$'

print_deny() {
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked by the kc-gates plugin: a new rule needs a check that blocks the mistake in the same commit (script, hook, test or CI); prose alone is not accepted. This commit adds rule lines to an instruction file and adds or changes no check file. Add the check, or, only when the user has said in their latest message that prose alone is fine here, prefix the command with KC_PROSE_APPROVED=1; never add it on your own."}}'
}

# Succeeds when the diff on stdin adds net non-blank lines to instruction files and changes no
# check file.
is_prose_only_rule() {
  KC_INSTRUCTIONS=$INSTRUCTION_PATHS KC_CHECKS=$CHECK_PATHS awk '
    /^\+\+\+ / { path = substr($0, 5); sub(/^b\//, "", path); instruction = (path ~ ENVIRON["KC_INSTRUCTIONS"]); if (path ~ ENVIRON["KC_CHECKS"]) checked = 1; next }
    /^--- / { if (substr($0, 5) ~ ENVIRON["KC_CHECKS"]) checked = 1; next }
    /^\+/ { if (instruction && $0 ~ /[^[:space:]+]/) net++ ; next }
    /^-/ { if (instruction && $0 ~ /[^[:space:]-]/) net-- }
    END { exit !(net > 0 && !checked) }'
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
    [ -n "$rest" ] || continue
    read -ra words <<< "$rest"
    parse_git_command "$dir" "${words[@]}"
    [ "${GIT_ARGS[0]:-}" = commit ] || continue
    if commit_diff "$GIT_DIR" -U0 "${GIT_ARGS[@]:1}" | is_prose_only_rule; then
      print_deny
      exit 0
    fi
  done <<EOF
$(split_segments "$command")
EOF
  exit 0
}

main
