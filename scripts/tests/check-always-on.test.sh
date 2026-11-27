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
   {"type":"command","command":"\"${CLAUDE_PLUGIN_ROOT}/scripts/slow.sh\"","async":true}]}],
 "PreToolUse":[{"hooks":[
   {"type":"command","command":"\"${CLAUDE_PLUGIN_ROOT}/scripts/quiet.sh\""},
   {"type":"command","command":"\"${CLAUDE_PLUGIN_ROOT}/scripts/chatty.sh\""},
   {"type":"command","command":"\"${CLAUDE_PLUGIN_ROOT}/scripts/read-only.sh\""}]}],
 "PostToolUse":[{"hooks":[
   {"type":"command","command":"\"${CLAUDE_PLUGIN_ROOT}/scripts/stderr.sh\""},
   {"type":"command","command":"\"${CLAUDE_PLUGIN_ROOT}/scripts/once.sh\""},
   {"type":"command","command":"\"${CLAUDE_PLUGIN_ROOT}/scripts/update-after.sh\""}]}]}}
JSON
printf '#!/usr/bin/env bash\nhead -c 70 /dev/zero | tr "\\0" z\n' > "$plugin/scripts/print.sh"
printf '#!/usr/bin/env bash\nhead -c 999 /dev/zero | tr "\\0" z\n' > "$plugin/scripts/update-marketplace.sh"
printf '#!/usr/bin/env bash\nhead -c 999 /dev/zero | tr "\\0" z\n' > "$plugin/scripts/slow.sh"
# quiet: silent on ordinary calls, speaks only for `rm`; chatty: 40 bytes on every call; stderr: 25 bytes on stderr.
printf '#!/usr/bin/env bash\nif grep -q "rm -rf" ; then echo blocked; fi\n' > "$plugin/scripts/quiet.sh"
printf '#!/usr/bin/env bash\ncat >/dev/null\nhead -c 40 /dev/zero | tr "\\0" c\n' > "$plugin/scripts/chatty.sh"
printf '#!/usr/bin/env bash\nif grep -q "\\"Read\\""; then echo speaks-on-read-only; fi\n' > "$plugin/scripts/read-only.sh"
printf '#!/usr/bin/env bash\ncat >/dev/null\nhead -c 25 /dev/zero | tr "\\0" e >&2\n' > "$plugin/scripts/stderr.sh"
printf '#!/usr/bin/env bash\nhead -c 999 /dev/zero | tr "\\0" z\n' > "$plugin/scripts/update-after.sh"
# shellcheck disable=SC2016 # the hook's text, written to a file
# once: a hand-off reminder; speaks only on a git push.
printf '#!/usr/bin/env bash\nif grep -q "git push"; then head -c 33 /dev/zero | tr "\\0" o; fi\n' > "$plugin/scripts/once.sh"
mkdir -p "$plugin/skills/s/references"
head -c 900 /dev/zero | tr '\0' 'r' > "$plugin/skills/s/references/ref.md"
chmod +x "$plugin"/scripts/*.sh

check "report: only the rule without paths counts" 0 "1 file(s), 100 bytes (~25 tokens, estimate)"
check "report: descriptions are counted without quotes or body" 0 "2, 100 bytes"
check "report: the longest description is listed first" 0 "60 plugins/p/skills/s/SKILL.md"
check "report: a hook's printed bytes are measured, skipped and async hooks are not" 0 "total: 70 bytes"
check "report: the hook is named with its event" 0 "70  p/print.sh (SessionStart)"
check "tool hooks: a silent hook measures 0" 0 "0 p/quiet.sh (PreToolUse)"
check "tool hooks: a hook printing on every call is measured" 0 "40 p/chatty.sh (PreToolUse)"
check "tool hooks: the worst of the four payloads is reported, not the last" 0 "20 p/read-only.sh (PreToolUse)"
check "tool hooks: stderr counts" 0 "25 p/stderr.sh (PostToolUse)"
check "tool hooks: update-*.sh is skipped" 0 "max: 40 bytes per ordinary call"
check "tool hooks: a hand-off reminder is silent on ordinary calls" 0 "0 p/once.sh (PostToolUse)"
check "hand-off: a git push's bytes are reported" 0 "33 p/once.sh (PostToolUse)"
check "hand-off: a hook silent on a push is not listed" 0 "Hand-off tool-hook output (a git push, bytes printed; report only):
  33"
check "hand-off: a silent hook is not listed under the reminder's name" 0 "Hand-off tool-hook output (a git push, bytes printed; report only):
  33 p/once.sh (PostToolUse)
"
check "tool hooks budget met" 0 "Per-tool-call" --budget-tool-hooks 40
check "tool hooks budget exceeded names the hook" 1 "p/chatty.sh (PreToolUse) prints 40 bytes on an ordinary tool call, budget 39, over by 1" --budget-tool-hooks 39
check "tool hooks budget of 0 fails a hook that prints" 1 "p/stderr.sh (PostToolUse) prints 25 bytes" --budget-tool-hooks 0
check "report: references are listed apart from bodies" 0 "900 plugins/p/skills/s/references/ref.md"
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

# Body sizes: the skill body is the whole SKILL.md; the agent body the whole agents/a.md.
skill_size=$(wc -c < "$plugin/skills/s/SKILL.md" | tr -d ' ')
agent_size=$(wc -c < "$plugin/agents/a.md" | tr -d ' ')
check "report: skill body is sized" 0 "$skill_size plugins/p/skills/s/SKILL.md"
check "skill body at the max passes" 0 "Skill bodies" --max-skill-body "$skill_size"
check "skill body over the max names the file" 1 "skill body plugins/p/skills/s/SKILL.md is $skill_size bytes, maximum $((skill_size - 1)), over by 1" --max-skill-body "$((skill_size - 1))"
check "agent body at the max passes" 0 "Agent bodies" --max-agent-body "$agent_size"
check "agent body over the max names the file" 1 "agent body plugins/p/agents/a.md is $agent_size bytes, maximum $((agent_size - 1)), over by 1" --max-agent-body "$((agent_size - 1))"
check "an agent body is not held to the skill max" 0 "Agent bodies" --max-skill-body "$skill_size" --max-agent-body "$agent_size"

echo "$passes passed, $failures failed"
[ "$failures" -eq 0 ]
