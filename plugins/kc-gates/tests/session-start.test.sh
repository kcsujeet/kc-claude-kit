#!/usr/bin/env bash
# Tests scripts/session-start.sh: every session gets the hand-off reminder, and only the kit's
# maintainer (gh's signed-in user owns the repo the copy came from) gets the lessons line. Uses
# the stub gh in lib/ with fixtures/session-start/ and a throwaway Claude config.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
script="$(dirname "$tests_dir")/scripts/session-start.sh"
fixtures="$tests_dir/fixtures/session-start"
require_jq
use_gh_fixtures "$fixtures"

config="$work_dir/config"
mkdir -p "$config/plugins"
cached="$work_dir/cache/shop-kit/kc-gates/3.1.0"
mkdir -p "$cached"

# Runs the hook for a plugin copy, with gh answering as the given fixture user.
lines_for() {
  local root=$1 routes=$2
  KC_GH_ROUTES="$fixtures/$routes" CLAUDE_CONFIG_DIR="$config" CLAUDE_PLUGIN_ROOT="$root" \
    bash "$script" | wc -l | tr -d ' '
}

printf '{"shop-kit":{"source":{"source":"git","url":"https://github.com/shop-owner/kit.git"}}}' \
  > "$config/plugins/known_marketplaces.json"
expect_eq "cached copy, maintainer: reminder and lessons line" 2 "$(lines_for "$cached" routes-owner.tsv)"
expect_eq "cached copy, another user: reminder only" 1 "$(lines_for "$cached" routes-other.tsv)"
expect_contains "the reminder names the pass" "kc-ready-for-review" \
  "$(KC_GH_ROUTES="$fixtures/routes-other.tsv" CLAUDE_CONFIG_DIR="$config" CLAUDE_PLUGIN_ROOT="$cached" bash "$script")"

printf '{"shop-kit":{"source":{"source":"github","repo":"shop-owner/kit"}}}' \
  > "$config/plugins/known_marketplaces.json"
expect_eq "github-source marketplace, maintainer: lessons line" 2 "$(lines_for "$cached" routes-owner.tsv)"

clone="$work_dir/clone/plugins/kc-gates"
mkdir -p "$clone"
git init -q "$work_dir/clone"
git -C "$work_dir/clone" remote add origin git@github.com:shop-owner/kit.git
expect_eq "copy loaded from a clone, maintainer: lessons line" 2 "$(lines_for "$clone" routes-owner.tsv)"
expect_eq "copy loaded from a clone, another user: reminder only" 1 "$(lines_for "$clone" routes-other.tsv)"

printf 'unrelated\tnone.txt\n' > "$work_dir/routes-none.tsv"
expect_eq "gh signed out: reminder only" 1 \
  "$(KC_GH_ROUTES="$work_dir/routes-none.tsv" CLAUDE_CONFIG_DIR="$config" CLAUDE_PLUGIN_ROOT="$cached" bash "$script" 2>/dev/null | wc -l | tr -d ' ')"

finish
