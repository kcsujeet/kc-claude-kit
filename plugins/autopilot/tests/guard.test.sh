#!/usr/bin/env bash
# Tests scripts/guard.sh: one case per rule in the plan's Task 7.
set -euo pipefail
tests_dir=$(cd "$(dirname "$0")" && pwd)
guard="$(dirname "$tests_dir")/scripts/guard.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
passes=0
failures=0

# A worktree with a config naming risky paths.
wt="$tmp/wt"
git init -q -b main "$wt"
mkdir -p "$wt/.claude" "$wt/db/migrate" "$wt/src"
echo '{"risky_paths":["db/migrate/**","**/payments/**"]}' > "$wt/.claude/autopilot.json"

bash_payload() { jq -cn --arg agent "$1" --arg cmd "$2" --arg cwd "$wt" \
  '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$cmd},cwd:$cwd} + (if $agent == "" then {} else {agent_type:$agent} end)'; }
edit_payload() { jq -cn --arg agent "$1" --arg path "$2" --arg text "$3" --arg cwd "$wt" \
  '{hook_event_name:"PreToolUse",tool_name:"Edit",tool_input:{file_path:$path,old_string:"x",new_string:$text},cwd:$cwd} + (if $agent == "" then {} else {agent_type:$agent} end)'; }
write_payload() { jq -cn --arg agent "$1" --arg path "$2" --arg text "$3" --arg cwd "$wt" \
  '{hook_event_name:"PreToolUse",tool_name:"Write",tool_input:{file_path:$path,content:$text},cwd:$cwd} + (if $agent == "" then {} else {agent_type:$agent} end)'; }

check() {
  local expectation=$1 label=$2 payload=$3 output verdict
  output=$(printf '%s' "$payload" | bash "$guard")
  if [ -z "$output" ]; then verdict=allow
  elif printf '%s' "$output" | grep -q '"permissionDecision":"deny"'; then verdict=deny
  else verdict="unexpected: $output"; fi
  if [ "$verdict" = "$expectation" ]; then echo "ok   $label"; passes=$((passes + 1))
  else echo "FAIL $label"; echo "     expected $expectation, got $verdict"; failures=$((failures + 1)); fi
}

E=autopilot:engineer
check deny  "1 run files"            "$(write_payload $E "$wt/.autopilot/runs/r1/units.json" '{}')"
check deny  "1 run files, verifier"  "$(write_payload autopilot:verifier "$wt/.autopilot/runs/r1/report.md" 'x')"
check deny  "1 outside runs"         "$(write_payload $E "$wt/.autopilot/notes.md" 'x')"
check allow "1 unit scratch"         "$(write_payload autopilot:qa-persona "$wt/.autopilot/runs/r1/U1/qa/0/flow.cjs" 'x')"
check deny  "1 bash redirect"        "$(bash_payload autopilot:shipper "echo x > $wt/.autopilot/runs/r1/units.json")"
check allow "1 bash unit scratch"    "$(bash_payload autopilot:shipper "bash pr-body.sh in.json > $wt/.autopilot/runs/r1/U1/pr-body.md")"
check deny  "2 merge"                "$(bash_payload autopilot:shipper 'gh pr merge 12 --squash')"
check deny  "2 auto-merge"           "$(bash_payload autopilot:shipper 'gh pr merge --auto 12')"
check deny  "3 force push"           "$(bash_payload autopilot:shipper 'git push --force origin autopilot/r1/U1')"
check deny  "3 push main"            "$(bash_payload autopilot:shipper 'git push origin HEAD:main')"
check allow "3 push own branch"      "$(bash_payload autopilot:shipper 'git push -u origin autopilot/r1/U1')"
check deny  "4 it.skip"              "$(edit_payload $E "$wt/src/picker.test.tsx" "it.skip('inserts', () => {})")"
check deny  "4 rspec skip"           "$(edit_payload $E "$wt/spec/models/reply_spec.rb" "  skip 'flaky'")"
check deny  "4 pytest skip"          "$(write_payload $E "$wt/tests/test_reply.py" "@pytest.mark.skip")"
check allow "4 skip word in source"  "$(edit_payload $E "$wt/src/picker.tsx" "const skip = true")"
check deny  "5 rm test"              "$(bash_payload $E "rm src/picker.test.tsx")"
check deny  "5 git rm spec"          "$(bash_payload $E "git rm spec/models/reply_spec.rb")"
check deny  "6 risky migration"      "$(write_payload $E "$wt/db/migrate/20261012_add_replies.rb" "class X; end")"
check deny  "6 risky nested glob"    "$(edit_payload $E "$wt/src/payments/charge.ts" "x")"
check allow "6 risky only for engineer" "$(edit_payload autopilot:verifier "$wt/db/migrate/a.rb" "x")"
check allow "6 normal file"          "$(edit_payload $E "$wt/src/picker.tsx" "x")"
check deny  "7 lockfile"             "$(edit_payload $E "$wt/package-lock.json" "x")"
check deny  "7 bun add"              "$(bash_payload $E "bun add left-pad")"
check deny  "7 bundle add"           "$(bash_payload $E "bundle add sidekiq")"
check allow "7 plain install"        "$(bash_payload $E "bun install")"
check allow "8 main session"         "$(bash_payload '' 'gh pr merge 12')"
check allow "8 other plugin agent"   "$(bash_payload code-review:naming-gate 'gh pr merge 12')"

# 9: fail closed without jq. PATH without jq, keeping bash core utilities.
nojq="$tmp/nojq"; mkdir -p "$nojq"
for tool in bash cat grep sed tr printf dirname; do
  path=$(command -v "$tool" || true); [ -n "$path" ] && ln -s "$path" "$nojq/$tool"
done
out=$(bash_payload $E 'ls' | PATH="$nojq" bash "$guard")
if printf '%s' "$out" | grep -q 'jq is required'; then echo "ok   9 fail closed without jq"; passes=$((passes + 1))
else echo "FAIL 9 fail closed without jq"; echo "     got: $out"; failures=$((failures + 1)); fi

echo "guard: $passes passed, $failures failed"
[ "$failures" = 0 ]
