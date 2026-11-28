#!/usr/bin/env bash
# SessionStart hook: what every session should know from kc-gates, printed as context.
#
# 1. Everyone: kc-self-correct reviews and fixes your own change; kc-ready-for-human-review gates the hand-off.
# 2. Everyone: lessons are checks first, prose last.
# 3. The kit's maintainer only: turn feedback worth keeping into kit lessons, shipped as merged
#    PRs. The maintainer is the GitHub user signed in to gh when that user owns the repo this copy
#    came from (the plugin directory's own clone, or its marketplace's source). Anyone else
#    installed the kit to use it, not to change it.
#
# Without jq or gh, only the first two lines print. Always exits 0.

set -u

echo 'Review your own change with /kc-gates:kc-self-correct; /kc-gates:kc-ready-for-human-review gates the first push, PR, ready, reviewer request and review status. Order of work: kc-do-a-task.'

echo "Lessons are checks first: a lint rule, test, script or hook; prose only when no check can hold it (feedback-ledger.sh check enforces it)."

plugin_root=${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
config=${CLAUDE_CONFIG_DIR:-$HOME/.claude}

# owner/repo of where this copy came from. A copy loaded from a clone knows its origin; a cached
# copy sits at cache/<marketplace>/<plugin>/<version>, and its marketplace records the source.
source_repo() {
  local url marketplace
  url=$(git -C "$plugin_root" remote get-url origin 2>/dev/null)
  if [ -z "$url" ]; then
    marketplace=$(basename "$(dirname "$(dirname "$plugin_root")")")
    url=$(jq -r --arg m "$marketplace" '.[$m].source | .repo // .url // empty' \
      "$config/plugins/known_marketplaces.json" 2>/dev/null)
  fi
  printf '%s' "$url" | sed -E 's#^(https://github\.com/|git@github\.com:)##; s#\.git$##'
}

repo=$(source_repo)
user=$(gh config get user -h github.com 2>/dev/null)
case "$repo" in
  "$user"/*) ;;
  *) exit 0 ;;
esac
[ -n "$user" ] || exit 0

echo "You maintain this kit ($repo). Feedback you act on that passes the look-back's bar becomes a kit lesson, unasked: kc-do-a-task step 6, skill kc-conventions:kc-look-back; the kit's CLAUDE.md says how to write it."
exit 0
