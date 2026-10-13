---
name: init
description: Set up a repo for autopilot. Works out how to boot, seed, log in to and check the app, writes .claude/autopilot.json, and proves it by booting the app once. Run once per repo before /autopilot:run, or when the app's dev setup changes.
disable-model-invocation: true
---

# Set up autopilot in this repo

QA agents can only be as good as their ability to run the app. This writes the recipe they use and proves it works. Nothing here is guessed silently: anything you cannot determine, ask the user. If any step fails and you cannot fix it, stop and report; do not continue to later steps.

Run from the repo root. Create a scratch directory once and reuse it for every step: `SCRATCH=$(mktemp -d)` (re-create it in each Bash call that needs it, or write its path down and reuse the literal path, since shell state does not persist).

## Steps

1. **Prerequisites.** Confirm `git`, `jq`, `gh` (and `gh auth status` succeeds), `node`, `curl`, `python3` exist. Name each missing one and stop. Then run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/qa-browser.sh ensure`: it installs the pinned Playwright and, the first time only, downloads a Chromium browser (can take minutes). Stop if it fails.
2. **Discover.** Read, in this order, whatever exists: `.claude/launch.json`, `package.json` scripts, `Procfile*`, `bin/dev`, `Makefile`, `docker-compose*.yml`, `README` setup sections, CI config (`.github/workflows/*`) for the check commands, seed scripts (`db/seeds*`, `scripts/seed*`, `package.json` `seed`). From them derive: `install`, `start` (must take a port; write it with `{port}`), `ready` URL (a health route if one exists, else the root; also with `{port}`), `seed`, test login (route and the env var names; never real credentials), and `checks` (lint, typecheck, tests, exactly as CI runs them). Ask the user for anything you cannot find (for example no start command, or no test login).
3. **Risky paths.** Propose `risky_paths` from the repo layout: migrations directory, auth, payments/billing, infrastructure. Show them to the user; they edit or accept.
4. **Write** `.claude/autopilot.json`. Fields (the validator in `${CLAUDE_PLUGIN_ROOT}/scripts/read-config.sh` is the authority; its header and checks define them):
   - `launch.install` (command, optional), `launch.start` (required, contains `{port}`), `launch.ready` (required URL, contains `{port}`), `launch.seed` (command, optional), `launch.ready_timeout_s` (default 120), `launch.ports` `{base: 4100, per_unit: 10}`, `launch.login` (optional object, for example `{"url": "/login", "user_env": "...", "password_env": "..."}`; env var names only).
   - `checks`: non-empty array of shell commands, run from the repo root.
   - `risky_paths`: array of globs.
   - `review.extra_agents`: array of extra reviewer agent types (default empty).
   - `limits`: `max_fix_rounds` 4, `max_parallel_units` 4, `qa_personas` `{min: 3, max: 5}`, `max_agents_per_unit` 200.
   - `models`: `workers` `"sonnet"`, `staff` `"best"`.

   Only write the fields you have a reason to set; defaults fill the rest.

   **If `.claude/autopilot.json` already exists**, do not overwrite it: read it, work out only the changes discovery suggests, show the user that diff, and write only after their yes. If nothing needs changing, leave it alone.

   **Data isolation (ask the user).** Each unit's app runs in parallel, each in its own worktree. If the app uses a database or other shared state (database, cache, queue, upload dir), every unit needs its own, or parallel units corrupt each other and the user's dev data. Ask how the app isolates data. What `boot-app.sh` actually does: it substitutes `{port}` in `launch.start` and `launch.ready` only. `launch.install` gets neither `{port}` nor `PORT`. `launch.seed` and `launch.start` run with the env var `PORT` set to the unit's port (seed runs on every boot, install once per unit). So a per-unit database name or URL must go in `start` (for example `DATABASE_URL=postgres://localhost/app_{port} bun run dev --port {port}`) and, for `seed`, be built from `$PORT` (for example `DATABASE_URL=postgres://localhost/app_$PORT bun run db:seed`); a per-unit sqlite file works the same way (`app_{port}.db` / `app_$PORT.db`). Make sure the database can be created on demand (put creation in `seed`). Write the user's answer into the recipe. If they cannot isolate data, set `limits.max_parallel_units` to 1 and tell them why.

   Then run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/read-config.sh .claude/autopilot.json > /dev/null` and fix every error it prints until it exits 0. (The guard blocks autopilot agents from writing this file; you are in the main session, so writing it is fine.)
5. **Prove the boot.** First show the user the exact `install`, `seed` and `start` commands and tell them they will run in this checkout (so install and seed may touch a real database if the recipe is not isolated); ask for a yes before booting. Then normalize to the scratch directory and boot unit index 0:
   ```bash
   SCRATCH=$(mktemp -d)   # note the path
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/read-config.sh .claude/autopilot.json > "$SCRATCH/config.json"
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/boot-app.sh "$SCRATCH/config.json" "$PWD" 0 "$SCRATCH/state"
   ```
   It prints `{"url","port","log"}`. Then open the URL with the QA browser: write a short CommonJS script (`$SCRATCH/shot.cjs`, `require('playwright')`) that loads the URL, logs in if `launch.login` is configured (read the credentials from the env vars it names; if they are unset, ask the user to export them in their own shell and re-run; never ask for credential values in chat), and saves a screenshot to `$SCRATCH/shot.png`; run it with `bash ${CLAUDE_PLUGIN_ROOT}/scripts/qa-browser.sh run $SCRATCH/shot.cjs`, then Read the screenshot and confirm the app really rendered (not an error page or login wall). Always stop the app afterwards, even on failure: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/stop-app.sh "$SCRATCH/state" 0`. A boot that fails is the finding: read the `log`, fix the recipe, and repeat steps 4-5, at most 3 attempts in total; after the third failure stop and report what you tried and the last log lines.
6. **Prove the checks.** Run `git status --porcelain` first; if the tree is dirty, warn the user that failures may come from their uncommitted changes. Then, `bash ${CLAUDE_PLUGIN_ROOT}/scripts/run-checks.sh "$SCRATCH/config.json" "$PWD"`. If checks fail on a clean tree, tell the user: autopilot cannot tell its own failures from existing ones until they pass. Do not edit the checks to make them pass unless the user agrees.
7. **Ignore run files.** Add `.autopilot/` and `.claude/worktrees/` to `.gitignore` if missing (create the file if needed; do not duplicate lines).
8. **Commit the config.** Worktrees need `.claude/autopilot.json`. Committing it is best (teammates get it too); `worktree.sh` also copies it into a unit worktree when it is untracked, so leaving it uncommitted works as well. Offer to commit; only if the user says yes, run `git add .claude/autopilot.json .gitignore && git commit -m "chore: set up autopilot" -- .claude/autopilot.json .gitignore` so nothing else is swept in. Never push.
9. **Permissions.** Unattended runs prompt for every new tool call otherwise. Tell the user the two options and let them choose: run `/autopilot:run` in auto permission mode (https://code.claude.com/docs/en/permission-modes), or add allow rules for `Bash`, `Edit`, `Write` and `Workflow(autopilot:deliver)` to the project's `.claude/settings.local.json`. Do not edit permission settings without their yes.
10. **Report**: the config written, what booted and the screenshot, check results, what you could not determine, and whether the config was committed.
