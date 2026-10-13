#!/usr/bin/env bash
# Builds a throwaway repo for an autopilot end-to-end dry run.
# Usage: make-fixture.sh <dir>
# Output: a git repo at <dir> (branch main, one commit) with a static counter
# app, a node --test suite, .claude/autopilot.json and docs/plans/reset.md.
# Exit codes: 0 fixture ready; 1 missing argument or any failed step.
set -euo pipefail
dir=${1:?usage: make-fixture.sh <dir>}
mkdir -p "$dir/.claude" "$dir/docs/plans" "$dir/test"
cd "$dir"
git init -q -b main

cat > index.html <<'HTML'
<!doctype html>
<html><head><meta charset="utf-8"><title>Counter</title></head>
<body>
  <p>Count: <span id="count">0</span></p>
  <button id="add">Add</button>
  <script src="counter.js"></script>
</body></html>
HTML

cat > counter.js <<'JS'
function load(storage) { return Number(storage.getItem('count') || 0) }
function add(storage) { const next = load(storage) + 1; storage.setItem('count', String(next)); return next }
if (typeof document !== 'undefined') {
  const view = document.getElementById('count')
  view.textContent = load(localStorage)
  document.getElementById('add').addEventListener('click', () => { view.textContent = add(localStorage) })
}
if (typeof module !== 'undefined') module.exports = { load, add }
JS

cat > test/counter.test.js <<'JS'
const test = require('node:test')
const assert = require('node:assert')
const { load, add } = require('../counter.js')
const memory = () => { const m = {}; return { getItem: k => m[k] ?? null, setItem: (k, v) => { m[k] = v } } }
test('add increments and persists', () => { const s = memory(); add(s); assert.strictEqual(load(s), 1) })
JS

cat > .claude/autopilot.json <<'JSON'
{"launch":{"start":"python3 -m http.server {port} --bind 127.0.0.1","ready":"http://127.0.0.1:{port}/"},
 "checks":["node --test test/*.test.js"],"limits":{"max_fix_rounds":3,"max_parallel_units":2,"qa_personas":{"min":3,"max":3},"max_agents_per_unit":200}}
JSON

cat > docs/plans/reset.md <<'MD'
# Counter reset

## Goal
Users can reset the counter to zero and it stays reset.

## Acceptance criteria
1. A "Reset" button sets the displayed count to 0.
2. After pressing Reset and reloading the page, the count is still 0.
3. Pressing Add after Reset shows 1.

## Work units
### U1: Reset logic
- Depends on: none
- Covers: AC3
A `reset(storage)` function in counter.js with a test.

### U2: Reset button
- Depends on: U1
- Covers: AC1, AC2
The button in index.html wired to reset.

## Out of scope
- Styling.
MD

printf '.autopilot/\n.claude/worktrees/\n' > .gitignore
git add -A
git -c user.email=t@t -c user.name=t commit -q -m "counter app"
echo "fixture ready at $dir"
