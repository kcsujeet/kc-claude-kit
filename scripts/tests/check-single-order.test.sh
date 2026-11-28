#!/usr/bin/env bash
# Tests scripts/check-single-order.sh in a throwaway tree: a skill, a reference, the session-start
# text, a guard message or the README that states the order of work ("on the committed branch", "as
# soon as the work is committed", "before its first push") fails, kc-do-a-task may state it, and the
# retired skill name fails everywhere but the CHANGELOG.
set -euo pipefail

script="$(cd "$(dirname "$0")/.." && pwd)/check-single-order.sh"
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
reset() {
  rm -rf "$repo"
  mkdir -p "$repo/plugins/kc-a/skills/kc-one/references" "$repo/plugins/kc-conventions/skills/kc-do-a-task" "$repo/plugins/kc-gates/scripts"
  printf '# One\n\n1. Review the change.\n' > "$repo/plugins/kc-a/skills/kc-one/SKILL.md"
  printf '# Detail\n\n- Review the change.\n' > "$repo/plugins/kc-a/skills/kc-one/references/detail.md"
  printf '# Do\n\n1. Review before the first push.\n' > "$repo/plugins/kc-conventions/skills/kc-do-a-task/SKILL.md"
  printf '# Readme\n' > "$repo/README.md"
  printf '# Changelog\n\n- kc-ready-for-review 3.1.0\n' > "$repo/CHANGELOG.md"
}

reset
expect_verdict pass "a clean tree passes, and kc-do-a-task may state the order"
reset; printf '1. Run it on the committed branch.\n' >> "$repo/plugins/kc-a/skills/kc-one/SKILL.md"
expect_verdict fail "a skill stating 'on the committed branch' fails"
case "$last_output" in *"kc-one/SKILL.md:4"*) pass "the message names the file and line" ;; *) fail "no file:line in: $last_output" ;; esac
reset; printf -- '- Run it as soon as the work is committed.\n' >> "$repo/plugins/kc-a/skills/kc-one/references/detail.md"
expect_verdict fail "a reference stating 'as soon as the work is committed' fails"
reset; printf -- '- Needed before its first push.\n' >> "$repo/plugins/kc-a/skills/kc-one/references/detail.md"
expect_verdict fail "a reference stating 'before its first push' fails"
reset; printf -- '- RUN IT ON THE COMMITTED LOCAL BRANCH.\n' >> "$repo/plugins/kc-a/skills/kc-one/references/detail.md"
expect_verdict fail "the phrases match in any case"
reset; printf "echo 'run it before the PR exists'\n" > "$repo/plugins/kc-gates/scripts/session-start.sh"
expect_verdict fail "the session-start text stating the order fails"
reset; printf 'deny "Run it on the committed branch."\n' > "$repo/plugins/kc-gates/scripts/guard-hand-off.sh"
expect_verdict fail "a guard message stating the order fails"
reset; printf 'Review once per PR.\n' >> "$repo/README.md"
expect_verdict fail "the README stating the order fails"
reset; printf -- '- Run /kc-gates:kc-ready-for-review.\n' >> "$repo/plugins/kc-a/skills/kc-one/SKILL.md"
expect_verdict fail "the retired skill name in a skill fails"
reset; printf 'x\n' > "$repo/plugins/kc-gates/scripts/anything.sh"; printf 'kc-ready-for-review\n' >> "$repo/plugins/kc-gates/scripts/anything.sh"
expect_verdict fail "the retired name in a script fails"
reset; mkdir -p "$repo/.git"; printf 'kc-ready-for-review\n' > "$repo/.git/note"
expect_verdict pass "the retired name inside .git is not searched"
reset; printf -- '- The skill kc-ready-for-human-review checks the record.\n' >> "$repo/plugins/kc-a/skills/kc-one/SKILL.md"
expect_verdict pass "the new skill name passes"
reset; printf -- '- Fixes go before the first commit.\n' >> "$repo/plugins/kc-a/skills/kc-one/SKILL.md"
expect_verdict pass "wording that only resembles the phrases passes"

echo "$passes passed, $failures failed"
[ "$failures" -eq 0 ]
