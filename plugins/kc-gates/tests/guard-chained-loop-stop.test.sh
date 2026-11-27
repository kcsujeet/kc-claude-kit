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



# The loop-stop guard reads the same chain, inside an open review pass whose round 1 fixed line 2.
loop_repo="$work_dir/loop"
git init -q -b main "$loop_repo"
printf 'a1\na2\na3\n' > "$loop_repo/f.txt"
run_git_in "$loop_repo" add .
run_git_in "$loop_repo" commit -q -m "order totals"
export KC_READY_DIR="$work_dir/receipts" KC_PASS_ROOT="$work_dir/passes"
mkdir -p "$KC_READY_DIR" "$KC_PASS_ROOT/kc-pass-chain/round-1"
printf 'HEAD_SHA=%s\n' "$(git -C "$loop_repo" rev-parse HEAD)" > "$KC_PASS_ROOT/kc-pass-chain/round-1/meta.env"
printf 'a1\nround one\na3\n' > "$loop_repo/f.txt"
run_git_in "$loop_repo" commit -q -am "round 1 fix"
loop_verdict() { expect_hook_verdict "$scripts/guard-loop-stop.sh" "$1" "$2" "$3" "$loop_repo"; }
printf 'a1\nsecond round fix\na3\n' > "$loop_repo/f.txt"
loop_verdict deny "blocked: a chain that stages a rewrite of round 1's fix" "git add f.txt && git commit -m again"
loop_verdict deny "blocked: a commit of a path that rewrites round 1's fix" "git commit f.txt -m again"
loop_verdict deny "blocked: a build step before the staging" "./build.sh; git add f.txt && git commit -m again"
printf 'a1\nround one\na3\n' > "$loop_repo/f.txt"
printf 'new\n' > "$loop_repo/new.txt"
loop_verdict allow "allowed: a chain that stages a new file" "git add new.txt && git commit -m new"
loop_verdict deny "blocked: a build step before staging a new file" "./build.sh; git add new.txt && git commit -m new"
rm -rf "$KC_PASS_ROOT/kc-pass-chain"
loop_verdict allow "allowed: with no open pass, a build step before staging is not judged" "./build.sh; git add new.txt && git commit -m new"
unset KC_READY_DIR KC_PASS_ROOT

finish
