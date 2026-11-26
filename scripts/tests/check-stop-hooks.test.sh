#!/usr/bin/env bash
# Tests scripts/check-stop-hooks.sh in a throwaway repo: a Stop or SubagentStop hook that is not in
# .claude/stop-hooks-allowed.txt fails, a listed one that only records passes, a listed one whose
# script reminds or blocks fails, a listed one with a thin reason fails, and other events are left
# alone. Each branch of the script is broken once below by a case that fails without it.
set -euo pipefail

script="$(cd "$(dirname "$0")/.." && pwd)/check-stop-hooks.sh"
repo=$(mktemp -d)
trap 'rm -rf "$repo"' EXIT
passes=0
failures=0

pass() { echo "ok   $1"; passes=$((passes + 1)); }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }

last_output=""
expect_verdict() {
  local expectation=$1 label=$2 actual=pass
  last_output=$(bash "$script" "$repo" 2>&1) || actual=fail
  if [ "$actual" = "$expectation" ]; then pass "$label"; else fail "$label (expected $expectation, got $actual: $last_output)"; fi
}
expect_output() {
  case "$last_output" in
    *"$2"*) pass "$1" ;;
    *) fail "$1 (no \"$2\" in: $last_output)" ;;
  esac
}

# write_hooks <plugin> <event> <script name>: one hook of that event in the plugin's hooks.json.
write_hooks() {
  mkdir -p "$repo/plugins/$1/hooks" "$repo/plugins/$1/scripts"
  jq -n --arg event "$2" --arg command "\"\${CLAUDE_PLUGIN_ROOT}/scripts/$3\"" \
    '{hooks: {($event): [{hooks: [{type: "command", command: $command, shell: "bash"}]}]}}' > "$repo/plugins/$1/hooks/hooks.json"
}
write_allowed() { mkdir -p "$repo/.claude"; printf '%s\n' "$@" > "$repo/.claude/stop-hooks-allowed.txt"; }
# shellcheck disable=SC2016 # a script's text, written to a file
recorder='#!/usr/bin/env bash
cat > /dev/null
echo "$1" >> "$HOME/misses"
exit 0'
reason="needs the finished reply to record a miss silently for the next turn; prints nothing, never blocks"

# No end-of-turn hook at all.
write_hooks shop PreToolUse guard.sh
rm -f "$repo/.claude/stop-hooks-allowed.txt"
expect_verdict pass "a plugin with no Stop hook passes with no allowlist"

# An unlisted end-of-turn hook fails, for both events.
write_hooks shop Stop remind-orders.sh
expect_verdict fail "an unlisted Stop hook fails"
expect_output "the failure names the plugin, event and hook" "shop: Stop hook 'remind-orders.sh'"
expect_output "the failure says where to put the check instead" "PreToolUse on that action"
write_hooks shop SubagentStop remind-orders.sh
expect_verdict fail "an unlisted SubagentStop hook fails"
write_allowed "# comment only"
expect_verdict fail "an allowlist with no entry for it still fails"

# A listed one that only records passes.
printf '%s\n' "$recorder" > "$repo/plugins/shop/scripts/remind-orders.sh"
write_hooks shop Stop remind-orders.sh
write_allowed "shop Stop remind-orders.sh $reason"
expect_verdict pass "a listed Stop hook that only records passes"
write_hooks shop SubagentStop remind-orders.sh
write_allowed "shop SubagentStop remind-orders.sh $reason"
expect_verdict pass "a listed SubagentStop hook that only records passes"
write_hooks shop Stop remind-orders.sh
write_allowed "shop SubagentStop remind-orders.sh $reason"
expect_verdict fail "a listing for the other event does not cover it"
write_allowed "other Stop remind-orders.sh $reason"
expect_verdict fail "a listing for another plugin does not cover it"
write_allowed "shop Stop remind-orders.sh.bak $reason"
expect_verdict fail "a listing for a different hook name does not cover it"

# The reason must say something.
write_allowed "shop Stop remind-orders.sh records state"
expect_verdict fail "a reason of three words fails"
expect_output "the failure asks for the reason" "fewer than 6 words"
write_allowed "shop Stop remind-orders.sh"
expect_verdict fail "a listing with no reason fails"

# A listed script may not remind or block.
write_allowed "shop Stop remind-orders.sh $reason"
for text in "echo '{\"decision\": \"block\"}'" "jq -Rsc '{decision: \"block\", reason: .}'" 'exit 2' "echo '{\"additionalContext\": \"x\"}'" "echo '{\"systemMessage\": \"x\"}'" "echo '{\"permissionDecision\": \"deny\"}'"; do
  printf '#!/usr/bin/env bash\n%s\n' "$text" > "$repo/plugins/shop/scripts/remind-orders.sh"
  expect_verdict fail "a listed script holding '$text' fails"
done
expect_output "the failure says it may only record" "may only record state"
printf '%s\n' "$recorder" > "$repo/plugins/shop/scripts/remind-orders.sh"
expect_verdict pass "the recorder passes again"

# Other events are left alone.
cat > "$repo/plugins/shop/hooks/hooks.json" <<'JSON'
{"hooks": {"UserPromptSubmit": [{"hooks": [{"type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}/scripts/remind.sh\""}]}], "PostToolUse": [{"hooks": [{"type": "command", "command": "x.sh"}]}]}}
JSON
rm -f "$repo/.claude/stop-hooks-allowed.txt"
expect_verdict pass "UserPromptSubmit and PostToolUse hooks need no listing"

# A command with no path is matched by its whole name; a prompt hook by its type.
cat > "$repo/plugins/shop/hooks/hooks.json" <<'JSON'
{"hooks": {"Stop": [{"hooks": [{"type": "prompt", "prompt": "Did you finish?"}]}]}}
JSON
expect_verdict fail "an unlisted prompt hook on Stop fails"

# A second plugin is checked on its own.
write_hooks shop Stop remind-orders.sh
write_allowed "shop Stop remind-orders.sh $reason"
write_hooks storefront Stop remind-carts.sh
expect_verdict fail "a second plugin's unlisted Stop hook fails"
expect_output "the failure names the second plugin" "storefront: Stop hook 'remind-carts.sh'"

# A hooks.json that cannot be read fails the check instead of passing it.
printf '{not json' > "$repo/plugins/storefront/hooks/hooks.json"
write_hooks shop Stop remind-orders.sh
expect_verdict fail "a malformed hooks.json fails"
expect_output "the failure says it cannot be read" "storefront: hooks.json cannot be read"
printf '{"hooks": {"Stop": [{"matcher": "x"}]}}' > "$repo/plugins/storefront/hooks/hooks.json"
expect_verdict pass "a Stop group with no hooks list has nothing to list"

echo
echo "$passes passed, $failures failed"
[ "$failures" -eq 0 ]
