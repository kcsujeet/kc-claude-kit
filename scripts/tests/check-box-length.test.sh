#!/usr/bin/env bash
# Tests scripts/check-box-length.sh in a throwaway repo: a checklist box over 220 characters fails,
# one at the limit passes, a long line outside the `## Review checklist` section is left alone, and
# a long box in any skill of any plugin is found.
set -euo pipefail

script="$(cd "$(dirname "$0")/.." && pwd)/check-box-length.sh"
repo=$(mktemp -d)
trap 'rm -rf "$repo"' EXIT
passes=0
failures=0

pass() { echo "ok   $1"; passes=$((passes + 1)); }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }

last_output=""
expect_verdict() {
  local expectation=$1 label=$2 actual=pass
  last_output=$(bash "$script" "$repo" 2>&1) || actual=fail
  if [ "$actual" = "$expectation" ]; then pass "$label"; else fail "$label (expected $expectation, got $actual: $last_output)"; fi
}

# write_skill <plugin> <skill> <checklist box line>
write_skill() {
  mkdir -p "$repo/plugins/$1/skills/$2"
  printf '# Skill\n\n## Review checklist\n\n%s\n\n## Notes\n\n%s\n' "$3" "$(head -c 400 /dev/zero | tr '\0' 'x')" > "$repo/plugins/$1/skills/$2/SKILL.md"
}
box_of_length() { printf -- '- [ ] §X1 %s' "$(head -c $(($1 - 11)) /dev/zero | tr '\0' 'a')"; }

write_skill kc-a kc-one "$(box_of_length 220)"
expect_verdict pass "a box of exactly 220 characters passes"
write_skill kc-a kc-one "$(box_of_length 221)"
expect_verdict fail "a box of 221 characters fails"
case "$last_output" in *"kc-one/SKILL.md:5"*) pass "the message names the file and line" ;; *) fail "no file:line in: $last_output" ;; esac
write_skill kc-a kc-one "$(box_of_length 100)"
expect_verdict pass "the long line under ## Notes is left alone"
write_skill kc-b kc-two "$(box_of_length 300)"
expect_verdict fail "a long box in another plugin's skill is found"
rm -rf "$repo/plugins/kc-b"
mkdir -p "$repo/empty/plugins"
if bash "$script" "$repo/empty" > /dev/null 2>&1; then pass "a repo with no skills passes"; else fail "a repo with no skills failed"; fi

echo "$passes passed, $failures failed"
[ "$failures" -eq 0 ]
