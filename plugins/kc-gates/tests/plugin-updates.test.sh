#!/usr/bin/env bash
# Tests scripts/check-loaded-versions.sh and scripts/update-marketplace.sh against a throwaway
# Claude config: a marketplace "shop-kit" with two installed plugins, a git clone of its source,
# and a stub claude command that logs each call instead of updating.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
scripts="$(dirname "$tests_dir")/scripts"
if ! command -v jq >/dev/null 2>&1; then
  echo "FAIL jq is required to run these tests"
  exit 1
fi

config="$work_dir/config"
data="$work_dir/data"
mkdir -p "$config/plugins"

# Writes installed_plugins.json: kc-gates and kc-conventions from shop-kit, and one plugin from
# another marketplace, which this plugin never touches.
install() {
  local gates=$1 conventions=$2
  jq -n --arg g "$gates" --arg c "$conventions" '{version: 2, plugins: {
    "kc-gates@shop-kit": [{scope: "user", version: $g}],
    "kc-conventions@shop-kit": [{scope: "user", version: $c}],
    "other@elsewhere": [{scope: "user", version: "9.9.9"}]}}' > "$config/plugins/installed_plugins.json"
}

root_for() {
  local version=$1
  mkdir -p "$config/plugins/cache/shop-kit/kc-gates/$version"
  printf '%s' "$config/plugins/cache/shop-kit/kc-gates/$version"
}

# Runs check-loaded-versions.sh <mode> for session <id> with the plugin loaded from <root>.
loaded_versions() {
  local mode=$1 session=$2 root=$3
  printf '{"session_id":"%s"}' "$session" \
    | CLAUDE_CONFIG_DIR="$config" CLAUDE_PLUGIN_DATA="$data" CLAUDE_PLUGIN_ROOT="$root" \
      bash "$scripts/check-loaded-versions.sh" "$mode"
}

# --- check-loaded-versions.sh

root=$(root_for 3.1.0)
install 3.1.0 2.0.0
loaded_versions snapshot s1 "$root"
expect_eq "nothing installed since the session loaded: says nothing" "" "$(loaded_versions check s1 "$root")"

install 3.1.0 2.0.1
behind=$(loaded_versions check s1 "$root")
expect_contains "a plugin updated on disk: names it with both versions" "kc-conventions 2.0.0 → 2.0.1" "$behind"
expect_contains "and asks for /reload-plugins" "/reload-plugins" "$behind"
expect_eq "says it once per version, not on every message" "" "$(loaded_versions check s1 "$root")"

install 3.1.0 2.0.2
expect_contains "a newer version again: says it again" "kc-conventions 2.0.0 → 2.0.2" "$(loaded_versions check s1 "$root")"

install 3.1.1 2.0.2
reloaded=$(root_for 3.1.1)
expect_eq "after /reload-plugins (this plugin's own path moved): says nothing" "" "$(loaded_versions check s1 "$reloaded")"
install 3.1.1 2.0.3
expect_contains "and compares with what the reload loaded" "kc-conventions 2.0.2 → 2.0.3" \
  "$(loaded_versions check s1 "$reloaded")"

expect_eq "a session with no snapshot (it started before the hook): says nothing at first" "" \
  "$(loaded_versions check s2 "$reloaded")"

printf 'claude plugin update kc-gates@shop-kit failed\n' > "$data/update-marketplace.error"
failed=$(loaded_versions check s2 "$reloaded")
expect_contains "an update that failed in the background: reports it" "kc-gates@shop-kit failed" "$failed"
expect_eq "and only once" "" "$(loaded_versions check s2 "$reloaded")"
rm "$data/update-marketplace.error"

clone_copy="$work_dir/clone/plugins/kc-gates"
mkdir -p "$clone_copy"
expect_eq "a copy loaded from a clone, not installed from a marketplace: says nothing" "" \
  "$(loaded_versions check s3 "$clone_copy")"

# --- update-marketplace.sh

source_repo="$work_dir/source"
git init -q "$source_repo"
git -C "$source_repo" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m one
marketplace_clone="$config/plugins/marketplaces/shop-kit"
git clone -q "$source_repo" "$marketplace_clone"
known() {
  jq -n --arg loc "$marketplace_clone" --argjson auto "$1" \
    '{"shop-kit": {installLocation: $loc, autoUpdate: $auto}}' > "$config/plugins/known_marketplaces.json"
}
known true
install 3.1.0 2.0.0

stub_bin="$work_dir/bin"
mkdir -p "$stub_bin"
claude_log="$work_dir/claude-calls.log"
printf '#!/usr/bin/env bash\necho "$*" >> "%s"\n' "$claude_log" > "$stub_bin/claude"
chmod +x "$stub_bin/claude"

# Runs update-marketplace.sh with a fresh throttle and the stub claude first on PATH; extra
# arguments are VAR=value settings for the run. Prints the claude calls it made.
update_calls() {
  rm -f "$data/update-marketplace.checked-at" "$claude_log"
  touch "$claude_log"
  env PATH="$stub_bin:$PATH" CLAUDE_CONFIG_DIR="$config" CLAUDE_PLUGIN_DATA="$data" \
    CLAUDE_PLUGIN_ROOT="$root" FORCE_AUTOUPDATE_PLUGINS= DISABLE_UPDATES= DISABLE_AUTOUPDATER= \
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC= "$@" bash "$scripts/update-marketplace.sh"
  cat "$claude_log"
}

expect_eq "source unchanged: updates nothing" "" "$(update_calls)"

git -C "$source_repo" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m two
expect_eq "source moved: updates the marketplace, then each plugin installed from it, at its scope" \
  "plugin marketplace update shop-kit
plugin update kc-conventions@shop-kit --scope user
plugin update kc-gates@shop-kit --scope user" "$(update_calls)"

: > "$claude_log"
env PATH="$stub_bin:$PATH" CLAUDE_CONFIG_DIR="$config" CLAUDE_PLUGIN_DATA="$data" CLAUDE_PLUGIN_ROOT="$root" \
  bash "$scripts/update-marketplace.sh"
expect_eq "checked less than ten minutes ago: doesn't check again" "" "$(cat "$claude_log")"

known false
expect_eq "auto-update off for the marketplace: updates nothing" "" "$(update_calls)"
known true

expect_eq "DISABLE_AUTOUPDATER set: updates nothing" "" "$(update_calls DISABLE_AUTOUPDATER=1)"
expect_contains "unless FORCE_AUTOUPDATE_PLUGINS=1 is set too" "plugin marketplace update shop-kit" \
  "$(update_calls DISABLE_AUTOUPDATER=1 FORCE_AUTOUPDATE_PLUGINS=1)"

rm "$stub_bin/claude"
no_claude_path="$stub_bin:$(dirname "$(command -v git)"):$(dirname "$(command -v jq)"):/usr/bin:/bin"
update_calls PATH="$no_claude_path" >/dev/null
expect_contains "no claude command: records why, for the check to report" "isn't on the hook's PATH" \
  "$(cat "$data/update-marketplace.error" 2>/dev/null)"
rm -f "$data/update-marketplace.error"

git -C "$marketplace_clone" remote set-url origin "$work_dir/missing"
update_calls >/dev/null
expect_contains "source unreachable: records it" "couldn't reach" "$(cat "$data/update-marketplace.error" 2>/dev/null)"

finish
