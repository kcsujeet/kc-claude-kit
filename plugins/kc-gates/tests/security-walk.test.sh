#!/usr/bin/env bash
# Checks the text that makes a public path get walked: kc-code-review's hard rule and walk receipt,
# the security row in its gate table and status template, the security gate's contract, and the
# verification gate's §V10 box. select-gates.test.sh checks the WALK= line these depend on.
# shellcheck disable=SC2016 # the patterns hold literal backticks from the Markdown they check
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
plugin_dir=$(dirname "$tests_dir")
# Wording moved to references/detail.md (the review skill) and verification-detail.md (the gate) is
# checked where it now lives: each pair is read as one text.
review_dir="$plugin_dir/skills/kc-code-review"
review_text=$(mktemp)
verification_text=$(mktemp)
trap 'rm -f "$review_text" "$verification_text"' EXIT
cat "$review_dir/SKILL.md" "$review_dir/references/detail.md" > "$review_text"
cat "$plugin_dir/agents/verification-gate.md" "$review_dir/references/verification-detail.md" > "$verification_text"
review="$review_text"
verification="$verification_text"
review_skill="$review_dir/SKILL.md"
gate="$plugin_dir/agents/security-gate.md"

max_skill_lines=500
failures=0
fail() { echo "FAIL $1"; failures=$((failures + 1)); }

grep -q 'When `select-gates.sh` prints `WALK=required`' "$review" || fail "kc-code-review: hard rule on WALK=required"
grep -q 'the reviewer has seen each changed behaviour themselves' "$review" || fail "kc-code-review: every changed behaviour is walked by the reviewer"
grep -q 'skipped a change made for someone else' "$review" || fail "kc-code-review: a re-review walks the delta, not only its own findings"
grep -q 'gives the public-path reason (`walk: public or guest path`), a signed-out visitor can reach the change, and only then the review also runs it as every audience' "$review" || fail "kc-code-review: only the public-path reason walks every audience"
grep -q 'with the public-path reason, also the audiences walked (signed out included)' "$review" || fail "kc-code-review: the Walk line asks for audiences only with the public-path reason"
grep -qE '^- \[ \] §V11 .*walk-item.*Walk:.*no receipt FAILS' "$verification" || fail "verification-gate §V11 box: a walk-item with no receipt FAILS"
grep -q 'signed out in a fresh browser profile included' "$review" || fail "kc-code-review: the walk includes signed out"
grep -q 'kc-verify:kc-ui` and `kc-verify:kc-e2e`' "$review" || fail "kc-code-review: the walk names kc-ui and kc-e2e"
grep -q '^- Walk: ' "$review" || fail "kc-code-review: the Checklist template has a Walk line"
grep -qE '^\| security \| `kc-gates:security-gate`' "$review" || fail "kc-code-review: security row in the phase-1 table"
grep -qE '^\| security \| \.\.\. \|' "$review" || fail "kc-code-review: security row in the gate-status template"
grep -qE '^- \[ \] §V10 .*public-path walk reason.*Walk:.*no receipt FAILS' "$verification" || fail "verification-gate §V10 box: a public-path reason with no receipt FAILS"
grep -q 'N/A: no public-path reason)' "$verification" || fail "verification-gate §V10 box: its N/A condition"
grep -q 'other walk-items are §V11' "$verification" || fail "verification-gate §V10: every other walk-item is §V11's"
grep -q 'grepped request surface: N hits' "$verification" || fail "verification-gate §V2: the security receipt"
grep -q 'kc-conventions:kc-security' "$gate" || fail "security-gate preloads kc-security"
[ "$(wc -l < "$review_skill")" -lt "$max_skill_lines" ] || fail "kc-code-review SKILL.md must stay under $max_skill_lines lines"
grep -q 'replayed with another record' "$plugin_dir/../kc-verify/skills/kc-e2e/SKILL.md" || fail "kc-e2e: the replay box"
! grep -q 'it is not a security review' "$review" || fail "kc-code-review: 'What this skill is not' must not deny the security gate it runs"
grep -q 'correctness, security, project-conventions, this gate) was walked' "$verification" || fail "verification-gate self-review: the gate list includes security"

[ "$failures" -eq 0 ] && echo "ok   security walk text"
exit "$failures"
