#!/usr/bin/env bash
# Tests scripts/check-loaded-version.sh against a throwaway Claude config whose
# installed_plugins.json the tests rewrite, and checks that every plugin in the kit runs it.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
script="$(dirname "$tests_dir")/scripts/check-loaded-version.sh"
repo_root=$(cd "$tests_dir/../../.." && pwd)
if ! command -v jq >/dev/null 2>&1; then
  echo "FAIL jq is required to run these tests"
  exit 1
fi

config="$work_dir/config"
data="$work_dir/data"
cache="$config/plugins/cache/shop-kit/kc-gates"
mkdir -p "$config/plugins"

# Writes installed_plugins.json with kc-gates installed at each given version (one entry per
# version, as installs at different scopes are), and one unrelated plugin.
write_installed_plugins() {
  local entries="[]" version
  for version in "$@"; do
    entries=$(jq -c --arg v "$version" --arg path "$cache/$version" \
      '. + [{scope: "user", installPath: $path, version: $v}]' <<< "$entries")
  done
  jq -n --argjson gates "$entries" --arg other "$config/plugins/cache/elsewhere/other/1.0.0" '{version: 2, plugins: {
    "kc-gates@shop-kit": $gates,
    "other@elsewhere": [{scope: "user", installPath: $other, version: "1.0.0"}]}}' \
    > "$config/plugins/installed_plugins.json"
}

# Runs the hook for session <id>, with the plugin loaded from <root>. Extra VAR=value arguments
# override the environment.
run_check() {
  local session=$1 root=$2
  shift 2
  printf '{"session_id":"%s"}' "$session" \
    | env CLAUDE_CONFIG_DIR="$config" CLAUDE_PLUGIN_DATA="$data" CLAUDE_PLUGIN_ROOT="$root" "$@" \
      bash "$script"
}

behind_line() {
  echo "This session runs kc-gates $1, but $2 is installed: its newer rules aren't active here until the person types /reload-plugins or starts a new session. Ask them for it before a review pass or other work kc-gates drives."
}

write_installed_plugins 3.1.0
expect_eq "the loaded version is the installed one: says nothing" "" "$(run_check s1 "$cache/3.1.0")"

write_installed_plugins 3.1.1
expect_eq "a newer version installed: says which, and asks for /reload-plugins" \
  "$(behind_line 3.1.0 3.1.1)" "$(run_check s1 "$cache/3.1.0")"
expect_eq "says it once per session, not on every message" "" "$(run_check s1 "$cache/3.1.0")"
expect_eq "a session started after /clear or /branch hears it too" \
  "$(behind_line 3.1.0 3.1.1)" "$(run_check s2 "$cache/3.1.0")"

write_installed_plugins 3.1.2
expect_eq "a newer version again: says it again" "$(behind_line 3.1.0 3.1.2)" "$(run_check s1 "$cache/3.1.0")"
expect_eq "after /reload-plugins (the hook's path is the installed one): says nothing" "" \
  "$(run_check s1 "$cache/3.1.2")"

write_installed_plugins 3.1.2 3.1.0
expect_eq "installed at two scopes, one of them the loaded version: says nothing" "" \
  "$(run_check s3 "$cache/3.1.0")"

expect_eq "a copy loaded from a clone, which nothing installed: says nothing, in a session told before too" "" \
  "$(run_check s1 "$work_dir/clone/plugins/kc-gates")"
expect_eq "no session id in the payload: says nothing" "" \
  "$(printf '{}' | CLAUDE_CONFIG_DIR="$config" CLAUDE_PLUGIN_DATA="$data" CLAUDE_PLUGIN_ROOT="$cache/3.0.0" bash "$script")"
expect_eq "no plugin data directory: says nothing" "" "$(run_check s5 "$cache/3.0.0" CLAUDE_PLUGIN_DATA=)"

# Every plugin in the kit registers the hook, and its copy of the script is kc-gates' file.
for plugin_dir in "$repo_root"/plugins/*/; do
  plugin=$(basename "$plugin_dir")
  registered=$(jq -r '[.hooks.UserPromptSubmit[]?.hooks[].command] | any(contains("scripts/check-loaded-version.sh"))' \
    "$plugin_dir/hooks/hooks.json" 2>/dev/null || echo false)
  expect_eq "$plugin registers the check on each message" true "$registered"
  expect_eq "$plugin's script is kc-gates' file" true \
    "$(cmp -s "$plugin_dir/scripts/check-loaded-version.sh" "$script" && echo true || echo false)"
done

finish
