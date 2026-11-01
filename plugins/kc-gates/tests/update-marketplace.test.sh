#!/usr/bin/env bash
# Tests scripts/update-marketplace.sh against a throwaway Claude config: a marketplace "shop-kit"
# whose clone follows a local git source, and a stub claude command that logs each call, failing
# a call that starts with $CLAUDE_STUB_FAILS.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
script="$(dirname "$tests_dir")/scripts/update-marketplace.sh"
if ! command -v jq >/dev/null 2>&1; then
  echo "FAIL jq is required to run these tests"
  exit 1
fi

config="$work_dir/config"
data="$work_dir/data"
project="$work_dir/project"
mkdir -p "$config/plugins" "$project/.claude"
root="$config/plugins/cache/shop-kit/kc-gates/3.1.0"

jq -n --arg root "$root" --arg c "$config/plugins/cache/shop-kit/kc-conventions/2.0.0" \
  --arg o "$config/plugins/cache/elsewhere/other/1.0.0" '{version: 2, plugins: {
    "kc-gates@shop-kit": [{scope: "user", installPath: $root, version: "3.1.0"}],
    "kc-conventions@shop-kit": [{scope: "project", installPath: $c, version: "2.0.0"},
                                {scope: "user", installPath: $c, version: "2.0.0"}],
    "kc-verify@shop-kit": [{scope: "project", installPath: $c, version: "2.0.0"}],
    "other@elsewhere": [{scope: "user", installPath: $o, version: "1.0.0"}]}}' \
  > "$config/plugins/installed_plugins.json"

commit_to() { git -C "$1" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m "$2"; }
source_repo="$work_dir/source"
git init -q -b main "$source_repo"
commit_to "$source_repo" one
clone="$config/plugins/marketplaces/shop-kit"
git clone -q "$source_repo" "$clone"

write_known_marketplaces() {
  jq -n --arg loc "$clone" --argjson auto "$1" '{"shop-kit": {installLocation: $loc, autoUpdate: $auto}}' \
    > "$config/plugins/known_marketplaces.json"
}
write_known_marketplaces true

stub_bin="$work_dir/bin"
mkdir -p "$stub_bin"
claude_log="$work_dir/claude-calls.log"
cat > "$stub_bin/claude" <<STUB
#!/usr/bin/env bash
echo "\$*" >> "$claude_log"
# A call fails when it starts with \$CLAUDE_STUB_FAILS.
case "\$*" in "\${CLAUDE_STUB_FAILS:-//none}"*) exit 1 ;; esac
STUB
chmod +x "$stub_bin/claude"

# Runs the hook as if last checked <age> seconds ago (default: never), with the stub claude first
# on PATH and the switches cleared; extra VAR=value arguments override the environment. Prints
# the hook's own output, then the claude calls it made.
run_update() {
  local age=${1:-never}
  shift || true
  rm -f "$data/update-marketplace.checked-at"
  : > "$claude_log"
  if [ "$age" != never ]; then
    mkdir -p "$data"
    echo $(($(date +%s) - age)) > "$data/update-marketplace.checked-at"
  fi
  printf '{"cwd":"%s"}' "$project" \
    | env PATH="$stub_bin:$PATH" CLAUDE_CONFIG_DIR="$config" CLAUDE_PLUGIN_DATA="$data" CLAUDE_PLUGIN_ROOT="$root" \
      FORCE_AUTOUPDATE_PLUGINS= DISABLE_UPDATES= DISABLE_AUTOUPDATER= CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC= \
      "$@" bash "$script"
  cat "$claude_log"
}

full_update="plugin marketplace update shop-kit
plugin update kc-gates@shop-kit --scope user
plugin update kc-conventions@shop-kit --scope user"
failure_context() {
  jq -cn --arg c "Updating shop-kit's plugins during this session failed: $1. Tell the person; until it's fixed, new versions arrive only with Claude Code's own update when a session starts." \
    '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $c}}'
}

expect_eq "source unchanged: updates nothing" "" "$(run_update)"

commit_to "$source_repo" two
expect_eq "source moved: updates the marketplace, then each plugin installed from it at user scope" \
  "$full_update" "$(run_update)"
expect_eq "looked 599 seconds ago: doesn't look again" "" "$(run_update 599)"
expect_eq "looked 600 seconds ago: looks again" "$full_update" "$(run_update 600)"

write_known_marketplaces false
expect_eq "auto-update off for the marketplace: updates nothing" "" "$(run_update)"
printf '{"extraKnownMarketplaces":{"shop-kit":{"autoUpdate":true}}}' > "$config/settings.json"
expect_eq "turned on in user settings, which win over known_marketplaces.json: updates" "$full_update" "$(run_update)"
printf '{"extraKnownMarketplaces":{"shop-kit":{"autoUpdate":false}}}' > "$project/.claude/settings.local.json"
expect_eq "turned off in the project's local settings, which win over user settings: updates nothing" "" \
  "$(run_update)"
rm "$config/settings.json" "$project/.claude/settings.local.json"
write_known_marketplaces true

for switch in DISABLE_UPDATES DISABLE_AUTOUPDATER CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC; do
  expect_eq "$switch set: updates nothing" "" "$(run_update never "$switch=1")"
  expect_eq "$switch set with FORCE_AUTOUPDATE_PLUGINS=1: updates" "$full_update" \
    "$(run_update never "$switch=1" FORCE_AUTOUPDATE_PLUGINS=1)"
done
expect_eq "DISABLE_UPDATES=0 is off: updates" "$full_update" "$(run_update never DISABLE_UPDATES=0)"

expect_eq "a copy nothing installed (a clone or --plugin-dir): updates nothing" "" \
  "$(run_update never CLAUDE_PLUGIN_ROOT="$work_dir/clone/plugins/kc-gates")"
expect_eq "no plugin data directory: updates nothing" "" "$(run_update never CLAUDE_PLUGIN_DATA=)"

git -C "$clone" checkout -q --detach
expect_eq "clone pinned to a tag or commit: updates nothing" "" "$(run_update)"
git -C "$source_repo" checkout -q -b beta
commit_to "$source_repo" beta-only
git -C "$clone" fetch -q origin
git -C "$clone" checkout -q -b beta origin/beta
commit_to "$source_repo" beta-moved
git -C "$source_repo" checkout -q main
expect_eq "clone on a branch other than the default: follows that branch" "$full_update" "$(run_update)"
# A fresh clone of main, current with its source, for the rest.
rm -rf "$clone"
git clone -q "$source_repo" "$clone"

mv "$clone/.git" "$work_dir/clone.git"
expect_eq "marketplace folder isn't a git clone: updates nothing" "" "$(run_update)"
mv "$work_dir/clone.git" "$clone/.git"
expect_eq "clone current with its source: updates nothing" "" "$(run_update)"

commit_to "$source_repo" three
failed=$(run_update never CLAUDE_STUB_FAILS="plugin update kc-conventions@shop-kit")
expect_eq "one plugin's update fails: still updates the others, and tells Claude which failed" \
  "$(failure_context "claude plugin update failed for kc-conventions@shop-kit")
$full_update" "$failed"
# The clone is current now, as the marketplace update moved it; the failed plugin update still
# has to run.
git -C "$clone" fetch -q origin main
git -C "$clone" reset -q --hard FETCH_HEAD
expect_eq "the same failure again: doesn't tell Claude twice, but retries though the clone is current" \
  "$full_update" "$(run_update never CLAUDE_STUB_FAILS="plugin update kc-conventions@shop-kit")"
expect_eq "the retry succeeds: the failure is cleared" "$full_update
none" "$(run_update; [ -f "$data/update-marketplace.failure" ] && echo kept || echo none)"
expect_eq "and with the clone current and nothing failed, the next look updates nothing" "" "$(run_update)"

commit_to "$source_repo" four
expect_eq "the marketplace update fails: tells Claude, and stops there" \
  "$(failure_context "claude plugin marketplace update shop-kit failed")
plugin marketplace update shop-kit" "$(run_update never CLAUDE_STUB_FAILS="plugin marketplace update shop-kit")"

rm "$stub_bin/claude"
no_claude_path="$(dirname "$(command -v git)"):$(dirname "$(command -v jq)"):/usr/bin:/bin"
expect_eq "no claude command: tells Claude why" "$(failure_context "the claude command isn't on the hook's PATH")" \
  "$(run_update never PATH="$no_claude_path")"

git -C "$clone" remote set-url origin "$work_dir/missing"
expect_eq "source unreachable: tells Claude" "$(failure_context "couldn't reach the marketplace's source")" \
  "$(run_update never PATH="$no_claude_path")"

finish
