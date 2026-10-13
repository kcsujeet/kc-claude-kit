# Contract and config formats

## Contract (one per unit, inside units.json)

```json
{
  "criteria": [
    {"id": "AC2", "statement": "Picking a saved reply inserts its text at the cursor.",
     "check": {"kind": "test", "how": "composer test: picking a reply inserts its text at the caret position"}},
    {"id": "AC3", "statement": "An empty picker shows \"No saved replies yet\".",
     "check": {"kind": "ui", "how": "log in as a user with no replies, open the composer picker, read the empty state"}}
  ],
  "personas": [
    {"name": "first-time agent on a slow laptop", "goals": "send a reply fast", "behaviour": "double-clicks, uses the mouse, narrow window"},
    {"name": "power user", "goals": "reuse ten replies an hour", "behaviour": "keyboard only, pastes long text, opens the picker repeatedly"},
    {"name": "careless user", "goals": "get it done", "behaviour": "submits empty, refreshes mid-flow, uses back"}
  ]
}
```

- `check.kind`: `test` (a test proves it), `ui` (walk a flow in the browser), `data` (read a stored value back). A criterion a user can see gets `ui` even if a test also covers it.
- Personas come from who the criteria affect, with behaviours chosen to break this unit: between `limits.qa_personas.min` and `max`. Units with no UI get personas that drive the API or CLI the same way.

Rules `scripts/validate-units.sh` enforces (it is the authority; the deliver workflow trusts its result):
- `criteria` ids are exactly the unit's `covers` ids, once each; each `statement` is the plan's text, character for character.
- Every `check` has `kind` `test`, `ui` or `data` and a non-empty `how`. `how` names the concrete thing: the test file and case, the flow with its starting state, or the stored value and how to read it.
- `personas` count is between `limits.qa_personas.min` and `max`; each has non-empty `name`, `goals` and `behaviour`; names are unique within the unit.

## units.json

```json
{
  "architecture": "<the cross-unit decisions and their reasons>",
  "units": [
    {"id": "U1", "index": 0, "title": "...", "depends_on": [], "covers": ["AC1"], "scope": "...",
     "contract": {"criteria": [], "personas": []}}
  ]
}
```

Each unit is the `validate-plan.sh` unit unchanged (same order and fields) plus its `contract`.

## Config (.claude/autopilot.json)

```json
{
  "launch": {"install": "bun install", "start": "bun run dev --port {port}", "ready": "http://localhost:{port}/health",
             "seed": "bun run db:seed", "ready_timeout_s": 120, "ports": {"base": 4100, "per_unit": 10},
             "login": {"url": "/login", "user_env": "AUTOPILOT_QA_USER", "password_env": "AUTOPILOT_QA_PASSWORD"}},
  "checks": ["bun run lint", "bun run typecheck", "bun test"],
  "risky_paths": [],
  "review": {"extra_agents": []},
  "limits": {"max_fix_rounds": 4, "max_parallel_units": 4, "qa_personas": {"min": 3, "max": 5}, "max_agents_per_unit": 200},
  "models": {"workers": "sonnet", "staff": "best"}
}
```
Only `launch.start`, `launch.ready` and `checks` are required; `read-config.sh` fills the rest.
