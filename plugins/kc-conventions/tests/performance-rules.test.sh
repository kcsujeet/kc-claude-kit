#!/usr/bin/env bash
# Checks that the performance topic keeps its boundary-payload box and sweep, that the security topic
# grades the same sweep's request-input hits, and that the correctness gate preloads the topic so
# the box is graded. Exact sweep output is in tests/sweeps/kc-performance; this runs the sweep once
# more to show each box's case is a hit.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
plugin_dir=$(dirname "$tests_dir")
repo_dir=$(cd "$plugin_dir/../.." && pwd)
skill="$plugin_dir/skills/kc-performance/SKILL.md"
security_skill="$plugin_dir/skills/kc-security/SKILL.md"
sweep="$plugin_dir/skills/kc-performance/scripts/boundary-payloads.sh"
fixture="$tests_dir/sweeps/kc-performance/boundary-payloads/input.diff"

failures=0
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
pass() { echo "ok   $1"; }
require_box_text() { grep -qE "^- \[ \] $2 .*$3" "$1" || fail "$2 box must carry: $3"; }

require_box_text "$skill" §PF1 'sized for the receiver'
require_box_text "$skill" §PF1 'boundary-payloads.sh'
require_box_text "$skill" §PF1 'grepped boundary payloads: 0 hits'
grep -qE '^### §PF1\. ' "$skill" || fail "§PF1 has a checklist box but no detail section"
sed -n '/^## Sweeps/,$p' "$skill" | grep -q 'skills/kc-performance/scripts/boundary-payloads.sh' || fail "§PF1: Sweeps must list boundary-payloads.sh"
require_box_text "$security_skill" §SEC10 'Raw request input never reaches a job, log, cache or event'
require_box_text "$security_skill" §SEC10 'boundary-payloads.sh'
sed -n '/^## Sweeps/,$p' "$security_skill" | grep -q 'skills/kc-performance/scripts/boundary-payloads.sh' || fail "§SEC10: security Sweeps must list boundary-payloads.sh"
grep -qx '  - kc-conventions:kc-performance' "$repo_dir/plugins/kc-gates/agents/correctness-gate.md" \
  || fail "§PF1: the correctness gate must preload kc-performance, or no gate grades the box"
[ -x "$sweep" ] || fail "boundary-payloads.sh must be executable"

hits=$(bash "$sweep" "$fixture")
# expect_hit <box id> <label> <text the hit holds>
expect_hit() { if printf '%s\n' "$hits" | grep -qF -- "$3"; then pass "$1 hit: $2"; else fail "$1 no hit: $2"; fi; }
expect_no_hit() { if printf '%s\n' "$hits" | grep -qF -- "$3"; then fail "$1 false hit: $2"; else pass "$1 no hit: $2"; fi; }
expect_hit §PF1 "a spread form in a request body" "JSON.stringify({ ...form })"
expect_hit §PF1 "a whole record in a cache" "storefront.__dict__"
expect_hit §PF1 "a whole model in an event" "order.model_dump()"
expect_hit §PF1 "a whole record in a response" "render json: order.as_json"
expect_hit §SEC10 "raw parameters queued" "perform_later(params.to_unsafe_h)"
expect_hit §SEC10 "raw parameters logged" 'logger.info("order received'
expect_hit §SEC10 "a raw form logged" "extra=request.form"
expect_no_hit §PF1 "an id queued" "perform_later(order.id)"
expect_no_hit §PF1 "named fields cached" '{"name": storefront.name}'
expect_no_hit §SEC10 "validated values queued" "order_contract.call(order_params).to_h"
expect_no_hit §SEC10 "a test file" "spec/jobs"

bash "$plugin_dir/scripts/build-rules.sh" --check >/dev/null || fail "rules/ is stale: run build-rules.sh"
[ "$failures" -eq 0 ] && echo "ok   performance rules"
exit "$failures"
