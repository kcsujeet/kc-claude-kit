#!/usr/bin/env bash
# Tests scripts/approvals-needed.sh: it lists every phrase the steps still ahead on a branch need
# (approve prose, approve rework, approve merge), each once, by running those guards in check-only
# mode, and nothing for a small prose branch or outside a repository. Real repos in a temp folder,
# receipts written by hand into KC_READY_DIR, the stub gh in lib/ answering every lookup with a failure.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
scripts="$(dirname "$tests_dir")/scripts"
require_jq
export KC_READY_DIR="$work_dir/receipts"
mkdir -p "$KC_READY_DIR" "$work_dir/gh"
use_gh_fixtures "$work_dir/gh"
: > "$work_dir/gh/routes.tsv"

repo="$work_dir/repo"
run_git() { git -C "$repo" -c user.name=t -c user.email=t@example.test "$@"; }
git init -q -b main "$repo"
git init -q --bare "$repo.git"
git -C "$repo" remote add origin "$repo.git"
printf 'echo one\necho two\n' > "$repo/order.sh"
printf 'Orders ship in one box.\nRefunds go to the card.\n' > "$repo/rules.md"
run_git add -A
run_git commit -q -m "order script (#3)"
git -C "$repo" push -q origin main
printf 'rounds=1\nopen=0\nclean=yes\n' > "$KC_READY_DIR/$(git -C "$repo" rev-parse HEAD)"
needed() { bash "$scripts/approvals-needed.sh" --dir "$repo"; }

expect_eq "nothing ahead on main: no phrase" "" "$(needed)"

run_git checkout -q -b wording
sed '2s/.*/Refunds go back to the card used./' "$repo/rules.md" > "$work_dir/r.tmp" && mv "$work_dir/r.tmp" "$repo/rules.md"
run_git commit -q -am wording
expect_eq "a small prose branch editing a handed-off line: no phrase" "" "$(needed)"

run_git checkout -q -b rework main
sed '2s/.*/echo three/' "$repo/order.sh" > "$work_dir/o.tmp" && mv "$work_dir/o.tmp" "$repo/order.sh"
run_git commit -q -am rework
expect_eq "a branch editing a handed-off script line: approve rework" "approve rework" "$(needed)"
printf 'sha=%s\nrounds=1\nopen=1\nclean=no\n' "$(git -C "$repo" rev-parse HEAD)" > "$KC_READY_DIR/$(git -C "$repo" rev-parse HEAD)"
expect_eq "and a receipt that left findings open: approve merge too" "approve rework
approve merge" "$(needed)"
printf 'sha=%s\nrounds=1\nopen=0\nclean=yes\n' "$(git -C "$repo" rev-parse HEAD)" > "$KC_READY_DIR/$(git -C "$repo" rev-parse HEAD)"
expect_eq "a clean receipt needs no merge phrase" "approve rework" "$(needed)"

printf 'Always ship orders in one box.\nNever split a refund.\n' >> "$repo/CLAUDE.md"
run_git add CLAUDE.md
expect_eq "a staged rule with no check: approve prose first" "approve prose
approve rework" "$(needed)"

mkdir -p "$work_dir/not-a-repo"
expect_eq "outside a repository: no phrase" "" "$(bash "$scripts/approvals-needed.sh" --dir "$work_dir/not-a-repo")"
status=0
bash "$scripts/approvals-needed.sh" --bogus >/dev/null 2>&1 || status=$?
expect_eq "an unknown option is a usage error" 2 "$status"

finish
