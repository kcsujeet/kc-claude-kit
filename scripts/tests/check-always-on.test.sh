#!/usr/bin/env bash
# Tests scripts/check-always-on.sh against a fixture plugin tree: what it counts as always-on, the
# report numbers, skipped hooks, and each budget passing and failing.
set -euo pipefail

scripts_dir="$(cd "$(dirname "$0")/.." && pwd)"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
passes=0
failures=0

# Runs the checker on the fixture with <args>; expects status <want> and output containing <text>.
check() {
  local label=$1 want=$2 text=$3 output status=0
  shift 3
  output=$(bash "$scripts_dir/check-always-on.sh" --root "$work_dir/kit" "$@" 2>&1) || status=$?
  if [ "$status" -eq "$want" ] && printf '%s' "$output" | grep -qF -- "$text"; then
    echo "ok   $label"
    passes=$((passes + 1))
  else
    echo "FAIL $label (want status $want with: $text; got status $status: $output)"
    failures=$((failures + 1))
  fi
}

plugin="$work_dir/kit/plugins/p"
mkdir -p "$plugin/rules" "$plugin/skills/s" "$plugin/agents" "$plugin/hooks" "$plugin/scripts"
# 100-byte always-on rule, and a path-scoped one that must not count.
{ printf '# Rule\n'; head -c 93 /dev/zero | tr '\0' 'x'; } > "$plugin/rules/always.md"
printf -- '---\npaths:\n  - "**/*.ts"\n---\n%s\n' "$(head -c 500 /dev/zero | tr '\0' 'y')" > "$plugin/rules/scoped.md"
printf -- '---\nname: s\ndescription: "%s"\n---\nbody that is not counted\n' "$(head -c 60 /dev/zero | tr '\0' 'a')" > "$plugin/skills/s/SKILL.md"
printf -- '---\nname: a\ndescription: %s\ntools: Read\n---\nbody\n' "$(head -c 40 /dev/zero | tr '\0' 'b')" > "$plugin/agents/a.md"
cat > "$plugin/hooks/hooks.json" <<'JSON'
{"hooks":{
 "SessionStart":[{"hooks":[{"type":"command","command":"\"${CLAUDE_PLUGIN_ROOT}/scripts/print.sh\""}]}],
 "UserPromptSubmit":[{"hooks":[
   {"type":"command","command":"\"${CLAUDE_PLUGIN_ROOT}/scripts/update-marketplace.sh\""},
   {"type":"command","command":"\"${CLAUDE_PLUGIN_ROOT}/scripts/slow.sh\"","async":true}]}]}}
JSON
printf '#!/usr/bin/env bash\nhead -c 70 /dev/zero | tr "\\0" z\n' > "$plugin/scripts/print.sh"
printf '#!/usr/bin/env bash\nhead -c 999 /dev/zero | tr "\\0" z\n' > "$plugin/scripts/update-marketplace.sh"
printf '#!/usr/bin/env bash\nhead -c 999 /dev/zero | tr "\\0" z\n' > "$plugin/scripts/slow.sh"
chmod +x "$plugin"/scripts/*.sh

check "report: only the rule without paths counts" 0 "1 file(s), 100 bytes (~25 tokens, estimate)"
check "report: descriptions are counted without quotes or body" 0 "2, 100 bytes"
check "report: the longest description is listed first" 0 "60 plugins/p/skills/s/SKILL.md"
check "report: a hook's printed bytes are measured, skipped and async hooks are not" 0 "total: 70 bytes"
check "report: the hook is named with its event" 0 "70  p/print.sh (SessionStart)"
check "no budget flags never fails" 0 "Always-on rule files"

check "rules budget met" 0 "Always-on" --budget-rules 100
check "rules budget exceeded names the overage" 1 "always-on rules is 100 bytes, budget 99, over by 1" --budget-rules 99
check "descriptions budget met" 0 "Skill and agent" --budget-descriptions 100
check "descriptions budget exceeded" 1 "descriptions is 100 bytes, budget 90, over by 10" --budget-descriptions 90
check "max description met" 0 "Skill and agent" --max-description 60
check "max description exceeded names the file" 1 "description of plugins/p/skills/s/SKILL.md is 60 bytes, maximum 59, over by 1" --max-description 59
check "hooks budget met" 0 "Hook-printed" --budget-hooks 70
check "hooks budget exceeded" 1 "hook-printed text is 70 bytes, budget 10, over by 60" --budget-hooks 10
check "several budgets exceeded are all named" 1 "descriptions is 100 bytes" --budget-rules 1 --budget-descriptions 1 --budget-hooks 1

echo "$passes passed, $failures failed"
[ "$failures" -eq 0 ]
