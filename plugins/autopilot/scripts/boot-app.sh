#!/usr/bin/env bash
# Boots one unit's copy of the app from its worktree and waits until ready.
#
# Usage: boot-app.sh <config.json> <worktree> <unit-index> <state-dir>
# Input: normalized config from read-config.sh (launch.install, seed, start,
#        ready, ready_timeout_s, ports.base, ports.per_unit).
# Output: {"url": "...", "port": N, "log": "..."} on stdout.
# Exit: 0 ready; 1 the port already serves the ready URL before start (a
#       stale server), install/seed failed, the app exited before ready, or
#       not ready within ready_timeout_s; 2 jq missing.
# The app runs in its own process group (bash job control, set -m:
# https://www.gnu.org/software/bash/manual/html_node/Job-Control-Basics.html)
# so stop-app.sh can end the whole tree with one kill.
set -euo pipefail

command -v jq >/dev/null 2>&1 || { echo "autopilot: jq is required" >&2; exit 2; }
config=$1 worktree=$2 index=$3 state=$4
mkdir -p "$state"
cfg() { jq -r "$1" "$config"; }

port=$(( $(cfg .launch.ports.base) + $(cfg .launch.ports.per_unit) * index ))
port_token='{port}'
sub() { printf '%s' "${1//"$port_token"/$port}"; }
log="$state/app-$index.log"
install=$(cfg .launch.install)
seed=$(cfg .launch.seed)
start=$(sub "$(cfg .launch.start)")
ready=$(sub "$(cfg .launch.ready)")
timeout_s=$(cfg .launch.ready_timeout_s)

# A server already answering would make a failed start look ready.
if curl -fsS --max-time 2 -o /dev/null "$ready" 2>/dev/null; then
  echo "port $port already serves $ready; stop it first" >&2
  exit 1
fi

if [ -n "$install" ] && [ ! -f "$state/installed-$index" ]; then
  (cd "$worktree" && bash -c "$install") >>"$log" 2>&1 || { echo "install failed; see $log" >&2; tail -n 40 "$log" >&2; exit 1; }
  touch "$state/installed-$index"
fi
if [ -n "$seed" ]; then
  (cd "$worktree" && PORT=$port bash -c "$seed") >>"$log" 2>&1 || { echo "seed failed; see $log" >&2; tail -n 40 "$log" >&2; exit 1; }
fi

set -m
(cd "$worktree" && PORT=$port exec bash -c "$start") >>"$log" 2>&1 &
pid=$!
set +m
# ps finds nothing when the start already exited; the loop reports that.
pgid=$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ') || pgid=
printf '%s\n' "${pgid:-$pid}" > "$state/app-$index.pgid"

for _ in $(seq 1 "$timeout_s"); do
  if curl -fsS --max-time 2 -o /dev/null "$ready" 2>/dev/null; then
    jq -cn --arg url "$ready" --argjson port "$port" --arg log "$log" '{url: $url, port: $port, log: $log}'
    exit 0
  fi
  if ! kill -0 "$pid" 2>/dev/null; then
    echo "app exited early; last log lines:" >&2
    tail -n 40 "$log" >&2
    bash "$(dirname "$0")/stop-app.sh" "$state" "$index"
    exit 1
  fi
  sleep 1
done

echo "app not ready at $ready after ${timeout_s}s; last log lines:" >&2
tail -n 40 "$log" >&2
bash "$(dirname "$0")/stop-app.sh" "$state" "$index"
exit 1
