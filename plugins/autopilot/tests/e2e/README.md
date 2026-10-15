# autopilot end-to-end dry run

Costs model calls. Run by hand before a release. Not picked up by CI (CI runs only the top-level `tests/*.sh`).

`<repo>` is this repository's root; `$SCRATCH` is any scratch directory.

1. `bash <repo>/plugins/autopilot/tests/e2e/make-fixture.sh "$SCRATCH/ap-e2e"`
2. `cd "$SCRATCH/ap-e2e" && claude --plugin-dir <repo>/plugins/autopilot --plugin-dir <repo>/plugins/code-review --plugin-dir <repo>/plugins/conventions --plugin-dir <repo>/plugins/testing`
3. In the session: `/autopilot:run docs/plans/reset.md --dry-run`

Headless instead of steps 2-3 (prompt first, then flags; `--allowedTools` takes one comma-separated string; the high idle ceiling lets the run wait for the background workflow):

```bash
cd "$SCRATCH/ap-e2e" && CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=3600000 claude -p "/autopilot:run docs/plans/reset.md --dry-run" \
  --plugin-dir <repo>/plugins/autopilot --plugin-dir <repo>/plugins/code-review \
  --plugin-dir <repo>/plugins/conventions --plugin-dir <repo>/plugins/testing \
  --permission-mode auto --allowedTools "Workflow,Bash,Read,Write,Edit,Agent,Skill" \
  --max-budget-usd 40 --output-format json < /dev/null > "$SCRATCH/ap-e2e-run.json"
```

Pass when all hold:
- Both units end `done`; U2's worktree branched from U1's branch.
- Every unit's decision log shows a design gate and a final gate by the staff reviewer.
- Each unit ran the code-review gates and the lens reviewers (visible in `/workflows`).
- U2's verifier evidence for AC2 is a screenshot after a reload showing 0.
- `pr-body.md` exists under `.autopilot/runs/<id>/U*/`, and no push or PR happened.

Negative check, on a fresh fixture (repeat step 1 into a new directory): before step 3, edit `docs/plans/reset.md` so U1's scope line (the line under `- Covers: AC3`) reads exactly ``Call the existing `reset(storage)` in counter.js from a test.`` Leave the edit uncommitted (the run allows the plan file to be dirty). counter.js has no `reset`. The staff engineer reads the code before starting the workflow (`skills/run/SKILL.md` step 2), so it should stop there. Pass when either holds:
- The run stops before the workflow (no `.autopilot/runs/` directory, plan unedited), quoting the plan's scope line and the code (counter.js exports only `load` and `add`), and tells the user what to decide: change the plan, or add `reset` to the code first. (Seen on 2026-10-12.)
- Or, if the conflict is only caught inside the workflow: U1 ends `blocked:plan-conflict` with a reason quoting the plan and the code, U2 ends `skipped`, and the report says what the user needs to decide. (This path is also covered by `tests/workflow-sim.test.mjs`, "plan-conflict blocks the unit and skips its dependent".)

Record the run's agent count and wall time from `/workflows` (or the headless JSON's `total_cost_usd` and `duration_ms`) in the release notes.
