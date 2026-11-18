#!/usr/bin/env bash
# Checks that the security topic keeps its boxes, and that each box names the failure it grades:
# kc-security §SEC1 to §SEC9 on its checklist, its sweep in its Sweeps section, and the generated
# rule file in step with the skill. Fixtures for the sweep itself are under tests/sweeps/kc-security.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
plugin_dir=$(dirname "$tests_dir")
skill="$plugin_dir/skills/kc-security/SKILL.md"
rule="$plugin_dir/rules/kc-security.md"

failures=0
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
box() { grep -qE "^- \[ \] $1 .*$2" "$skill" || fail "$1 box must carry: $2"; }

box §SEC1 'checks, in the handler, that the caller may act on every record it reads or writes'
box §SEC1 'N/A: the diff adds or changes no handler, route, callback or middleware'
box §SEC2 'looks each up alone FAILS'
box §SEC2 'N/A: no handler reads more than one request-supplied id or token'
box §SEC3 'idempotent for its target, cannot be pointed at another record'
box §SEC3 'N/A: the diff adds or changes no write reachable from a request'
box §SEC4 'starts from the caller.s scope'
box §SEC4 'N/A: no lookup by a request-supplied id'
box §SEC5 'recomputed or validated from the server.s own records'
box §SEC5 'N/A: the request carries no such value'
box §SEC6 'stay out of responses, logs, error messages and URLs'
box §SEC6 'N/A: the diff adds or changes no response, log line, error message or URL'
box §SEC7 'never by prefix or substring'
box §SEC7 'N/A: the diff adds or changes no redirect'
box §SEC8 'joining strings with request input'
box §SEC8 'N/A: no query, command, markup or template built from input'
box §SEC9 'request-surface.sh'
box §SEC9 'grepped request surface: 0 hits'

for section in §SEC1 §SEC2 §SEC3 §SEC4 §SEC5 §SEC6 §SEC7 §SEC8 §SEC9; do
  grep -qE "^### $section\. " "$skill" || fail "$section has a checklist box but no detail section"
done
! sed -n '/^### §SEC7\. /,/^### §SEC8\. /p' "$skill" | grep -qE ' \? .+ : ' || fail "§SEC7's Prefer example must not be a ternary (clarity §C15): gates copy it into fixes"
sed -n '/^## Sweeps/,$p' "$skill" | grep -q 'skills/kc-security/scripts/request-surface.sh' || fail "Sweeps must list request-surface.sh"
[ -x "$plugin_dir/skills/kc-security/scripts/request-surface.sh" ] || fail "request-surface.sh must be executable"
grep -q 'ids the request supplies that must belong together are checked together' "$rule" \
  || grep -q 'Ids the request supplies that must belong together are checked together' "$rule" || fail "rules/kc-security.md must carry the ids-belong-together rule"
bash "$plugin_dir/scripts/build-rules.sh" --check >/dev/null || fail "rules/ is stale: run build-rules.sh"

[ "$failures" -eq 0 ] && echo "ok   security rules"
exit "$failures"
