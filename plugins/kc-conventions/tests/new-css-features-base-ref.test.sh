#!/usr/bin/env bash
# Tests skills/kc-react/scripts/new-css-features.sh with a base ref (its third argument): uses are
# counted in the repo at that ref, so a unit the base already used is not new, and one it never
# used is, even when the checkout is already at the head.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
sweep="$(dirname "$tests_dir")/skills/kc-react/scripts/new-css-features.sh"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
repo="$work_dir/repo"
run_git() { git -C "$repo" -c user.name=t -c user.email=t@example.test "$@"; }
failures=0
check() {
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1"; echo "  expected: $2"; echo "  actual:   $3"; failures=$((failures + 1)); fi
}

git init -q -b main "$repo"
mkdir -p "$repo/src"
printf '.page { height: 100dvh; }\n' > "$repo/src/base.css"
run_git add -A && run_git commit -q -m base
base=$(run_git rev-parse HEAD)
printf '.page { height: 100dvh; }\n.card { width: 20cqw; margin-top: 5svh; }\n' > "$repo/src/base.css"
run_git add -A && run_git commit -q -m head
run_git diff "$base" HEAD > "$work_dir/change.diff"

actual=$(bash "$sweep" "$work_dir/change.diff" "$repo" "$base")
check "units the base never used are new, the one it used is not" \
  "src/base.css:2: [new to the repo: cqw] .card { width: 20cqw; margin-top: 5svh; }
src/base.css:2: [new to the repo: svh] .card { width: 20cqw; margin-top: 5svh; }" "$actual"

[ "$failures" -eq 0 ]
