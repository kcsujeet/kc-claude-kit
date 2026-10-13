#!/usr/bin/env bash
# Runs the deliver workflow's control-flow simulation (workflow-sim.test.mjs)
# with Node; no agents are spawned. Exit: 0 all scenarios pass; 1 otherwise.
set -euo pipefail
node "$(cd "$(dirname "$0")" && pwd)/workflow-sim.test.mjs"
