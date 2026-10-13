#!/usr/bin/env bash
# Stops the app boot-app.sh started for a unit by killing its process group.
#
# Usage: stop-app.sh <state-dir> <unit-index>
# Output: none. Exit: always 0 (stopping an app that is not running is fine).
# A pgid file that is empty, not a number, 0 or 1 (kill -- -0 is the caller's
# own group, -1 every process it may signal), or names this script's own
# process group, is removed without killing anything.
set -uo pipefail

file="${1:-}/app-${2:-}.pgid"
[ -f "$file" ] || exit 0
pgid=$(cat "$file")
case "$pgid" in ''|0|1|*[!0-9]*) rm -f "$file"; exit 0 ;; esac
own=$(ps -o pgid= -p "$$" 2>/dev/null | tr -d ' ')
if [ "$pgid" = "$own" ]; then rm -f "$file"; exit 0; fi
kill -TERM -- "-$pgid" 2>/dev/null
for _ in 1 2 3 4 5; do
  kill -0 -- "-$pgid" 2>/dev/null || break
  sleep 1
done
kill -KILL -- "-$pgid" 2>/dev/null
rm -f "$file"
exit 0
