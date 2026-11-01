#!/usr/bin/env bash
# UserPromptSubmit hook, run in the background: keeps the marketplace this copy was installed from,
# and the plugins installed from it, current during a session. Claude Code's own auto-update runs
# once, minutes after a session's first message
# (https://code.claude.com/docs/en/plugins/loading#when-auto-update-runs), so a change merged after
# that, from any session or from GitHub, waits for the next session. This compares the
# marketplace's clone with its source at most every ten minutes (KC_UPDATE_INTERVAL_SECONDS) and,
# when the source moved, runs the update a person would: `claude plugin marketplace update`, then
# `claude plugin update` for each plugin installed from it.
#
# It follows Claude Code's own switches: only a marketplace with auto-update on, and nothing while
# DISABLE_UPDATES, DISABLE_AUTOUPDATER or CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC is set, unless
# FORCE_AUTOUPDATE_PLUGINS=1 is too. The running session keeps the versions it loaded;
# check-loaded-versions.sh says when they are behind. A failure is written to
# $CLAUDE_PLUGIN_DATA/update-marketplace.error for that hook to report. Always exits 0.

set -u

plugin_root=${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
config=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
data=${CLAUDE_PLUGIN_DATA:-}
interval=${KC_UPDATE_INTERVAL_SECONDS:-600}

[ -n "$data" ] && command -v jq >/dev/null 2>&1 || exit 0

is_set() { [ -n "${1:-}" ] && [ "$1" != 0 ]; }
if [ "${FORCE_AUTOUPDATE_PLUGINS:-}" != 1 ]; then
  if is_set "${DISABLE_UPDATES:-}" || is_set "${DISABLE_AUTOUPDATER:-}" \
    || is_set "${CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:-}"; then
    exit 0
  fi
fi

# A cached copy sits at <plugins>/cache/<marketplace>/<plugin>/<version>; a copy loaded from a clone
# or with --plugin-dir has no marketplace to update.
marketplace_dir=$(dirname "$(dirname "$plugin_root")")
[ "$(basename "$(dirname "$marketplace_dir")")" = cache ] || exit 0
marketplace=$(basename "$marketplace_dir")
known="$config/plugins/known_marketplaces.json"
[ "$(jq -r --arg m "$marketplace" '.[$m].autoUpdate // false' "$known" 2>/dev/null)" = true ] || exit 0
clone=$(jq -r --arg m "$marketplace" '.[$m].installLocation // empty' "$known" 2>/dev/null)
[ -n "$clone" ] && git -C "$clone" rev-parse --git-dir >/dev/null 2>&1 || exit 0

mkdir -p "$data"
lock="$data/update-marketplace.lock"
mkdir "$lock" 2>/dev/null || exit 0
trap 'rmdir "$lock"' EXIT

stamp="$data/update-marketplace.checked-at"
now=$(date +%s)
last=$(cat "$stamp" 2>/dev/null || echo 0)
[ $((now - last)) -ge "$interval" ] || exit 0
echo "$now" > "$stamp"

error_file="$data/update-marketplace.error"
fail() {
  printf '%s\n' "$1" > "$error_file"
  exit 0
}

source_head=$(git -C "$clone" ls-remote origin HEAD 2>/dev/null | cut -f1)
[ -n "$source_head" ] || fail "couldn't reach the $marketplace marketplace's source to check for updates"
[ "$source_head" = "$(git -C "$clone" rev-parse HEAD)" ] && exit 0

command -v claude >/dev/null 2>&1 || fail "the claude command isn't on the hook's PATH, so $marketplace's plugins weren't updated"
claude plugin marketplace update "$marketplace" >/dev/null 2>&1 \
  || fail "claude plugin marketplace update $marketplace failed"
installed="$config/plugins/installed_plugins.json"
for id in $(jq -r --arg m "$marketplace" '.plugins | keys[] | select(endswith("@" + $m))' "$installed"); do
  scope=$(jq -r --arg id "$id" '.plugins[$id][0].scope // "user"' "$installed")
  claude plugin update "$id" --scope "$scope" >/dev/null 2>&1 || fail "claude plugin update $id failed"
done
rm -f "$error_file"
exit 0
