#!/usr/bin/env bash
# Tests the guards of a publish for one command that commits, switches branch or pulls and then
# publishes (guard-lesson-ledger.sh, guard-hand-off.sh). Real repos in a temp folder. Each hook case
# runs twice, once with jq and once through the sed fallback.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
scripts="$(dirname "$tests_dir")/scripts"
require_jq

ledger_verdict() { expect_hook_verdict "$scripts/guard-lesson-ledger.sh" "$1" "$2" "$3" "${4:-$repo}"; }
hand_off_verdict() { expect_hook_verdict "$scripts/guard-hand-off.sh" "$1" "$2" "$3" "$repo"; }

repo="$work_dir/repo"
git init -q -b main "$repo"
mkdir -p "$repo/src" "$repo/.claude"
printf '# Rules\n\n- Name things by role.\n' > "$repo/CLAUDE.md"
printf 'export const total = 1\n' > "$repo/src/total.ts"
printf '#!/bin/sh\n' > "$repo/build.sh"
printf -- '---\nledger: true\n---\n\n# Hand-off\n' > "$repo/.claude/hand-off-checklist.md"
run_git_in "$repo" add .
run_git_in "$repo" commit -q -m base
reset_repo() { git -C "$repo" reset -q --hard HEAD; git -C "$repo" clean -qfd; }

# rm and mv change the working tree, so they are never replayed on the copy of the index.
# shellcheck source=../scripts/lib/hook-input.sh
(. "$scripts/lib/hook-input.sh"; note_chain_segment "git rm -q src/total.ts" "$repo"; get_commit_diff "$repo" -U0 -m x > /dev/null)
expect_eq "a git rm in the chain left the working file alone" "yes" "$([ -e "$repo/src/total.ts" ] && echo yes || echo no)"

# The lint check knows whether a lint command would run.
lint_status() { bash "$scripts/lint-changed-files.sh" --configured "$1" > /dev/null 2>&1 && echo 0 || echo 1; }
expect_eq "--configured: a repo with no lint config" 1 "$(lint_status "$repo")"
printf 'true\n' > "$repo/.claude/lint-command"
expect_eq "--configured: a repo with a lint command" 0 "$(lint_status "$repo")"
rm "$repo/.claude/lint-command"
expect_eq "--configured: a folder that is not a repo" 1 "$(lint_status "$work_dir")"

# One command that commits (or switches branch or pulls) then pushes is judged on a HEAD and branch from before it.
run_git_in "$repo" checkout -q -b lesson
ledger_verdict deny "blocked: commit then push in a ledger repo" "git commit -m x && git push -u origin lesson"
expect_contains "the block says to commit first" "Commit in one command" "$last_hook_output"
ledger_verdict deny "blocked: pull then push in a ledger repo" "git pull && git push -u origin lesson"
run_git_in "$repo" checkout -q main
ledger_verdict deny "blocked: a switch to a feature branch, then its push, from main" "git checkout -b lesson2 && git push -u origin lesson2"
run_git_in "$repo" checkout -q lesson
ledger_verdict deny "blocked: the push alone still needs its ledger" "git push -u origin lesson"
expect_not_contains "the plain push is refused for its ledger, not for the chain" "Commit in one command" "$last_hook_output"

# The same for the guard of a push that reads the receipt and the lint (guard-hand-off.sh).
remote="$work_dir/remote.git"
git init -q --bare "$remote"
run_git_in "$repo" remote add origin "$remote"
hand_off_verdict deny "blocked: commit then first push of a branch" "git commit -m x && git push -u origin lesson"
expect_contains "the hand-off block says to commit first" "Commit in one command" "$last_hook_output"
hand_off_verdict deny "blocked: the first push alone has no receipt" "git push -u origin lesson"
expect_not_contains "the plain first push is refused for its receipt" "Commit in one command" "$last_hook_output"
hand_off_verdict deny "blocked: commit then open a PR" "git commit -m x && gh pr create --fill"
expect_contains "the PR block says to commit first" "Commit in one command" "$last_hook_output"
# A branch the remote has needs the chain refused only when a lint would read the old commit.
run_git_in "$repo" push -q origin lesson
hand_off_verdict allow "allowed: commit then push of a branch the remote has, no lint configured" "git commit -m x && git push origin lesson"
printf 'true\n' > "$repo/.claude/lint-command"
hand_off_verdict deny "blocked: commit then push of a branch the remote has, with a lint configured" "git commit -m x && git push origin lesson"
rm "$repo/.claude/lint-command"

finish
