#!/usr/bin/env bash
# Tests hooks/guard-investigation.sh: with a failing investigation write-up for the current branch,
# opening a pull request or posting a comment (gh, gh api, an MCP comment tool) is denied with the
# problems; a passing write-up, no write-up, another branch's write-up, a comment read, any other
# command, or a machine with no jq is allowed silently.
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

build_bash_payload() { jq -n --arg command "$1" --arg cwd "$2" '{tool_name: "Bash", cwd: $cwd, tool_input: {command: $command}}'; }
build_mcp_payload() { jq -n --arg tool "$1" --arg cwd "$2" '{tool_name: $tool, cwd: $cwd, tool_input: {body: "findings"}}'; }

# expect_hook_verdict <allow|deny> <label> <payload> [nojq]
expect_hook_verdict() {
  local expectation=$1 label=$2 payload=$3 mode=${4:-jq} output verdict
  if [ "$mode" = nojq ]; then
    output=$(printf '%s' "$payload" | PATH="$no_jq_bin" bash "$hook" 2>&1)
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

expect_hook_verdict allow "no write-up: gh pr create passes" "$(build_bash_payload 'gh pr create --fill' "$repo")"

cp "$work_dir/failing.md" "$write_up_dir/slow-import.md"
expect_hook_verdict deny "§INV5 missing: gh pr create is denied" "$(build_bash_payload 'gh pr create --fill' "$repo")"
expect_hook_verdict deny "§INV5 missing: gh pr comment is denied" "$(build_bash_payload 'gh pr comment 12 --body-file /tmp/findings.md' "$repo")"
expect_hook_verdict deny "§INV5 missing: gh issue comment is denied" "$(build_bash_payload 'gh issue comment 7 --body hi' "$repo")"
expect_hook_verdict deny "§INV5 missing: a comments api write is denied" "$(build_bash_payload 'gh api repos/acme/shop/issues/7/comments -f body=hi' "$repo")"
expect_hook_verdict deny "§INV5 missing: a leading cd names the checkout" "$(build_bash_payload "cd $repo && gh pr create --fill" "$work_dir")"
expect_hook_verdict allow "§INV5 missing: git status passes" "$(build_bash_payload 'git status' "$repo")"
expect_hook_verdict allow "§INV5 missing: a comments api read passes" "$(build_bash_payload 'gh api repos/acme/shop/pulls/1/comments' "$repo")"
expect_hook_verdict deny "§INV5 missing: a comments api POST is denied" "$(build_bash_payload 'gh api -X POST repos/acme/shop/issues/7/comments --input body.json' "$repo")"
expect_hook_verdict deny "§INV5 missing: a comments api PATCH with no fields is denied" "$(build_bash_payload 'gh api -X PATCH repos/acme/shop/issues/comments/5' "$repo")"
expect_hook_verdict allow "§INV5 missing: gh pr view passes" "$(build_bash_payload 'gh pr view 12' "$repo")"
expect_hook_verdict allow "§INV5 missing: a command from another checkout passes" "$(build_bash_payload 'gh pr create --fill' "$work_dir")"
no_jq_bin="$work_dir/no-jq-bin"
mkdir -p "$no_jq_bin"
for tool in bash cat dirname; do ln -s "$(command -v "$tool")" "$no_jq_bin/$tool"; done
expect_hook_verdict allow "§INV5 missing: with no jq the hook reads nothing and allows" "$(build_bash_payload 'gh pr create --fill' "$repo")" nojq
expect_hook_verdict deny "§INV5 missing: the denial names the problem" "$(build_bash_payload 'gh pr create --fill' "$repo")"
if printf '%s' "$last_output" | jq -r '.hookSpecificOutput.permissionDecisionReason' | grep -qF '§INV5: missing'; then
  echo "ok   the reason carries the checker's problem"; passes=$((passes + 1))
else
  echo "FAIL the reason does not carry the checker's problem: $last_output"; failures=$((failures + 1))
fi
expect_hook_verdict deny "§INV5 missing: an MCP comment tool is denied" "$(build_mcp_payload mcp__tracker__save_comment "$repo")"
expect_hook_verdict allow "§INV5 missing: an MCP tool that lists comments passes" "$(build_mcp_payload mcp__tracker__list_comments "$repo")"
expect_hook_verdict allow "§INV5 missing: a list tool on a server named like a verb passes" "$(build_mcp_payload mcp__postgres__list_comments "$repo")"
expect_hook_verdict allow "§INV5 missing: a get tool naming address comments passes" "$(build_mcp_payload mcp__shop__get_address_comments "$repo")"
expect_hook_verdict deny "§INV5 missing: an add-issue-comment tool is denied" "$(build_mcp_payload mcp__tracker__add_issue_comment "$repo")"
expect_hook_verdict deny "§INV5 missing: a tool with words after comment is denied" "$(build_mcp_payload mcp__tracker__add_comment_to_issue "$repo")"
expect_hook_verdict deny "§INV5 missing: a camelCase comment tool is denied" "$(build_mcp_payload mcp__tracker__addCommentToIssue "$repo")"
expect_hook_verdict deny "§INV5 missing: a comment-first tool name is denied" "$(build_mcp_payload mcp__tracker__comment_create "$repo")"
expect_hook_verdict deny "§INV5 missing: a reply tool is denied" "$(build_mcp_payload mcp__tracker__reply_to_comment "$repo")"
expect_hook_verdict allow "§INV5 missing: an MCP tool that does not comment passes" "$(build_mcp_payload mcp__tracker__get_issue "$repo")"

git -C "$repo" checkout -q -b other
expect_hook_verdict allow "another branch's write-up does not apply" "$(build_bash_payload 'gh pr create --fill' "$repo")"
git -C "$repo" checkout -q fix/slow-import

cp "$work_dir/passing.md" "$write_up_dir/slow-import.md"
expect_hook_verdict allow "§INV1-§INV9 filled: gh pr create passes" "$(build_bash_payload 'gh pr create --fill' "$repo")"

echo "$passes passed, $failures failed"
[ "$failures" -eq 0 ]
