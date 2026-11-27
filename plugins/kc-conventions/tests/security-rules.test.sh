#!/usr/bin/env bash
# Checks that the security topic keeps its boxes, and that each box names the failure it grades:
# kc-security §SEC1 to §SEC9 on its checklist, its sweep in its Sweeps section. Fixtures for the sweep itself are under tests/sweeps/kc-security.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
plugin_dir=$(dirname "$tests_dir")
skill="$plugin_dir/skills/kc-security/SKILL.md"
detail="$plugin_dir/skills/kc-security/references/detail.md"

failures=0
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
# shellcheck source=lib/box-text.sh
. "$tests_dir/lib/box-text.sh"
require_box_text() { box_has kc-security "$1" "$2" || fail "$1 box must carry: $2"; }

require_box_text §SEC1 'checks, in the handler, that the caller may act on every record it reads or writes'
require_box_text §SEC1 'N/A: the diff adds or changes no handler, route, callback or middleware'
require_box_text §SEC2 'looks each up alone FAILS'
require_box_text §SEC2 'N/A: no handler reads more than one request-supplied id or token'
require_box_text §SEC3 'idempotent for its target, cannot be pointed at another record'
require_box_text §SEC3 'N/A: the diff adds or changes no write reachable from a request'
require_box_text §SEC4 'starts from the caller.s scope'
require_box_text §SEC4 'N/A: no lookup by a request-supplied id'
require_box_text §SEC5 'recomputed or validated from the server.s own records'
require_box_text §SEC5 'N/A: the request carries no such value'
require_box_text §SEC6 'stay out of responses, logs, error messages and URLs'
require_box_text §SEC6 'N/A: the diff adds or changes no response, log line, error message or URL'
require_box_text §SEC7 'never by prefix or substring'
require_box_text §SEC7 'N/A: the diff adds or changes no redirect'
require_box_text §SEC8 'joining strings with request input'
require_box_text §SEC8 'N/A: no query, command, markup or template built from input'
require_box_text §SEC9 'request-surface.sh'
require_box_text §SEC9 'grepped request surface: 0 hits'

# §SEC10 (raw request input in jobs, logs, caches and events) has its box and its detail section.
require_box_text §SEC10 'validated, allowlisted output or ids'
grep -qE "^### §SEC10\. " "$detail" || fail "§SEC10 has a checklist box but no detail section"

for section in §SEC1 §SEC2 §SEC3 §SEC4 §SEC5 §SEC6 §SEC7 §SEC8 §SEC9; do
  grep -qE "^### $section\. " "$detail" || fail "$section has a checklist box but no detail section"
done
! sed -n '/^### §SEC7\. /,/^### §SEC8\. /p' "$detail" | grep -qE ' \? .+ : ' || fail "§SEC7's Prefer example must not be a ternary (clarity §C15): gates copy it into fixes"
sed -n '/^## Sweeps/,$p' "$skill" | grep -q 'skills/kc-security/scripts/request-surface.sh' || fail "Sweeps must list request-surface.sh"
[ -x "$plugin_dir/skills/kc-security/scripts/request-surface.sh" ] || fail "request-surface.sh must be executable"
box_has kc-security §SEC2 'ids that must belong together' i || fail "kc-security must carry the ids-belong-together box"

[ "$failures" -eq 0 ] && echo "ok   security rules"
exit "$failures"
