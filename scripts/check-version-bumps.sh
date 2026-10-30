#!/usr/bin/env bash
# Fails when a plugin changed since <base> without a higher version in its plugin.json.
#
# Installed plugins update only when their version goes up
# (https://code.claude.com/docs/en/plugins/loading.md#versions-and-updates), so a merged change
# without a bump never reaches anyone. A plugin new since <base> passes.
#
# Usage: scripts/check-version-bumps.sh <base-ref>
set -euo pipefail

base=${1:?usage: scripts/check-version-bumps.sh <base-ref>}
merge_base=$(git merge-base "$base" HEAD)
status=0

version_at() {
  # A manifest missing at that commit prints nothing.
  { git show "$1:$2" 2>/dev/null || true; } | sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1
}

for dir in plugins/*/; do
  plugin=${dir%/}
  if git diff --quiet "$merge_base" HEAD -- "$plugin"; then
    continue
  fi
  manifest="$plugin/.claude-plugin/plugin.json"
  before=$(version_at "$merge_base" "$manifest")
  after=$(version_at HEAD "$manifest")
  if [ -z "$before" ]; then
    echo "ok   $plugin: new plugin at $after"
  elif [ "$before" != "$after" ] && [ "$(printf '%s\n%s\n' "$before" "$after" | sort -V | tail -n 1)" = "$after" ]; then
    echo "ok   $plugin: $before -> $after"
  else
    echo "FAIL $plugin changed since $base but its version is still $before; bump it in $manifest and add a CHANGELOG entry"
    status=1
  fi
done
exit "$status"
