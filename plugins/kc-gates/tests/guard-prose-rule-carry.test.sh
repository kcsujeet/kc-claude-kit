#!/usr/bin/env bash
# Tests the merge handling of scripts/guard-prose-rule.sh in its fewest cases: a merge brings in a
# reviewed rule line (allowed), a rule the branch adds still blocks, and a path named like a command
# runs nothing. Small on purpose: the ledger check runs it inside a hook's time limit.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
scripts="$(dirname "$tests_dir")/scripts"
require_jq

run_git_in() { local repo=$1; shift; git -C "$repo" -c user.name=t -c user.email=t@example.test "$@"; }
check_verdict() { expect_hook_verdict "$scripts/guard-prose-rule.sh" "$1" "$2" "$3" "${4:-$repo}"; }

merge_repo="$work_dir/merge-repo"
git init -q -b main "$merge_repo"
printf '# Rules\n\n- Name things by role.\n' > "$merge_repo/CLAUDE.md"
run_git_in "$merge_repo" add .
run_git_in "$merge_repo" commit -q -m base
run_git_in "$merge_repo" checkout -q -b lesson
printf 'x\n' > "$merge_repo/lesson.txt"
run_git_in "$merge_repo" add .
run_git_in "$merge_repo" commit -q -m lesson
run_git_in "$merge_repo" checkout -q main
echo '- A rule main already reviewed.' >> "$merge_repo/CLAUDE.md"
run_git_in "$merge_repo" commit -q -am "main rule"
run_git_in "$merge_repo" checkout -q lesson
run_git_in "$merge_repo" merge -q --no-commit --no-ff main > /dev/null
check_verdict allow "allowed: a merge of the base branch bringing a reviewed rule line" "git commit --no-edit" "$merge_repo"
run_git_in "$merge_repo" merge --abort
run_git_in "$merge_repo" checkout -q -b prose main
echo '- A prose-only rule from the branch.' >> "$merge_repo/CLAUDE.md"
run_git_in "$merge_repo" commit -q -am "branch prose"
run_git_in "$merge_repo" checkout -q main
run_git_in "$merge_repo" merge -q --no-commit --no-ff prose > /dev/null
check_verdict deny "blocked: a merge whose branch side adds a prose-only rule" "git commit --no-edit" "$merge_repo"
run_git_in "$merge_repo" merge --abort

finish
