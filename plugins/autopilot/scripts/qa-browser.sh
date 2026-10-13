#!/usr/bin/env bash
# Gives QA agents an isolated, pinned Playwright: one browser process per
# script run, so parallel personas never share a profile.
# Playwright library: https://playwright.dev/docs/library
#
# Usage: qa-browser.sh ensure | run <script.cjs> [args...]
# Env:   AUTOPILOT_CACHE (default $HOME/.cache/autopilot)
# Output: ensure prints the node_modules path on stdout; run passes through the
#         script's stdout. Install logs go to stderr only.
# Exit:  0 ok; 1 usage or install failure; run exits with the script's status.
# Concurrency: installs are serialized with a mkdir lock, so parallel callers on
# a cold cache wait for one install instead of racing npm into one directory.
set -euo pipefail
readonly PLAYWRIGHT_VERSION='1.64.0'
readonly LOCK_WAIT_SECONDS=900
root="${AUTOPILOT_CACHE:-$HOME/.cache/autopilot}"
cache="$root/playwright-$PLAYWRIGHT_VERSION"
lock="$cache.lock"

install_pinned() {
  mkdir -p "$cache"
  (
    cd "$cache"
    [ -f package.json ] || npm init -y >&2
    npm i --no-audit --no-fund "playwright@$PLAYWRIGHT_VERSION" >&2
    PLAYWRIGHT_BROWSERS_PATH="$cache/browsers" npx --no-install playwright install chromium >&2
  )
  touch "$cache/.ready"
}

ensure() {
  if [ ! -f "$cache/.ready" ]; then
    mkdir -p "$root"
    waited=0
    until mkdir "$lock" 2>/dev/null; do
      [ -f "$cache/.ready" ] && break
      if [ "$waited" -ge "$LOCK_WAIT_SECONDS" ]; then
        echo "autopilot: timed out waiting for $lock (remove it if stale)" >&2
        exit 1
      fi
      sleep 1
      waited=$((waited + 1))
    done
    # Here we hold the lock unless the loop broke out because .ready appeared.
    if [ ! -f "$cache/.ready" ]; then
      trap 'rmdir "$lock" 2>/dev/null || true' EXIT
      install_pinned
    fi
    rmdir "$lock" 2>/dev/null || true
    trap - EXIT
  fi
  printf '%s\n' "$cache/node_modules"
}

case "${1:-}" in
  ensure) ensure ;;
  run)
    shift
    modules=$(ensure)
    NODE_PATH="$modules" PLAYWRIGHT_BROWSERS_PATH="$cache/browsers" exec node "$@"
    ;;
  *) echo "usage: qa-browser.sh ensure | run <script.cjs> [args...]" >&2; exit 1 ;;
esac
