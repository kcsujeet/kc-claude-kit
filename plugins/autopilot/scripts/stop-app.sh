#!/usr/bin/env bash
# Stops the app boot-app.sh started for a unit by killing its process group.
#
# Usage: stop-app.sh <state-dir> <unit-index>
# Output: none. Exit: always 0 (stopping an app that is not running is fine).
set -uo pipefail

file="${1:-}/app-${2:-}.pgid"
[ -f "$file" ] || exit 0
pgid=$(cat "$file")
kill -TERM -- "-$pgid" 2>/dev/null
for _ in 1 2 3 4 5; do
  kill -0 -- "-$pgid" 2>/dev/null || break
  sleep 1
done
kill -KILL -- "-$pgid" 2>/dev/null
rm -f "$file"
exit 0
