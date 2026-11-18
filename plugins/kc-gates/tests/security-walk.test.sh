#!/usr/bin/env bash
# Checks the text that makes a public path get walked: kc-code-review's hard rule and walk receipt,
# the security row in its gate table and status template, the security gate's contract, and the
# verification gate's §V10 box. select-gates.test.sh checks the WALK= line these depend on.
# shellcheck disable=SC2016 # the patterns hold literal backticks from the Markdown they check
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
plugin_dir=$(dirname "$tests_dir")
review="$plugin_dir/skills/kc-code-review/SKILL.md"
verification="$plugin_dir/agents/verification-gate.md"
gate="$plugin_dir/agents/security-gate.md"

max_skill_lines=500
failures=0
fail() { echo "FAIL $1"; failures=$((failures + 1)); }

grep -q 'When `select-gates.sh` prints `WALK=required`, the review runs the change in the running app as every audience' "$review" || fail "kc-code-review: hard rule on WALK=required"
grep -q 'signed out in a fresh browser profile included' "$review" || fail "kc-code-review: the walk includes signed out"
grep -q 'kc-verify:kc-ui` and `kc-verify:kc-e2e`' "$review" || fail "kc-code-review: the walk names kc-ui and kc-e2e"
grep -q '^- Walk: ' "$review" || fail "kc-code-review: the Checklist template has a Walk line"
grep -qE '^\| security \| `kc-gates:security-gate`' "$review" || fail "kc-code-review: security row in the phase-1 table"
grep -qE '^\| security \| \.\.\. \|' "$review" || fail "kc-code-review: security row in the gate-status template"
grep -qE '^- \[ \] §V10 .*WALK=required.*Walk:.*no receipt FAILS' "$verification" || fail "verification-gate §V10 box: WALK=required with no receipt FAILS"
grep -q 'N/A: `WALK=not-required`' "$verification" || fail "verification-gate §V10 box: its N/A condition"
grep -q 'grepped request surface: N hits' "$verification" || fail "verification-gate §V2: the security receipt"
grep -q 'kc-conventions:kc-security' "$gate" || fail "security-gate preloads kc-security"
[ "$(wc -l < "$review")" -lt "$max_skill_lines" ] || fail "kc-code-review SKILL.md must stay under $max_skill_lines lines"
grep -q 'replayed with another record' "$plugin_dir/../kc-verify/skills/kc-e2e/SKILL.md" || fail "kc-e2e: the replay box"
! grep -q 'it is not a security review' "$review" || fail "kc-code-review: 'What this skill is not' must not deny the security gate it runs"
grep -q 'correctness, security, project-conventions, this gate) was walked' "$verification" || fail "verification-gate self-review: the gate list includes security"

[ "$failures" -eq 0 ] && echo "ok   security walk text"
exit "$failures"
