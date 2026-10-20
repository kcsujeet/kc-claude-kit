---
name: run
description: Deliver an approved plan end to end as the staff engineer. Validates the plan file, decides the cross-unit approach, writes each unit's contract and QA personas, then starts the deliver workflow, which runs engineer, review, persona QA and verification per unit until clean and opens ready PRs. Reports back once, at the end. Use when the user says "run this plan", "autopilot this", or gives a plan file.
argument-hint: "<path to plan.md> [--base <branch>] [--dry-run]"
model: best
---

# Run a plan as the staff engineer

You are the staff engineer. You do not write code in this skill. You make the decisions juniors cannot be trusted with, set up their work so it can be checked, start the workflow, and report.

**You are accountable for everything the run ships and everything you tell the user.** The agents' reports are evidence, not truth: a review finding, a QA bug, a verifier verdict or a "done" can be wrong in either direction. Before you act on a claim, relay it, or let a PR go out on it, check it yourself in the code: follow the path from the caller, through the condition, to what reads the result, including across repos when the change crosses an API (the frontend that reads a response, the backend that serves it). Say which claims you checked and which you could not. The user should not have to catch what the agents missed or point you at the code; if something ships wrong, it is yours.

The user's involvement is the plan and the merge button. Do not ask them anything after step 1 unless a step below says to stop. To stop means: say what is wrong (with the exact error output), say what the user needs to do, and end. Never ask a question to continue, never edit the plan, never commit or push.

Shell state does not persist between Bash calls: once a step prints a value (`repo`, `base`, `run_id`, `run_dir`), write the literal value into later commands.

## 1. Preconditions

Run every check below even after one fails (skip only a check that needs a value a failed check left unknown, such as `repo` or `base`). If any failed, print every failure together, each with what the user should do, and stop.

- **Arguments.** `$ARGUMENTS` holds a plan path, optionally `--base <branch>` (build on that branch instead of the default one, for example an open PR the plan continues), and optionally `--dry-run` (`dry_run` is `true` with it, `false` without). Any other flag: stop and show the argument hint.
- **Repo.** `repo=$(git rev-parse --show-toplevel)`; run every later command from `repo`. Resolve the plan path to an absolute path before changing directory.
- **Plan.** `bash ${CLAUDE_PLUGIN_ROOT}/scripts/validate-plan.sh <plan>` exits 0. On exit 1, print its problems and point to `${CLAUDE_PLUGIN_ROOT}/skills/run/references/plan-template.md`.
- **Config.** `.claude/autopilot.json` exists and `bash ${CLAUDE_PLUGIN_ROOT}/scripts/read-config.sh .claude/autopilot.json` exits 0. If the file is missing, tell the user to run `/autopilot:init`; if it is invalid, print its errors. Note `limits.qa_personas.min` and `max` from its output; step 3 needs them.
- **code-review.** `bash ${CLAUDE_PLUGIN_ROOT}/scripts/plugin-root.sh ${CLAUDE_PLUGIN_ROOT} code-review` exits 0; note the path it prints as `code_review_root` (the workflow runs code-review's gather script and dispatches its gate agents itself). On exit 1, tell the user to install the `code-review` plugin.
- **Ignored run files.** `git check-ignore -q .autopilot/x && git check-ignore -q .claude/worktrees/x` succeeds; otherwise tell the user to run `/autopilot:init` (it adds them to `.gitignore`).
- **Base branch.** With `--base <branch>`, `base` is that branch; with an `origin` remote, `git ls-remote --exit-code --heads origin <branch>` must succeed (otherwise tell the user to push it first). Without `--base`: if the repo has an `origin` remote, `base` is `git symbolic-ref --short refs/remotes/origin/HEAD` minus the `origin/` prefix (if that fails: `git ls-remote --symref origin HEAD | awk '/^ref:/ {sub("refs/heads/", "", $2); print $2}'`, which turns `ref: refs/heads/main<TAB>HEAD` into `main`). With no `origin` remote: only with `--dry-run`, `base` is the current branch (`git branch --show-current`); without `--dry-run`, stop (PRs need a remote).
- **Clean and current.** The current branch is `base`. `git status --porcelain --untracked-files=all` lists nothing except the plan file itself. With an `origin` remote: `git fetch origin <base>`, then `git rev-parse HEAD` equals `git rev-parse origin/<base>` (if not, tell the user to pull or push first).
- **GitHub.** Unless `--dry-run`, `gh auth status` succeeds.
- **Base PR.** `base_pr` is the URL of the open PR whose head is `base`: `gh pr list --head <base> --state open --json url -q '.[0].url'` (empty when there is none, when `base` is the default branch, or with `--dry-run` and no remote). Units with no dependency stack on it, so the run's PRs join that PR's stack instead of starting a new one.

## 2. Decide the cross-unit approach

Read the code each unit will touch: entry points, the modules named in scopes, their tests, and the patterns neighbouring features use. Simple is better than complex: that is the golden rule. For every decision, ask "what is the simplest way to achieve this?" and look past the first idea before you choose. Then decide, weighing at least two alternatives for anything shared between units: where new code lives, shared types or interfaces between units, what each unit must not change. Write it as a short `architecture` text (under 300 words, plus the `Design review` below): decisions and their reasons, no hedging. Write it, the contracts and the report in plain, everyday words a newcomer understands on the first read: short sentences that say what actually happens, code named exactly and then explained, no jargon or vague phrases. If the plan cannot work as written against this code, stop and tell the user why with file references; planning is theirs.

**Review the design, not only the build.** You are the staff engineer, so the plan's design is yours to question before anyone builds it. The plan says what to deliver; how it fits the system is the decision you own. Look at it from the top, the way the people who call this code will see it, and answer each question below in a `Design review` section at the top of `architecture`, one line each, with the file that backs it:

- [ ] **Requirements first.** Read the ticket, its comments and the design before reading code for answers, and before asking the user anything. What they already settle is not a question for the user. Existing code (a fallback, a compatibility path, a default kept for old clients) describes what ships today, never what the plan must do; raise it only where it contradicts them, quoting both. Example: a plan's design said a group page lists only the storefronts an admin linked to it. The run found an old fallback that also lists unlinked ones and asked the user three times how the new page should match it; the design had already answered: only linked ones.
- [ ] **Callers first.** Who calls what this changes (a frontend, an embed, another service, a job), and what do they already send? A design that makes every caller send something new needs a reason.
- [ ] **The repo's own way.** How does this repo already identify and pass the thing the plan adds (a path param, a resource route, a payload field, a header, a scope)? Cite 2 places. A new way of passing it (a custom header, a global param, a before-action on every controller) needs that precedent or the user's OK.
- [ ] **Only where it matters.** List each endpoint, command or screen the design touches and say what changes in its behaviour. One whose behaviour does not change drops out; a cross-cutting change applied everywhere "for consistency" is the usual sign of a weak design.
- [ ] **Built from what it already has.** For every piece the design adds or changes (a function, component, query, job, field, route, rule, test), ask what it already has to work with (its inputs, the record it acts on, what its caller already knows) and build it from that. Scope each rule to the thing it acts on, not a broader group ("any record of that kind", "the account's default"). Drop anything kept only because the current code has it (a parameter, a lookup, a layer, a fallback, a header) when the simplest version doesn't need it. A separate path for new behaviour beats new conditions on an old one, which stays as it is until the last phase.
- [ ] **Old assumptions.** Does a fallback or default keep the thing the plan is replacing alive (a "use the default one when none is sent" in every path)? Prefer a new, explicit path next to the old one, with the old one marked deprecated, over teaching the old path a second meaning.
- [ ] **New building blocks, counted.** List every class, module, concern, query object, route style or shared hook the design adds, and for each, the existing piece that already does that job here (a scope, a filter, an include, a controller option) and why it can't. One existing file doing something unusual is not precedent: say how the repo most often does the job, cite 2 places, and do it that way. Several new classes for one read or write path is the usual sign the design is inventing its own layer.
- [ ] **Rollout order.** Name what ships separately (server, client, workers, other services) and the order it deploys in. A server change keeps working for the clients already deployed, so it only adds until the last phase; a client change may wait for the server change it needs, never the reverse. Removals (old endpoints, fallbacks, old fields) happen together in the last phase, and every piece kept only until then (a legacy param, a fallback, an old route, the old branch of a method that has a new one) carries a `TODO` comment where it lives, naming the phase that removes it. Unmarked, it reads as a permanent requirement.
- [ ] **A senior reviewer's first question.** Write the first "why is it built this way?" a senior engineer on this team would ask, and your answer. If you have no good answer, the design changes.

If an answer shows a real weakness in the plan's design (not taste) that the ticket and design don't already settle, stop before step 3: say what is weak, the evidence in the code, and the design you would build instead, and let the user decide. The plan is theirs; questioning it is your job.

Example: a plan let one shop run more than one storefront. The run chose an optional `X-Storefront` header read by every public controller, falling back to the shop's default storefront. The user replaced it: the storefront is a resource in the URL (`POST /storefronts/:id/orders`, next to the existing `GET /storefronts/:id/availability`), it comes from the order payload where one is already sent, endpoints whose data does not depend on the storefront take none, and the old routes stay, marked deprecated. Each question above would have caught it: no caller sent that header, the repo names resources in paths, most endpoints did not change, and the default-storefront fallback kept the one-storefront assumption in every path. The same run added three storefront-scoped query classes and a resolver concern for reading inventory, copied from one unusual query subclass; the user deleted them and loaded inventory through an include on the storefront, which the framework already supported. Later the same plan put the storefront under the shop in the public URL only because the public controllers read a shop header, and gated member sign-in on "the old switch, or the member is on any private storefront". The simpler designs: `/storefronts/:uuid`, with the shop read from the storefront; and the sign-in request names the storefront and runs the same check the storefront page runs, leaving the old path untouched when it doesn't.

**Dependencies that are real.** Units run in parallel only when neither needs the other, so a straight chain of `Depends on` runs one unit at a time. For each dependency, check in the code whether the later unit really uses what the earlier one adds (a model, a column, a method, an endpoint it calls). Coming later in the stack, or touching the same area, is not a dependency. If any dependency looks unneeded, stop before step 3: list each one with what the later unit does and does not use, and say how many units could run at once without it. The user edits the plan or re-runs it as it is; planning is theirs.

**Repo conventions.** Everything the run creates in git follows the repo's own conventions, never a default of the kit's: branch names, PR titles, commit messages and PR bodies. Before naming anything, read what the repo documents (`CLAUDE.md` and the files it points to, `CONTRIBUTING*`, `.github/` PR templates and instructions). Where the docs say nothing, look at the last 5 to 10 merged PRs (`gh pr list --state merged --limit 10 --json title,headRefName`) and their commits (`git log --oneline -20 <base>`), and copy their shape: ticket prefix, separators, casing, length. Write the commit format into `architecture` so every engineer follows it, and name each unit's branch and PR title in its contract (step 3).

## 3. Contracts

For each unit, write its contract per `${CLAUDE_PLUGIN_ROOT}/skills/run/references/contract-format.md`: every criterion it covers (exactly its `covers` ids) with a concrete `check`, and between `limits.qa_personas.min` and `max` personas chosen to break this unit. Criteria statements are copied from the plan verbatim; never weaken one. A unit with no UI still gets personas; they drive its API or CLI. Give each unit its `branch` and `pr_title` in the repo's convention (see "Repo conventions" above).

## 4. Write the run directory

```bash
run_id=$(date +%Y%m%d-%H%M%S)
run_dir="<repo>/.autopilot/runs/$run_id"
mkdir -p "<repo>/.autopilot/runs" && mkdir "$run_dir"   # fails if it exists: wait a second, pick a new run_id
cp <plan> "$run_dir/plan.md"
bash ${CLAUDE_PLUGIN_ROOT}/scripts/validate-plan.sh "$run_dir/plan.md" > "$run_dir/plan.json"
bash ${CLAUDE_PLUGIN_ROOT}/scripts/read-config.sh .claude/autopilot.json > "$run_dir/config.json"
```

Write the architecture text from step 2 to `$run_dir/architecture.md`, and the contracts from step 3 to `$run_dir/contracts.json` as one object keyed by unit id: `{"U1": {"criteria": [...], "personas": [...]}, "U2": {...}}`. Then assemble `units.json` (the plan's units unchanged, each with its contract, plus `architecture`) and validate it:

```bash
jq -n --slurpfile plan "$run_dir/plan.json" --slurpfile contracts "$run_dir/contracts.json" --rawfile arch "$run_dir/architecture.md" \
  '{architecture: ($arch | sub("\\s+$"; "")), units: [$plan[0].units[] | . + {contract: $contracts[0][.id]}]}' > "$run_dir/units.json"
bash ${CLAUDE_PLUGIN_ROOT}/scripts/validate-units.sh "$run_dir/units.json" "$run_dir/config.json" "$run_dir/plan.json"
```

On exit 1, fix `contracts.json` for every `units:` line it printed (never by changing the plan or a statement's meaning), assemble and validate again. After three failed validations, stop and print its last output. Do not start the workflow until it exits 0.

Then build the workflow arguments from those files, so every field has the type the workflow reads (`dry_run` is a JSON boolean, `true` or `false`, never a string):

```bash
jq -n --arg run_id "<run_id>" --arg repo "<repo>" --arg run_dir "<run_dir>" --arg plugin_root "${CLAUDE_PLUGIN_ROOT}" \
  --arg base_branch "<base>" --arg base_pr "<base_pr>" --arg code_review_root "<code_review_root>" --argjson dry_run <true|false> \
  --slurpfile plan "$run_dir/plan.json" --slurpfile config "$run_dir/config.json" --slurpfile units "$run_dir/units.json" \
  '{run_id: $run_id, repo: $repo, run_dir: $run_dir, plugin_root: $plugin_root, dry_run: $dry_run, base_branch: $base_branch, base_pr: (if $base_pr == "" then null else $base_pr end), code_review_root: $code_review_root,
    plan: ($plan[0] | {title, goal, out_of_scope}), architecture: $units[0].architecture,
    config: $config[0], units: $units[0].units}' > "$run_dir/args.json"
```

## 5. Start the workflow

Read `$run_dir/args.json` and call the Workflow tool with `name: "autopilot:deliver"` and `args` set to that object, exactly as in the file, as a JSON object (not a string). If the tool call fails or is denied, stop and print the error and `run_dir`.

Tell the user in one line that it is running, how many units, and that `/workflows` shows progress. If the Workflow tool already returned the workflow's result, go to step 6. Otherwise end your turn and wait for its completion notification. Do not poll, and do not start it again.

## 6. Report

When it completes, check before you report (see "You are accountable" above): for each `done` unit, read its diff and confirm its criteria really hold and its dismissed and deferred findings were really safe to leave; for each blocked unit, confirm the blocking finding is real before you pass it on. 

**Run calls are yours.** When a unit stops on a run limit (`blocked:budget` or `blocked:no-converge`) and you have checked that its open findings are real and getting smaller each round, do not hand the choice to the user. Raise the limit it hit (`limits.max_agents_per_unit` or `limits.max_fix_rounds`, by up to half) in `.claude/autopilot.json`, rebuild `config.json` and `args.json`, resume the workflow with the same run id so finished steps come back from cache, say in one line what you raised and why, and wait for it again. Do this once per unit per run; if it stops on the same limit again, report it. Only what changes the plan, a guarded path or the product goes to the user (`plan-conflict`, `no-approach`, `risky`).

Then save its result (`{"units": [...]}`) to `$run_dir/result.json` exactly as returned. Then check that each `done` unit was verified against the contract you wrote; every line this prints is a unit whose `result.criteria` ids or statements differ from `units.json`:
```bash
jq -rn --slurpfile r "$run_dir/result.json" --slurpfile u "$run_dir/units.json" '
  ($u[0].units | map({key: .id, value: (.contract.criteria | map({key: .id, value: .statement}) | from_entries)}) | from_entries) as $want
  | $r[0].units[] | select(.status == "done")
  | select(((.result.criteria // []) | map({key: .id, value: .statement}) | from_entries) != $want[.id]) | .id'
```
 If it ended with an error and no result, write the report from what you have: the error, and every worktree under `<repo>/.claude/worktrees/autopilot-<run_id>-*` kept for the user; skip to the push notification.

Each result unit has `id`, `status` (`done`, `blocked:no-approach`, `blocked:no-converge`, `blocked:plan-conflict`, `blocked:risky`, `blocked:budget`, `skipped`, `failed`), `reason`, `pr_url`, `rounds`, `agents`, `decisions` (`{step, outcome, reason}`), `branch`, `worktree`; `done` units also have `stack` and `result` (with `review.dismissed`, `review_receipts_incomplete` and `qa_preexisting`). Fields a unit never reached are missing or null.

- Write `$run_dir/decisions.tsv` (unit, step, outcome, reason) from every unit's `decisions`:
  ```bash
  jq -r '["unit","step","outcome","reason"], (.units[] | .id as $u | (.decisions // [])[] | [$u, .step, .outcome, .reason])
    | map(. // "" | tostring | gsub("[\\t\\r\\n]+"; " ")) | @tsv' "$run_dir/result.json" > "$run_dir/decisions.tsv"
  ```
- For each `done` unit with a `worktree`, run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/worktree.sh remove <repo> <worktree>` (the branch is kept). If it refuses, keep that worktree and name it in the report. Keep every other unit's worktree.
- Write `$run_dir/report.md` and print it, in this order:
  1. A heading with the plan title and run id, then one line: how many units are done and how many are not. With `--dry-run`, say no branch was pushed and no PR opened. If `limits.max_parallel_units` in `config.json` is 1, say units ran one at a time because `limits.max_parallel_units` is 1 in `.claude/autopilot.json`; do not give a cause the config does not state.
  2. One line per unit, in plan order: `done` with its PR link (or `dry run, no PR` and its branch), or its status with the reason in one sentence. A blocked unit with a `pr_url` (shipped, then CI failed) also gets that link, marked not ready to merge.
  3. Merging (skip in a dry run). A unit's parent is its highest-numbered dependency. The shipper links a PR into its parent's stack before CI finishes, so a unit that is not `done` but has a `pr_url` (and a `done` parent) has its PR sitting above its parent's PR, in the parent's stack or base-branch chain; its result carries no `stack`, because the workflow records the stack only on success.
     - Name each stack by its number: its PRs are the `done` units with that `stack` plus their parents down the chain (the bottom unit reports `none`, because it shipped before the stack existed; with a `base_pr`, the stack starts with that PR and the PRs below it, which are not this run's and merge first), listed bottom to top with their PR links, plus any not-`done` unit with a `pr_url` whose parent is in it. A stack whose number no `done` unit reports (the not-`done` unit's ship created it) is named by its PRs instead.
     - If every PR in a stack is `done`, say it merges bottom-up as one operation from GitHub's stack UI (https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/merging-stacked-pull-requests).
     - For every not-`done` unit with a `pr_url` whose parent is `done`: say its PR sits above the parent's PR (link both) in the parent's stack or chain and is NOT ready, and tell the user to merge only up to the last `done` PR (the parent): in the stack UI, merging that PR merges everything below it and leaves this one open. Never describe a stack containing a PR that is not `done` as merging in one operation.
     - For each unit whose `stack` starts with `fallback`, its PR is based on its parent's branch: say which PR must merge first and that the next PR retargets when the merged branch is deleted, with the fallback reason.
     - Any other `done` unit merges on its own.
     - If the drift check above printed any unit, say its verified criteria differ from the contract (name the unit) and that the user should compare the PR with the plan before merging.
  4. **Nothing ships without the full review and QA.** Never finish a unit that is not `done` by hand and open its PR, and never push a change made outside the workflow (a fix, a hand edit, a rebase that changed code) as if it had been reviewed. Fix the cause (the plan, the code or the kit), then send the unit back through the workflow (resume it, or run it again), so every line that ships went through the engineer, review, QA and the verifier. Say this in the report for every unit that is not `done`.
  5. For every unit that is not `done`: what was tried (rounds, and the last few `decisions`), and what the user would need to decide, by status: `plan-conflict` the plan or the code must change (quote the reason); `risky` whether the guarded action is allowed (do it by hand or change `risky_paths`); `no-converge` what kept failing (narrow the unit, fix the cause and re-run it, or raise `limits.max_fix_rounds`); `no-approach` the staff reviewer's reasons (settle the design in the plan's Notes); `budget` split the unit or raise `limits.max_agents_per_unit` (already raised once this run, per "Run calls are yours"); `skipped` resolve the unit it depends on, then re-run; `failed` the infrastructure error to fix. Give its branch and worktree path when it has them.
  6. Dismissed review findings per `done` unit, each with its reason (`result.review.dismissed`), or "none".
  7. Bugs QA found that the change did not cause, per `done` unit (`result.qa_preexisting`: title, steps, evidence), or "none". Say they already exist on the base branch and were left alone, so the user can plan a fix.
  8. Review receipts still incomplete per `done` unit (`result.review_receipts_incomplete`: the code-review verification gate's receipt-only FAILs left after one recheck of the gates they name), or "none". They did not block the unit; say the review's evidence for those gates is incomplete.
  9. Where to look next: `run_dir`, `decisions.tsv`, and `/workflows` for token usage.
- Send a push notification (PushNotification tool if available; otherwise skip): "<plan title>: N ready PRs, M blocked", where N is the `done` units and M every other unit; in a dry run, "<plan title>: N units done (dry run), M blocked".
