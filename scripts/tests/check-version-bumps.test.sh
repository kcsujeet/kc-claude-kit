#!/usr/bin/env bash
# Tests scripts/check-version-bumps.sh in a throwaway repo with two plugins.
set -euo pipefail

script="$(cd "$(dirname "$0")/.." && pwd)/check-version-bumps.sh"
repo=$(mktemp -d)
trap 'rm -rf "$repo"' EXIT
passes=0
failures=0

check() {
  local expectation=$1 label=$2 actual=pass
  (cd "$repo" && bash "$script" main >/dev/null) || actual=fail
  if [ "$actual" = "$expectation" ]; then
    echo "ok   $label"
    passes=$((passes + 1))
  else
    echo "FAIL $label (expected $expectation, got $actual)"
    failures=$((failures + 1))
  fi
}

manifest() {
  mkdir -p "$repo/plugins/$1/.claude-plugin"
  printf '{\n  "name": "%s",\n  "version": "%s"\n}\n' "$1" "$2" > "$repo/plugins/$1/.claude-plugin/plugin.json"
}

commit() {
  git -C "$repo" add -A
  git -C "$repo" -c user.name=t -c user.email=t@example.test commit -q -m "$1"
}

git -C "$repo" init -q -b main
manifest shop 1.2.0
manifest cart 0.9.0
echo "rule" > "$repo/plugins/shop/rule.md"
commit base
git -C "$repo" checkout -q -b change

check pass "nothing changed"
echo "rule, edited" > "$repo/plugins/shop/rule.md"
commit "edit shop"
check fail "a changed plugin without a bump"
manifest shop 1.2.1
commit "bump shop"
check pass "a changed plugin with a patch bump"
echo "note" > "$repo/plugins/cart/note.md"
commit "edit cart"
check fail "a second changed plugin without a bump"
manifest cart 0.8.0
commit "lower cart"
check fail "a lower version"
manifest cart 0.10.0
commit "bump cart"
check pass "both bumped (0.10.0 sorts above 0.9.0)"
manifest basket 0.1.0
commit "new plugin"
check pass "a new plugin"

echo "$passes passed, $failures failed"
[ "$failures" -eq 0 ]
