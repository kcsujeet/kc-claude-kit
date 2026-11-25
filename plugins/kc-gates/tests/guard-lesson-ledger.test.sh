#!/usr/bin/env bash
# Tests scripts/guard-lesson-ledger.sh: in a repo whose hand-off checklist has ledger: true, a push,
# gh pr create or gh pr merge on a feature branch is denied until the branch's ledger folder passes
# feedback-ledger.sh check and ticks every box of kc-look-back's Gate checklist. Real repos in a temp
# folder; each case runs with jq and through the sed fallback.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
scripts="$(dirname "$tests_dir")/scripts"
require_jq

run_git_in() { local repo=$1; shift; git -C "$repo" -c user.name=t -c user.email=t@example.test "$@"; }
make_repo() {
  local repo=$1 front_matter=$2
  git init -q -b main "$repo"
  mkdir -p "$repo/.claude"
  printf '%s\n\n# Checklist\n' "$front_matter" > "$repo/.claude/hand-off-checklist.md"
  run_git_in "$repo" add .
  run_git_in "$repo" commit -q -m base
  run_git_in "$repo" switch -q -c lesson-branch
}
lesson_repo="$work_dir/lesson"
make_repo "$lesson_repo" $'---\nledger: true\n---'
plain_repo="$work_dir/plain"
make_repo "$plain_repo" $'---\ndrafts: true\n---'
export KC_LEDGER_DIR="$work_dir/ledger"
check_verdict() { expect_hook_verdict "$scripts/guard-lesson-ledger.sh" "$1" "$2" "$3" "${4:-$lesson_repo}"; }

check_verdict allow "allowed: a command that is not a hand-off" "git status"
check_verdict allow "allowed: a push in a repo with no ledger in its checklist" "git push -u origin lesson-branch" "$plain_repo"

check_verdict deny "blocked: a push with no ledger folder" "git push -u origin lesson-branch"
expect_contains "it names the missing files" "is missing: feedback.tsv ledger.tsv checklist.md" "$last_hook_output"
check_verdict deny "blocked: gh pr create with no ledger folder" "gh pr create --fill"
check_verdict deny "blocked: gh pr merge with no ledger folder" "gh pr merge 5 --squash"
check_verdict allow "allowed: a push of the default branch" "git push origin main" "$work_dir"

mkdir -p "$KC_LEDGER_DIR"
printf 'F1\ttyped\tnew code had no precedent\n' > "$KC_LEDGER_DIR/feedback.tsv"
printf 'F1\tone-off\tthis one is settled for one file\n' > "$KC_LEDGER_DIR/ledger.tsv"
printf -- '- [x] §LB1 named without tokens\n- [x] §LB2 ladder\n- [ ] §LB3 examples\n- [x] §LB4 widened\n- [x] §LB5 class\n' > "$KC_LEDGER_DIR/checklist.md"
check_verdict deny "blocked: a Gate checklist box that is not ticked" "git push -u origin lesson-branch"
expect_contains "it names the box" "box §LB3 of the kc-look-back Gate checklist is not ticked" "$last_hook_output"

printf -- '- [x] §LB1 a\n- [x] §LB2 b\n- [x] §LB3 c\n- [x] §LB4 d\n- [x] §LB5 e\n' > "$KC_LEDGER_DIR/checklist.md"
printf 'F1\tone-off\tthis one is settled for one file\nF9\tone-off\tnot on the list\n' > "$KC_LEDGER_DIR/ledger.tsv"
check_verdict deny "blocked: a ledger that fails feedback-ledger.sh check" "git push -u origin lesson-branch"
expect_contains "it names the ledger problem" "feedback-ledger.sh check:" "$last_hook_output"

printf 'F1\tone-off\tthis one is settled for one file\n' > "$KC_LEDGER_DIR/ledger.tsv"
check_verdict allow "allowed: a complete ledger and every box ticked" "git push -u origin lesson-branch"
check_verdict allow "allowed: gh pr create with a complete ledger" "gh pr create --fill"
check_verdict allow "allowed: gh pr merge with a complete ledger" "gh pr merge 5 --squash"

# A repo with no base branch still reaches the ledger check (an empty argument list under set -u).
nobase_repo="$work_dir/nobase"
git init -q -b feature "$nobase_repo"
mkdir -p "$nobase_repo/.claude"
printf -- '---\nledger: true\n---\n' > "$nobase_repo/.claude/hand-off-checklist.md"
run_git_in "$nobase_repo" add .
run_git_in "$nobase_repo" commit -q -m base
printf 'F1\tone-off\tx\nF9\tone-off\tnot on the list\n' > "$KC_LEDGER_DIR/ledger.tsv"
check_verdict deny "blocked: a failing ledger is still checked in a repo with no base branch" "git push -u origin feature" "$nobase_repo"
expect_contains "it names the ledger problem" "feedback-ledger.sh check:" "$last_hook_output"
printf 'F1\tone-off\tx\n' > "$KC_LEDGER_DIR/ledger.tsv"
check_verdict allow "allowed: a complete ledger in a repo with no base branch" "git push -u origin feature" "$nobase_repo"

# Front matter that never closes does not make a lesson repo.
unclosed_repo="$work_dir/unclosed"
make_repo "$unclosed_repo" $'---\nledger: true'
check_verdict allow "allowed: a checklist whose front matter never closes" "git push -u origin lesson-branch" "$unclosed_repo"

finish
