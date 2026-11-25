#!/usr/bin/env bash
# Tests (§P19) skills/kc-simplicity/scripts/no-precedent.sh with --base: tokens are counted in the
# tree at that ref, so what the base already used is not flagged and what it never used is, even
# when the checkout is already at the head.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
sweep="$(dirname "$tests_dir")/skills/kc-simplicity/scripts/no-precedent.sh"
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
printf '.page { height: 100vh; width: 10px; }\n' > "$repo/src/base.css"
run_git add -A && run_git commit -q -m base
base=$(run_git rev-parse HEAD)
printf '.page { height: 100vh; width: 10px; }\n.card { width: 20cqw; height: 50vh; }\n' > "$repo/src/base.css"
run_git add -A && run_git commit -q -m head
run_git diff "$base" HEAD > "$work_dir/change.diff"

actual=$(bash "$sweep" "$work_dir/change.diff" "$repo" --base "$base")
check "a unit the base never used is flagged, one it used is not" \
  "src/base.css:2: [no precedent: unit cqw] .card { width: 20cqw; height: 50vh; }" "$actual"

[ "$failures" -eq 0 ]
