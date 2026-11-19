#!/usr/bin/env bash
# Tests scripts/guard-prose-rule.sh: a `git commit` that adds net lines to an instruction file and
# changes no check file is denied unless the command carries KC_PROSE_APPROVED=1 and the user typed "approve prose". Real repos in a
# temp folder. Each case runs twice, once with jq and once through the sed fallback.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
scripts="$(dirname "$tests_dir")/scripts"
require_jq

run_git_in() { local repo=$1; shift; git -C "$repo" -c user.name=t -c user.email=t@example.test "$@"; }
repo="$work_dir/repo"
git init -q -b main "$repo"
mkdir -p "$repo/src" "$repo/plugin/skills/shop" "$repo/.claude/rules" "$repo/docs"
printf '# Rules\n\n- Name things by role.\n- Keep functions short.\n-- old note\n' > "$repo/CLAUDE.md"
printf 'export const total = 1\n' > "$repo/src/total.ts"
printf 'notes\n' > "$repo/docs/notes.md"
run_git_in "$repo" add .
run_git_in "$repo" commit -q -m base
reset_repo() { git -C "$repo" reset -q --hard HEAD; git -C "$repo" clean -qfd; mkdir -p "$repo/plugin/skills/shop" "$repo/.claude/rules"; }

check_verdict() { expect_hook_verdict "$scripts/guard-prose-rule.sh" "$1" "$2" "$3" "${4:-$repo}"; }

echo '- Prefer early returns.' >> "$repo/CLAUDE.md"
run_git_in "$repo" add CLAUDE.md
check_verdict deny "blocked: a CLAUDE.md rule with no check" "git commit -m 'rule'"
expect_contains "the message names the missing check" "a new rule needs a check that blocks the mistake in the same commit (script, hook, test or CI); prose alone is not accepted" "$last_hook_output"
expect_token_needs_typed_words "$scripts/guard-prose-rule.sh" KC_PROSE_APPROVED=1 "approve prose" "git commit -m 'rule'" "$repo"
check_verdict deny "blocked: git -C <repo> commit" "git -C $repo commit -m 'rule'" "$work_dir"
check_verdict deny "blocked: cd into the repo, then commit" "cd $repo && git commit -m 'rule'" "$work_dir"
check_verdict allow "allowed: a command that is not a commit" "git status"
printf 'test -n 1\n' > "$repo/src/total.test.ts"
run_git_in "$repo" add src/total.test.ts
check_verdict allow "allowed: the same commit with a test file" "git commit -m 'rule and test'"
reset_repo

echo '- Prefer early returns.' >> "$repo/CLAUDE.md"
printf '#!/bin/sh\n' > "$repo/scripts-check.sh"
run_git_in "$repo" add .
check_verdict allow "allowed: the rule with a script file" "git commit -m 'rule and script'"
reset_repo

echo '- Prefer early returns.' >> "$repo/CLAUDE.md"
mkdir -p "$repo/.github/workflows"
printf 'name: ci\n' > "$repo/.github/workflows/ci.yml"
run_git_in "$repo" add .
check_verdict allow "allowed: the rule with a CI workflow" "git commit -m 'rule and ci'"
reset_repo

printf '# Shop\n\nSteps.\n' > "$repo/plugin/skills/shop/SKILL.md"
run_git_in "$repo" add .
check_verdict deny "blocked: a new SKILL.md with no check" "git commit -m 'skill'"
reset_repo

printf -- '- A rule.\n' > "$repo/.claude/rules/naming.md"
run_git_in "$repo" add .
check_verdict deny "blocked: a new .claude/rules file with no check" "git commit -m 'rules'"
reset_repo

printf '# Rules\n\n- Name things by role.\n' > "$repo/CLAUDE.md"
run_git_in "$repo" add CLAUDE.md
check_verdict allow "allowed: a deletion-only edit of an instruction file" "git commit -m 'drop a rule'"
reset_repo

sed 's/Keep functions short\./Keep functions small./' "$repo/CLAUDE.md" > "$work_dir/reword" && mv "$work_dir/reword" "$repo/CLAUDE.md"
run_git_in "$repo" add CLAUDE.md
check_verdict allow "allowed: a reworded line, no net new rule" "git commit -m 'reword'"
reset_repo

echo 'more notes' >> "$repo/docs/notes.md"
echo 'export const more = 2' >> "$repo/src/total.ts"
run_git_in "$repo" add .
check_verdict allow "allowed: added lines in files that are not instruction files" "git commit -m 'notes'"
reset_repo

echo '- Prefer early returns.' >> "$repo/CLAUDE.md"
check_verdict allow "allowed: an unstaged rule, plain commit" "git commit -m 'nothing staged'"
check_verdict deny "blocked: git commit -a reads the unstaged rule" "git commit -a -m 'all'"
check_verdict deny "blocked: git commit -am reads the unstaged rule" "git commit -am all"
reset_repo

# A removed line that starts with `-- ` is a removed line, not a file header, and an added one that
# starts with `++ ` is an added line.
grep -v '^-- old note' "$repo/CLAUDE.md" > "$work_dir/claude" && mv "$work_dir/claude" "$repo/CLAUDE.md"
echo '- Prefer early returns.' >> "$repo/CLAUDE.md"
run_git_in "$repo" add CLAUDE.md
check_verdict allow "allowed: one rule line swapped for a removed '-- ' line, no net new rule" "git commit -m 'swap'"
reset_repo
echo '++ a rule written like a header' >> "$repo/CLAUDE.md"
run_git_in "$repo" add CLAUDE.md
check_verdict deny "blocked: an added '++ ' line is a rule line, not a file header" "git commit -m 'plus'"
reset_repo

# Every kind of instruction file.
for instruction_file in AGENTS.md .claude/review-conventions.md .claude/hand-off-checklist.md rules/naming.md; do
  mkdir -p "$repo/$(dirname "$instruction_file")"
  echo '- A rule.' > "$repo/$instruction_file"
  run_git_in "$repo" add .
  check_verdict deny "blocked: a new rule line in $instruction_file with no check" "git commit -m 'rule'"
  reset_repo
done

finish
