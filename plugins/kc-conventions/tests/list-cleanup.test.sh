#!/usr/bin/env bash
# Tests skills/kc-clean-up/scripts/list-cleanup.sh (§CU2, §CU3, §CU5): a merged clean worktree and its
# branch are listed; a dirty merged worktree, an unmerged branch and the default branch are not; stashes
# and branches whose remote branch is gone are listed; nothing is deleted.
set -u

tests_dir=$(cd "$(dirname "$0")" && pwd)
script="$(dirname "$tests_dir")/skills/kc-clean-up/scripts/list-cleanup.sh"
work_dir=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$work_dir"' EXIT

failures=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; failures=$((failures + 1)); }

g() { git -C "$work_dir/repo" "$@"; }
git init -q --bare "$work_dir/origin.git"
git clone -q "$work_dir/origin.git" "$work_dir/repo" 2>/dev/null
g config user.email t@example.com; g config user.name t
g checkout -q -b main
echo a > "$work_dir/repo/a"; g add a; g commit -q -m init; g push -q origin main
git -C "$work_dir/origin.git" symbolic-ref HEAD refs/heads/main
g remote set-head origin main >/dev/null 2>&1

g branch merged-free
g worktree add -q "$work_dir/wt-clean" -b merged-clean
g worktree add -q "$work_dir/wt-dirty" -b merged-dirty
echo x > "$work_dir/wt-dirty/x"
g worktree add -q "$work_dir/wt-open" -b unmerged
echo y > "$work_dir/wt-open/y"; git -C "$work_dir/wt-open" add y; git -C "$work_dir/wt-open" commit -q -m open
g branch gone-one; g push -q origin gone-one; g branch -q -u origin/gone-one gone-one
git -C "$work_dir/origin.git" branch -D gone-one >/dev/null; g fetch -q --prune
echo s >> "$work_dir/repo/a"; g stash -q -m "task stash"

out=$(bash "$script" --repo "$work_dir/repo" 2>&1)
has() { if printf '%s\n' "$out" | grep -qF -- "$2"; then ok "$1"; else bad "$1: missing '$2' in: $out"; fi; }
lacks() { if printf '%s\n' "$out" | grep -qF -- "$2"; then bad "$1: found '$2'"; else ok "$1"; fi; }

has "merged clean worktree listed" "worktree $work_dir/wt-clean (merged-clean)"
lacks "dirty merged worktree skipped" "wt-dirty"
lacks "unmerged worktree skipped" "wt-open"
has "merged branch without worktree listed" "branch merged-free"
lacks "branch with a worktree not listed as a branch" "branch merged-clean"
lacks "default branch not listed" "branch main"
has "stash listed" "task stash"
has "gone upstream listed" "gone gone-one"
if [ -d "$work_dir/wt-clean" ] && g rev-parse --verify -q merged-free >/dev/null; then ok "nothing deleted"; else bad "script deleted something"; fi
bash "$script" --bogus >/dev/null 2>&1; status=$?
if [ "$status" -eq 2 ]; then ok "bad flag exits 2"; else bad "bad flag exit $status"; fi
bash "$script" >/dev/null 2>&1; status=$?
if [ "$status" -eq 2 ]; then ok "no arguments exits 2"; else bad "no-argument exit $status"; fi

exit "$failures"
