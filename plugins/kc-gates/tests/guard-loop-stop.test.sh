#!/usr/bin/env bash
# Tests scripts/guard-loop-stop.sh: armed only while a kc-ready-for-human-review pass is open on the
# branch, it denies a `git commit` that rewrites lines an earlier fix round of that pass wrote,
# unless the command carries KC_REWORK_APPROVED=1 and the user typed "approve rework". Outside a
# pass, after its receipt, or for lines the pass did not write, it never blocks. Real repos in a temp
# folder, pass folders under KC_PASS_ROOT and receipts under KC_READY_DIR written by hand. Each case
# runs twice, once with jq and once through the sed fallback.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
scripts="$(dirname "$tests_dir")/scripts"
require_jq
export KC_READY_DIR="$work_dir/receipts" KC_PASS_ROOT="$work_dir/passes"
mkdir -p "$KC_READY_DIR" "$KC_PASS_ROOT"

run_git_in() { local repo=$1; shift; git -C "$repo" -c user.name=t -c user.email=t@example.test "$@"; }
write_lines() { local file=$1 prefix=$2 i; for i in 1 2 3 4 5 6; do echo "$prefix$i"; done > "$file"; }
# Replaces line $3 of file $2 in repo $1 with $4 (default "changed").
edit_line() { sed "$3s/.*/${4:-changed}/" "$1/$2" > "$work_dir/edit.tmp" && mv "$work_dir/edit.tmp" "$1/$2"; }
reset_repo() { git -C "$1" reset -q --hard HEAD; }
# Opens a pass whose round 1 reviewed commit $2: the folder gather-review.sh writes, round-1/meta.env.
open_pass() { mkdir -p "$KC_PASS_ROOT/kc-pass-$1/round-1"; printf 'HEAD_SHA=%s\nBASE=main\n' "$2" > "$KC_PASS_ROOT/kc-pass-$1/round-1/meta.env"; }
close_all_passes() { rm -rf "${KC_PASS_ROOT:?}"/kc-pass-*; }
check_verdict() { expect_hook_verdict "$scripts/guard-loop-stop.sh" "$@"; }

# The change under review: f.txt and a version file, then a round-1 fix of line 2.
repo="$work_dir/repo"
git init -q -b main "$repo"
write_lines "$repo/f.txt" a
printf '{\n  "version": "1.0.0"\n}\n' > "$repo/plugin.json"
run_git_in "$repo" add f.txt plugin.json
run_git_in "$repo" commit -q -m "order totals"
reviewed_sha=$(git -C "$repo" rev-parse HEAD)

# Outside any pass nothing is blocked, whatever wrote the line.
edit_line "$repo" f.txt 2
run_git_in "$repo" add f.txt
check_verdict allow "loop-stop-pass: outside a review pass, editing any line is allowed" "git commit -m 'edit'" "$repo"
reset_repo "$repo"

open_pass round "$reviewed_sha"
edit_line "$repo" f.txt 2 "round one"
run_git_in "$repo" add f.txt
check_verdict allow "loop-stop-pass: round 1 fixing the reviewed change is allowed" "git commit -m 'round 1 fix'" "$repo"
run_git_in "$repo" commit -q -m "round 1 fix"
round_one_sha=$(git -C "$repo" rev-parse HEAD)

edit_line "$repo" f.txt 2 "second round fix"
run_git_in "$repo" add f.txt
check_verdict deny "loop-stop-pass: a later round rewriting round 1's fix is blocked" "git commit -m 'round 2 fix'" "$repo"
expect_contains "loop-stop-pass: the message names the loop-stop rule" "the loop-stop rule says stop and question the approach; ask the user" "$last_hook_output"
expect_contains "loop-stop-pass: the message names the earlier round's fix" "${round_one_sha:0:9} round 1 fix (f.txt:2)" "$last_hook_output"
expect_token_needs_typed_words "$scripts/guard-loop-stop.sh" KC_REWORK_APPROVED=1 "approve rework" "git commit -m 'round 2 fix'" "$repo"
check_verdict deny "loop-stop-pass: cd into the repo first" "cd $repo && git commit -m 'round 2 fix'" "$work_dir"
check_verdict deny "loop-stop-pass: git -C <repo> commit" "git -C $repo commit -m 'round 2 fix'" "$work_dir"
check_verdict allow "loop-stop-pass: a command that is not a commit" "git status" "$repo"
reset_repo "$repo"

edit_line "$repo" f.txt 4
run_git_in "$repo" add f.txt
check_verdict allow "loop-stop-pass: a later round editing a line no round wrote is allowed" "git commit -m 'round 2 other'" "$repo"
reset_repo "$repo"

edit_line "$repo" f.txt 2 "second round fix"
check_verdict allow "loop-stop-pass: an unstaged edit, plain commit" "git commit -m 'nothing staged'" "$repo"
check_verdict deny "loop-stop-pass: git commit -a reads the unstaged edit" "git commit -a -m 'all'" "$repo"
reset_repo "$repo"

sed 's/1\.0\.0/1.0.1/' "$repo/plugin.json" > "$work_dir/p.tmp" && mv "$work_dir/p.tmp" "$repo/plugin.json"
run_git_in "$repo" commit -q -am "round 1 bump"
sed 's/1\.0\.1/1.0.2/' "$repo/plugin.json" > "$work_dir/p.tmp" && mv "$work_dir/p.tmp" "$repo/plugin.json"
run_git_in "$repo" add plugin.json
check_verdict allow "loop-stop-pass: raising a version a round set is allowed" "git commit -m 'bump again'" "$repo"
reset_repo "$repo"

# The receipt ends the pass: a reviewer's later requests are no agent loop.
printf 'rounds=2\n' > "$KC_READY_DIR/$(git -C "$repo" rev-parse HEAD)"
edit_line "$repo" f.txt 2 "reviewer asked"
run_git_in "$repo" add f.txt
check_verdict allow "loop-stop-pass: after the pass's receipt, editing a round's fix is allowed" "git commit -m 'review feedback'" "$repo"
reset_repo "$repo"
rm -f "$KC_READY_DIR"/*

# A pass of another branch, whose reviewed commit this branch doesn't hold, arms nothing here.
close_all_passes
open_pass other 0123456789abcdef0123456789abcdef01234567
edit_line "$repo" f.txt 2 "second round fix"
run_git_in "$repo" add f.txt
check_verdict allow "loop-stop-pass: a pass of another branch does not arm the guard" "git commit -m 'edit'" "$repo"
reset_repo "$repo"
close_all_passes

finish
