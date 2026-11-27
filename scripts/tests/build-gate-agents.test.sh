#!/usr/bin/env bash
# Tests scripts/build-gate-agents.sh against the kit's real template: the generated files equal the
# committed agents (so the committed ones are not edited by hand), --check passes on them, a hand
# edit or a missing file makes it fail, and the topic gates differ only where the template says.
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
script="$root/scripts/build-gate-agents.sh"
template="$root/plugins/kc-gates/gate-agent.template.md"
agents="$root/plugins/kc-gates/agents"
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
passes=0
failures=0

pass() { echo "ok   $1"; passes=$((passes + 1)); }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
expect_exit() {
  local expectation=$1 label=$2 actual=0
  shift 2
  "$@" > "$out/last-output" 2>&1 || actual=$?
  if [ "$actual" = "$expectation" ]; then pass "$label"; else fail "$label (expected exit $expectation, got $actual: $(cat "$out/last-output"))"; fi
}

expect_exit 0 "--check passes on the committed agents" bash "$script" "$template" --check
bash "$script" "$template" --out-dir "$out"
for topic in clarity correctness datetime i18n naming rails react security simplicity structure testing; do
  if cmp -s "$out/$topic-gate.md" "$agents/$topic-gate.md"; then pass "$topic-gate.md is what the template makes"; else fail "$topic-gate.md differs from the template's output"; fi
done
expect_exit 0 "--check passes on a fresh build" bash "$script" "$template" --check --out-dir "$out"
printf 'hand edit\n' >> "$out/rails-gate.md"
expect_exit 1 "--check fails on a hand-edited agent" bash "$script" "$template" --check --out-dir "$out"
case "$(cat "$out/last-output")" in *"drift: $out/rails-gate.md"*) pass "the message names the drifted file" ;; *) fail "no drift line in: $(cat "$out/last-output")" ;; esac
bash "$script" "$template" --out-dir "$out"
rm "$out/testing-gate.md"
expect_exit 1 "--check fails on a missing agent" bash "$script" "$template" --check --out-dir "$out"
expect_exit 2 "a missing template is a usage error" bash "$script" "$out/no-such-template.md"
if grep -q 'GATE: react' "$out/react-gate.md" && grep -q 'kc-conventions:kc-performance' "$agents/correctness-gate.md"; then pass "topic and extra skill land where the template puts them"; else fail "topic or extra skill missing"; fi

echo "$passes passed, $failures failed"
[ "$failures" -eq 0 ]
