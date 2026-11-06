#!/usr/bin/env bash
# Tests scripts/lib/hook-input.sh directly: split_segments cuts at every separator, quotes or not,
# so a guard sees each command a wrapper runs.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
# shellcheck source=../scripts/lib/hook-input.sh
. "$(dirname "$tests_dir")/scripts/lib/hook-input.sh"

# --- the guards' split ----------------------------------------------------------------------------
expect_eq "split_segments cuts inside quotes too, so a wrapper's commands each get a segment" \
  "$(printf 'bash -c "git status\n git diff"')" "$(split_segments 'bash -c "git status; git diff"')"

finish
