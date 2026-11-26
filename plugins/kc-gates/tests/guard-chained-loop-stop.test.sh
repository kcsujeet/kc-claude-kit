#!/usr/bin/env bash
# Tests guard-loop-stop.sh for one command that stages then commits: it is judged on what it will
# commit. Real repos in a temp folder. Each hook case runs twice, once with jq and once through the
# sed fallback. Kept apart from guard-chained-commit.test.sh so each file runs inside a hook's time limit.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
scripts="$(dirname "$tests_dir")/scripts"
require_jq



# The loop-stop guard reads the same chain.
loop_repo="$work_dir/loop"
git init -q -b main "$loop_repo"
git init -q --bare "$loop_repo.git"
git -C "$loop_repo" remote add origin "$loop_repo.git"
printf 'a1\na2\na3\n' > "$loop_repo/f.txt"
printf 'n1\nn2\nn3\n' > "$loop_repo/notes.md"
run_git_in "$loop_repo" add .
run_git_in "$loop_repo" commit -q -m "fix f"
git -C "$loop_repo" push -q origin main
export KC_READY_DIR="$work_dir/receipts"
mkdir -p "$KC_READY_DIR"
printf 'rounds=1\n' > "$KC_READY_DIR/$(git -C "$loop_repo" rev-parse HEAD)"
loop_verdict() { expect_hook_verdict "$scripts/guard-loop-stop.sh" "$1" "$2" "$3" "$loop_repo"; }
printf 'a1\nchanged\na3\n' > "$loop_repo/f.txt"
loop_verdict deny "blocked: a chain that stages an edit of a receipted line" "git add f.txt && git commit -m again"
loop_verdict deny "blocked: a commit of a path that edits a receipted line" "git commit f.txt -m again"
loop_verdict deny "blocked: a build step before the staging" "./build.sh; git add f.txt && git commit -m again"
printf 'a1\nchanged\na3\n' > "$loop_repo/f.txt"
printf 'docs\n' > "$loop_repo/readme.md"
run_git_in "$loop_repo" add readme.md
loop_verdict deny "blocked: an index that holds only a small prose change does not excuse a chain that stages code" "git add f.txt && git commit -m again"
run_git_in "$loop_repo" reset -q
rm "$loop_repo/readme.md"
printf 'a1\na2\na3\n' > "$loop_repo/f.txt"
printf 'n1\nchanged\nn3\n' > "$loop_repo/notes.md"
loop_verdict deny "blocked: a chain that stages a small prose edit of a receipted line is graded in full" "git add notes.md && git commit -m again"
loop_verdict deny "blocked: a commit of a prose path that edits a receipted line is graded in full" "git commit notes.md -m again"
printf 'n1\nn2\nn3\n' > "$loop_repo/notes.md"
printf 'new\n' > "$loop_repo/new.txt"
loop_verdict allow "allowed: a chain that stages a new file" "git add new.txt && git commit -m new"
loop_verdict deny "blocked: a build step before staging a new file" "./build.sh; git add new.txt && git commit -m new"
unset KC_READY_DIR

finish
