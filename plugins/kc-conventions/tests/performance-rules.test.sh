#!/usr/bin/env bash
# Checks that the performance topic keeps its boundary-payload box and sweep, that the security topic
# grades the same sweep's request-input hits, and that the correctness gate preloads the topic so
# the box is graded. The sweep's exact output is pinned by tests/sweeps/kc-performance.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
plugin_dir=$(dirname "$tests_dir")
repo_dir=$(cd "$plugin_dir/../.." && pwd)
skill="$plugin_dir/skills/kc-performance/SKILL.md"
security_skill="$plugin_dir/skills/kc-security/SKILL.md"
sweep="$plugin_dir/skills/kc-performance/scripts/boundary-payloads.sh"

failures=0
fail_rule_check() { echo "FAIL $1"; failures=$((failures + 1)); }
require_box_text() { grep -qE "^- \[ \] $2 .*$3" "$1" || fail_rule_check "$2 box must carry: $3"; }

require_box_text "$skill" §PF1 'sized for the receiver'
require_box_text "$skill" §PF1 'boundary-payloads.sh'
require_box_text "$skill" §PF1 'grepped boundary payloads: 0 hits'
grep -qE '^### §PF1\. ' "$skill" || fail_rule_check "§PF1 has a checklist box but no detail section"
sed -n '/^## Sweeps/,$p' "$skill" | grep -q 'skills/kc-performance/scripts/boundary-payloads.sh' || fail_rule_check "§PF1: Sweeps must list boundary-payloads.sh"
require_box_text "$security_skill" §SEC10 'Raw request input never reaches a job, log, cache or event'
require_box_text "$security_skill" §SEC10 'boundary-payloads.sh'
sed -n '/^## Sweeps/,$p' "$security_skill" | grep -q 'skills/kc-performance/scripts/boundary-payloads.sh' || fail_rule_check "§SEC10: security Sweeps must list boundary-payloads.sh"
grep -qx '  - kc-conventions:kc-performance' "$repo_dir/plugins/kc-gates/agents/correctness-gate.md" \
  || fail_rule_check "§PF1: the correctness gate must preload kc-performance, or no gate grades the box"
[ -x "$sweep" ] || fail_rule_check "boundary-payloads.sh must be executable"

bash "$plugin_dir/scripts/build-rules.sh" --check >/dev/null || fail_rule_check "rules/ is stale: run build-rules.sh"
[ "$failures" -eq 0 ] && echo "ok   performance rules"
exit "$failures"
