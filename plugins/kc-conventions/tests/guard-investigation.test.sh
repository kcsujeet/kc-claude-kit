#!/usr/bin/env bash
# Tests hooks/guard-investigation.sh: with a failing investigation write-up for the current branch,
# opening a pull request or posting a comment (gh, gh api, an MCP comment tool) is denied with the
# problems; a passing write-up, no write-up, another branch's write-up or any other command is
# allowed silently. Bash cases run with jq and with the sed fallback (KC_GUARD_NO_JQ=1).
set -u

tests_dir=$(cd "$(dirname "$0")" && pwd)
plugin_dir=$(dirname "$tests_dir")
hook="$plugin_dir/hooks/guard-investigation.sh"
skill="$plugin_dir/skills/kc-investigate/SKILL.md"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

failures=0
passes=0

repo="$work_dir/shop"
git init -q "$repo"
git -C "$repo" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init
git -C "$repo" checkout -q -b fix/slow-import
write_up_dir="$repo/.git/kc-investigation/fix"
mkdir -p "$write_up_dir"
awk '/^```markdown$/ { inside = 1; next } inside && /^```$/ { exit } inside' "$skill" > "$work_dir/passing.md"
grep -v '§INV5' "$work_dir/passing.md" > "$work_dir/failing.md"

bash_payload() { jq -n --arg command "$1" --arg cwd "$2" '{tool_name: "Bash", cwd: $cwd, tool_input: {command: $command}}'; }
mcp_payload() { jq -n --arg tool "$1" --arg cwd "$2" '{tool_name: $tool, cwd: $cwd, tool_input: {body: "findings"}}'; }

# check <allow|deny> <label> <payload> [nojq]
check() {
  local expectation=$1 label=$2 payload=$3 mode=${4:-jq} output verdict
  if [ "$mode" = nojq ]; then
    output=$(printf '%s' "$payload" | KC_GUARD_NO_JQ=1 bash "$hook" 2>&1)
  else
    output=$(printf '%s' "$payload" | bash "$hook" 2>&1)
  fi
  verdict="unexpected: $output"
  [ -z "$output" ] && verdict=allow
  if printf '%s' "$output" | grep -q '"permissionDecision":"deny"' && printf '%s' "$output" | jq -e . >/dev/null 2>&1; then
    verdict=deny
  fi
  if [ "$verdict" = "$expectation" ]; then
    echo "ok   [$mode] $label"
    passes=$((passes + 1))
  else
    echo "FAIL [$mode] $label: expected $expectation, got $verdict"
    failures=$((failures + 1))
  fi
  last_output=$output
}

check allow "no write-up: gh pr create passes" "$(bash_payload 'gh pr create --fill' "$repo")"

cp "$work_dir/failing.md" "$write_up_dir/slow-import.md"
for mode in jq nojq; do
  check deny "§INV5 missing: gh pr create is denied" "$(bash_payload 'gh pr create --fill' "$repo")" "$mode"
  check deny "§INV5 missing: gh pr comment is denied" "$(bash_payload 'gh pr comment 12 --body-file /tmp/findings.md' "$repo")" "$mode"
  check deny "§INV5 missing: gh issue comment is denied" "$(bash_payload 'gh issue comment 7 --body hi' "$repo")" "$mode"
  check deny "§INV5 missing: a comments api write is denied" "$(bash_payload 'gh api repos/acme/shop/issues/7/comments -f body=hi' "$repo")" "$mode"
  check deny "§INV5 missing: a leading cd names the checkout" "$(bash_payload "cd $repo && gh pr create --fill" "$work_dir")" "$mode"
  check allow "§INV5 missing: git status passes" "$(bash_payload 'git status' "$repo")" "$mode"
  check allow "§INV5 missing: gh pr view passes" "$(bash_payload 'gh pr view 12' "$repo")" "$mode"
  check allow "§INV5 missing: a command from another checkout passes" "$(bash_payload 'gh pr create --fill' "$work_dir")" "$mode"
done
check deny "§INV5 missing: the denial names the problem" "$(bash_payload 'gh pr create --fill' "$repo")"
if printf '%s' "$last_output" | jq -r '.hookSpecificOutput.permissionDecisionReason' | grep -qF '§INV5: missing'; then
  echo "ok   the reason carries the checker's problem"; passes=$((passes + 1))
else
  echo "FAIL the reason does not carry the checker's problem: $last_output"; failures=$((failures + 1))
fi
check deny "§INV5 missing: an MCP comment tool is denied" "$(mcp_payload mcp__tracker__save_comment "$repo")"
check allow "§INV5 missing: an MCP tool that does not comment passes" "$(mcp_payload mcp__tracker__get_issue "$repo")"

git -C "$repo" checkout -q -b other
check allow "another branch's write-up does not apply" "$(bash_payload 'gh pr create --fill' "$repo")"
git -C "$repo" checkout -q fix/slow-import

cp "$work_dir/passing.md" "$write_up_dir/slow-import.md"
check allow "§INV1-§INV9 filled: gh pr create passes" "$(bash_payload 'gh pr create --fill' "$repo")"

echo "$passes passed, $failures failed"
[ "$failures" -eq 0 ]
