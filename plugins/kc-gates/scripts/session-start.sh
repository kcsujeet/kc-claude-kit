#!/usr/bin/env bash
# SessionStart hook: what every session should know from kc-gates, printed as context.
#
# 1. Everyone: run kc-ready-for-review before a PR goes to a reviewer.
# 2. The kit's maintainer only: turn feedback worth keeping into kit lessons, shipped as merged
#    PRs. The maintainer is the GitHub user signed in to gh when that user owns the repo this copy
#    came from (the plugin directory's own clone, or its marketplace's source). Anyone else
#    installed the kit to use it, not to change it.
#
# Without jq or gh, only the first line prints. Always exits 0.

set -u

echo 'Before a PR of yours goes to a reviewer (marking it ready, opening it ready, requesting a reviewer, or moving its ticket to review), run /kc-gates:kc-ready-for-review on it once: at most two rounds, then what is still open goes to the user. Nothing runs per commit or push.'

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

echo "You maintain this kit ($repo). When feedback you act on in any project (a correction, a review comment, a QA finding) shows a habit that would have caught a whole class of mistakes, it becomes a kit lesson in the same session, unasked: generalized as the kit's CLAUDE.md says (the class of mistake first, the case one example of it), checked against its .claude/hand-off-checklist.md before the first commit, in its own PR from a worktree of your clone with the changed plugins' versions raised, and merged once its checks pass."
exit 0
