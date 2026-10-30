# kc-claude-kit

Sujeet's personal Claude Code toolkit for any codebase: portable coding conventions that load while you write, a gate-based code review built on them, and plugins for auditing a repo's instruction setup and verifying a change before calling it done.

| Plugin | What it does |
|---|---|
| `kc-autopilot` | Plan in, PRs out. `/kc-autopilot:kc-run` takes an approved plan file and the staff-engineer `run` skill (on `best`) splits it into units; each unit goes through engineer, code review and lens reviewers, persona QA in a real browser and an independent verifier until clean, then opens a ready PR. You merge. |
| `kc-usage-band` | A row of pills above the prompt: the model, the current git branch, how full the context window is, the 5-hour and 7-day rate limits with their reset times, input, output and cache-read tokens, and the session's cost. The context, 5-hour and 7-day percentages turn amber from 70% and red from 90%. |
| `kc-image-preview` | Thumbnails of the images you paste, above the prompt, instead of bare `[Image #1]` tags: the real picture in Ghostty and kitty, colored cells in other terminals. |
| `kc-conventions` | The conventions themselves, one skill per topic, each with its authoring rules, its review checklist and the scripts that check them. `/kc-conventions:kc-init` installs the rules into a project. |
| `kc-gates` | Reviews a PR, branch or diff with one read-only gate agent per convention topic, and returns a single PASSED or FAILED verdict. Posting to GitHub is a separate skill that only you can run, behind a hook. |
| `kc-instructions` | Audits a repo's instruction setup and proposes what stays in CLAUDE.md, what becomes a path-scoped rule, a skill, or a hook. |
| `kc-verify` | Verification workflows: look at the UI before calling it done, and drive a cross-layer change end to end. |

## Contents

- [Install](#install)
- [Writing code: the conventions](#writing-code-the-conventions)
- [Reviewing code](#reviewing-code)
- [Delivering a plan with autopilot](#delivering-a-plan-with-autopilot)
- [Posting review comments to GitHub](#posting-review-comments-to-github)
- [Adding your repo's own rules](#adding-your-repos-own-rules)
- [Using the skills in Gemini CLI or Antigravity](#using-the-skills-in-gemini-cli-or-antigravity)
- [Script reference](#script-reference)
- [Developing](#developing)

## Install

Add the marketplace, then install the plugins you want:

```
/plugin marketplace add kcsujeet/kc-claude-kit
/plugin install kc-conventions@kc-claude-kit
/plugin install kc-gates@kc-claude-kit
/plugin install kc-instructions@kc-claude-kit
/plugin install kc-verify@kc-claude-kit
/plugin install kc-autopilot@kc-claude-kit
/plugin install kc-usage-band@kc-claude-kit
/plugin install kc-image-preview@kc-claude-kit
```

`kc-gates` declares `kc-conventions` in its `dependencies`, so installing `kc-gates` installs `kc-conventions` too ([plugin dependencies](https://code.claude.com/docs/en/plugin-dependencies)). The review cannot run without it: its gates load their checklists from the conventions skills.

Upgrading `kc-gates` from 1.x: `claude plugin update` does not install the new `kc-conventions` dependency, and `kc-gates` stays disabled with a dependency error until you install it:

```
claude plugin install kc-conventions@kc-claude-kit
```

Then, once in each project you want the conventions in:

```
/kc-conventions:kc-init
```

Most skills trigger on their own:

| Say | Skill |
|---|---|
| "review this PR", "review my changes" | `kc-gates:kc-code-review` |
| "audit my CLAUDE.md", "should this be a skill or a rule" | `kc-instructions:kc-audit` |
| "does this look right" | `kc-verify:kc-ui` |
| "test this end to end" | `kc-verify:kc-e2e` |
| "run this plan", "autopilot this" | `kc-autopilot:kc-run` |
| (the topic comes up) | `kc-conventions:kc-<topic>` |

One skill only runs when you type it: `/kc-autopilot:kc-init`. `/kc-gates:kc-post-review` also loads on its own whenever Claude drafts a PR comment or reply, so drafts follow its rules; posting still needs your explicit go-ahead.

`kc-usage-band` has no skill: once installed, it draws its pills above the prompt in every session.

<img width="1071" height="385" alt="collage-pen-20261003-160636" src="https://github.com/user-attachments/assets/2fbbfb31-4dc5-4d7b-bdaa-96364cf63509" />

It is built on Claude Code's function hooks, an early-access API, so a Claude Code update can change what it can draw. The rate-limit pills appear only on a subscription, after the first response reports the limits; the token pills count from when the session loaded the plugin.

`kc-image-preview` has no skill either: paste an image and a thumbnail labelled with its tag number appears above the prompt. The row clears when you send the prompt or delete the tags, and whatever else draws in that band (`kc-usage-band`'s pills, say) stays below it.

<img width="1038" height="486" alt="collage-pen-20261003-175242" src="https://github.com/user-attachments/assets/db9d3a9a-0060-481b-aae5-fc5214ceb053" />

How the thumbnail is drawn depends on the terminal:

| Terminal | What you see |
|---|---|
| Ghostty (`TERM=xterm-ghostty`) or kitty (`TERM=xterm-kitty`, or `KITTY_WINDOW_ID` set) | The real picture, drawn by the terminal over the kitty graphics protocol. |
| Apple Terminal, and any other terminal without the kitty graphics protocol | Colored half-block cells (`▀`), two pixels per cell, at most 32 columns by 4 rows. You can tell what the image is, but it is blurry, and fine text in a screenshot is not readable. |

Apple Terminal cannot show the actual image: it does not speak the kitty graphics protocol, and given an `Image` element there, Claude Code draws only its text fallback. So the cells are the best a terminal like it can do. The cells are also what you get in these cases:

- **Any terminal the plugin does not detect as Ghostty or kitty**, even one that draws images some other way, such as iTerm2's inline images or sixel. Claude Code's `Image` element speaks the kitty protocol only.
- **Ghostty or kitty with `TERM` changed**, over SSH or inside tmux, which set their own `TERM`. The plugin goes by the variables those terminals set.

And no thumbnails at all:

- **Linux.** Decoding an image relies on macOS's `sips`, because a function hook's environment has no way to decompress a PNG or JPEG.
- **The Claude desktop app.** The plugin draws on the terminal surface only.

Copying an image file in Finder (⌘C on the file) puts the file's icon on the clipboard, not the picture, so ctrl+v pastes the file type's generic icon (a grey "JPG" page, say). `kc-image-preview` checks the clipboard when a new tag appears; if it holds a copied image file, the thumbnail shows the real file, and on send Claude gets a note naming that file so it reads the real image. The icon is still attached to the prompt: a plugin cannot remove an attachment.

It is built on Claude Code's function hooks, like `kc-usage-band`. It reads the prompt every 300ms to spot new tags, and finds each image in Claude Code's paste cache, `<tmp>/<project>/<session>/images/<n>.<ext>`. Neither is a documented contract, so a Claude Code update can move them.

## Writing code: the conventions

Each convention topic is one skill. It holds the rules to write against and the checklist a reviewer ticks, in the same file, so the two cannot drift apart.

| Topic | Scope | Covers |
|---|---|---|
| `naming` | source files | One word per concept, role-not-type names, verb-noun functions, booleans as assertions, unambiguous where read not where declared, named predicates, file names that stand without their path |
| `clarity` | source files | Ternary limits, early returns, comments that earn their place, magic numbers, no defensive coercion |
| `structure` | source files | One responsibility per unit, co-location and promotion, no barrels, named exports, lookup over switch |
| `simplicity` | source files | DRY, YAGNI and KISS; look for what already exists before hand-rolling it |
| `datetime` | source files | No hand-rolled date math, ISO 8601 with offset, truncation accounting, timezone and clock as settings |
| `react` | components, hooks, api | Components own their container, reads and writes in separate hooks, cache-patch before invalidate, form is the source of truth |
| `rails` | Ruby, rake, Gemfile, `db/` | Copy siblings of the same kind, one check in one place, locks before checks, N+1s that preloading does not fix, GETs never write, backfills that know every writer, honest Rails specs |
| `i18n` | source and locale files | Source locale only, grep before adding a key, ICU plurals for countable nouns, never concatenate translations |
| `testing` | source files | Failing test first, never skip a test to reach green, cover the unhappy paths, exact assertions on observable behavior, gates tested both ways |
| `correctness` | source files | Empty, null, zero and boundary inputs; operators and conditions checked for off-by-one and inversion; current dependency arrays and closures; no cast hiding a real mismatch; no regression of a fixed bug |
| `type-safety` | typed languages | No `any`, no silencing casts, parse external input at the boundary, reuse existing types |
| `error-handling` | source files | No empty catch, typed codes, one envelope, messages that say what to do, structured logs |
| `performance` | source files | Filter and paginate in the data layer, no N+1, index with the query, measure and say what you measured |
| `dependencies` | dependency manifests | Ask first, check maintenance signals, exact versions, nothing that duplicates what is installed |

Plus `kc-working-agreement.md`, the one hand-written rule, loaded in every session: ask before assuming, report honestly, write corrections down where they belong.

For React and TypeScript codebases, [bulletproof-react](https://github.com/alan2207/bulletproof-react/blob/master/docs/project-structure.md) is the canonical source for project structure, and the `structure` topic says so explicitly: where the two appear to disagree, that document wins and the rule is what gets corrected.

### Getting the rules loaded

Rules are what Claude Code loads when you open a matching file ([memory](https://code.claude.com/docs/en/memory)), and a plugin cannot ship rules. So the conventions reach your session as rule files you install:

- **Per project:** `/kc-conventions:kc-init` copies the rules into `.claude/rules/`, where each loads only when a matching file is touched. Commit the directory and the project carries its own conventions.
- **Machine-wide:** link them into `~/.claude/rules/`, where they apply to every project on that machine:

  ```bash
  git clone https://github.com/kcsujeet/kc-claude-kit ~/src/kc-claude-kit
  mkdir -p ~/.claude/rules
  for f in ~/src/kc-claude-kit/plugins/kc-conventions/rules/*.md; do ln -s "$f" ~/.claude/rules/; done
  ```

`init` writes a version stamp next to the copies. When the rules are missing or older than the installed plugin, a `SessionStart` hook says so in one line, and it stays silent otherwise. After a plugin update, run `/kc-conventions:kc-init` again. Run `/context` in a new session to confirm what loaded.

Why not let the skills load themselves? Skills accept `paths:`, but measured on Claude Code 2.1.280, a `paths:`-scoped plugin skill is not loaded when you read a matching file, only when the model decides to invoke it. The rule files are generated from the skills, so there is still one source.

## Reviewing code

Ask for a review of a PR, a branch or your working changes. `kc-gates:kc-code-review` then:

1. **Gathers the change:** saves the diff, the head SHA and the changed files.
2. **Checks its scope:** is the PR stacked on another, does it do more than its title says, what constraints does the linked issue set, was a large diff read in full.
3. **Dispatches every gate in parallel.** Each gate is a read-only agent (`Read, Grep, Glob, Bash`, plus `Skill` to recover a topic skill that did not preload) that preloads its conventions skill, runs that topic's scripts over the diff, walks every checklist box, and returns a per-box verdict with evidence. A gate whose topic the diff does not touch still runs and returns `PASS (N/A)` with its reason, so the report always shows every gate.
4. **Verifies the receipts:** the verification gate runs last and checks that every other gate produced the evidence its checklist demands.
5. **Reports one verdict:** PASSED only when every gate passed.

Two rules keep findings honest:

- **Findings cite real lines.** Every line number comes from the citation map (`added-lines.sh`), which lists each added line with its line number in the source file at the head SHA, so a finding never points at a position inside the diff file.
- **Only confirmed findings count.** A confirmed finding fails its gate, and "intentional" or "low-value" is never a reason to hold it back. A finding the gate cannot confirm from the code or the docs is dropped, not softened into a maybe.

### The gates

| Topic | Gate agent | Applies when | Checks, in short |
|---|---|---|---|
| naming | `kc-gates:naming-gate` | every diff | Role names, honest names, extracted boolean chains, names unambiguous where read, verb-led functions, file names |
| clarity | `kc-gates:clarity-gate` | every diff | Ternaries, guard clauses, comments, magic numbers, casts and `any` that lie, defensive coercion |
| structure | `kc-gates:structure-gate` | every diff | One responsibility, co-location, no barrels, dead wrappers, lookups over `switch`, breaking changes named |
| simplicity | `kc-gates:simplicity-gate` | every diff | DRY, YAGNI, KISS; reuse of what already exists, searched by shape as well as by name |
| correctness | `kc-gates:correctness-gate` | every diff | Logic bugs, edge cases (empty, null, zero, boundary, timezone), data matching its declared type at a boundary, no regression of a bug the repo already fixed |
| datetime | `kc-gates:datetime-gate` | diff touches date/time logic | No hand-rolled date math, ISO 8601 with offset, truncation, timezone as an input |
| react | `kc-gates:react-gate` | diff has React/JSX UI code | Bulletproof-react structure, keys, data-fetching hooks, forms, render cost |
| rails | `kc-gates:rails-gate` | diff touches Ruby, rake, Gemfile or `db/` | Sibling shape, Rails conventions, layers, races, N+1s, request risks, backfills, Rails specs |
| i18n | `kc-gates:i18n-gate` | diff touches locale files | Per-key audit table, dedup, ICU plurals, no concatenated translations |
| testing | `kc-gates:testing-gate` | diff changes behavior or tests | New behavior tested, no class-name assertions, exact assertions, gates tested both ways |
| project conventions | `kc-gates:project-conventions-gate` | repo has `.claude/review-conventions.md` | Every rule in the repo's own conventions file; repo rules that override a built-in box are listed |
| verification | `kc-gates:verification-gate` | every diff; runs after the others | Files read at head SHA, findings cite `file:line` and SHA, receipts present, nothing posted |

`type-safety`, `error-handling`, `performance` and `dependencies` guide writing only and have no gate.

If a gate agent is unavailable, for example because the `kc-conventions` dependency failed to load, the review runs that gate as a `general-purpose` agent told to invoke the `kc-conventions:kc-<topic>` skill and follow the same contract, and says so in the report. And if a gate agent starts but its preloaded skill did not load (Claude Code skips a missing preloaded skill silently), the gate invokes the skill itself, and fails with `topic skill unavailable` if that fails too. No gate ever grades a topic from memory.

### What the report looks like

- The gate-status table comes first, listing every gate as PASS, FAIL or N/A, then the findings, then an explicit PASSED or FAILED verdict. One confirmed finding in any gate fails the review.
- Each finding is one line, citing the file, line and head SHA, then the issue and the fix.
- No em dashes anywhere in the output: not in the report, the gate verdicts, drafted comments or replies.

## Delivering a plan with autopilot

`kc-autopilot` turns an approved plan into pull requests. Your only touch points are writing (or agreeing) the plan and pressing merge. In between, the staff-engineer `run` skill (on `best`) splits the plan into units and decides the approach, then a workflow takes each unit through an engineer, `kc-gates`'s gates, lens reviewers, persona QA in a real headless browser and an independent verifier, fixing until clean or giving up with a reason. It depends on `kc-gates`, `kc-conventions` and `testing`, which install with it.

**Once per repo: `/kc-autopilot:kc-init`.** It checks that `git`, `jq`, `gh`, `node` and `curl` are present, installs a pinned Playwright, works out how to install, boot, seed, log in to and check your app, writes `.claude/autopilot.json`, and proves it by booting the app once and running your checks. Data isolation matters here: units run in parallel, each with its own copy of the app, so they share your database unless the recipe isolates it per unit (a database name or file built from the unit's port). If you cannot isolate it, `init` sets `limits.max_parallel_units` to 1.

**Each plan.** Write it from the template at `plugins/kc-autopilot/skills/kc-run/references/plan-template.md` (goal, numbered acceptance criteria, work units with dependencies), then:

```
/kc-autopilot:kc-run docs/plans/x.md
/kc-autopilot:kc-run docs/plans/x.md --dry-run    # everything except pushing and opening PRs
```

You can also say "run this plan". The working tree must be clean, on the base branch and current with `origin`.

**What comes back**, in one report and one push notification:

- Ready PRs, never merged by agents. Units that depend on each other are linked as GitHub native stacked pull requests, falling back to a chain of PRs each based on its parent's branch when the stack API is unavailable. Screenshots are attached when they make the change clearer.
- Blocked units, each with the reason (no approach, did not converge, plan conflict, risky path, budget).
- Bugs QA found that the change did not cause, left alone, so you can plan a fix.

The run's evidence (criteria checks, review decisions, QA results) stays in `.autopilot/runs/<id>/` for the staff engineer to verify. PR descriptions carry only what a reviewer needs, in the repo's own template.

**Parallel units.** Units that do not depend on each other run side by side, up to `limits.max_parallel_units`, each with its own app, data and test database through `launch.unit_env` (per-unit `KEY=value` pairs with `{port}` and `{index}`, set up by `/kc-autopilot:kc-init`). Before it starts, `/kc-autopilot:kc-run` checks that every `Depends on` in the plan is real, because a chain of dependencies runs one unit at a time.

**Models.** Workers run on `sonnet` and the staff roles on `best`, both set in `.claude/autopilot.json` `models` ([model config](https://code.claude.com/docs/en/model-config)). The `run` skill already sets `model: best` for its turn, so the staff engineer runs on the top model whatever your session's `/model` is.

**Size.** A run is bounded by the workflow runtime's cap of 1,000 agents per run ([workflows, Behavior and limits](https://code.claude.com/docs/en/workflows#behavior-and-limits)), and each unit takes up to `limits.max_agents_per_unit` of them, so split very large plans (5 or more units) into several runs.

**Local only.** Every unit runs its app on this machine, on localhost, against your local dev database and services. QA creates and deletes data, so the recipe never points at staging, production or any shared environment, and `read-config.sh` rejects a `launch.ready` URL that is not local.

**Permissions.** An unattended run prompts for every new tool call unless you run in auto mode ([permission modes](https://code.claude.com/docs/en/permission-modes)) or allow `Bash`, `Edit`, `Write` and `Workflow(kc-autopilot:deliver)` in `.claude/settings.local.json`.

**Cost.** It spends real tokens. A 2-unit dry run on the test fixture cost $6 to over $10 and took 8 to 12 minutes, with 75 to 150 agents; most of it is review. To keep it down, a re-review after fixes looks only at the fix commits, with the checks that found something plus correctness, testing and security, and one full review runs before QA. Checks with no file they apply to (React, accessibility, type-safety, dependencies) start no agent, two skeptics judge all serious findings of a round together, and minor findings alone never start a fix round. In your first two or three runs, skim the QA evidence in the run directory to calibrate how far to trust it.

**Start command.** `launch.start` must keep the app in the foreground. A command that backgrounds itself (`docker compose up -d`, `rails s -d`) is reported as "app exited early", and autopilot could not stop it anyway; use the foreground form (`docker compose up`, `rails s`). `init`'s boot check shows this the first time.

**The guard.** A `PreToolUse` hook blocks autopilot's own agents (never your session) from merging, enabling auto-merge, force-pushing, pushing to `main` or `master`, editing the run files or `.claude/autopilot.json`, skipping or deleting tests, and (the engineer) touching risky paths or adding dependencies. It is a guardrail for well-meaning agents, not a sandbox: a script an agent writes and then runs is not inspected. The staff reviewer's final gate on each diff is the backstop.

## Posting review comments to GitHub

The review never posts; its output stays in chat. To turn findings into PR comments, run `/kc-gates:kc-post-review`. Claude also loads it on its own before drafting any PR comment or reply, so drafts are never written from memory; posting still waits for your explicit signal and the approval token. It:

1. Drafts the comments in Conventional Comments format, giving every `suggestion` a brief reason.
2. Runs the drafts through `build-comment-payloads.sh`, which rejects any comment whose file or line is not in the diff.
3. Shows you the drafts and the exact post commands, and waits for a fresh, explicit post signal.

A post only goes through when the same Bash command carries the approval token `KC_REVIEW_POST_APPROVED=1`, typed after your signal. A `PreToolUse` hook in the plugin (`scripts/guard-github-post.sh`) blocks every GitHub review write without it, because an instruction is only context and a hook is what enforces. It covers `gh pr comment`, `gh pr review`, `gh issue comment`, and `gh api` writes to a PR's or issue's comments or reviews. Reads, `gh pr create` and `gh pr merge` pass untouched.

## Before a PR goes to review

`/kc-gates:kc-ready-for-review` is the one pass on your own PR before a person reviews it, so the reviewer finds nothing your rules already say. It runs `kc-code-review`, your repo's hand-off checklist (`.claude/hand-off-checklist.md`: the description, the ticket, paired PRs) and QA, fixes what they find, re-reviews once, and hands anything still open to you instead of looping. Two rounds at most, and nothing runs per commit or push. Claude also runs it on its own when work is about to go to review: a `SessionStart` hook in the plugin puts a one-line reminder in every session, in every project, wherever kc-gates is installed, with nothing to set up per project. If you are the kit's maintainer (the GitHub user signed in to `gh` owns the repo you installed from), the same hook adds a line telling Claude to turn feedback worth keeping into kit lessons, shipped as merged PRs; anyone else installed the kit to use it and doesn't get that line.

It ends in a receipt for the PR's head commit. A second `PreToolUse` hook (`scripts/guard-hand-off.sh`) blocks `gh pr ready`, a ready `gh pr create`, `gh pr edit --add-reviewer` and reviewer requests through `gh api` until that commit has one. To hand off without the pass, tell Claude to skip it; the command then carries `KC_READY_SKIP=1`.

## Adding your repo's own rules

If the repository under review has a `.claude/review-conventions.md`, it becomes an extra gate (`kc-gates:project-conventions-gate`). Use it for project-specific rules: data-layer patterns, UI-library rules, domain helpers, whatever the built-in topics do not know about. Write each rule as a checklist of failure modes with one canonical example path, so the gate can walk it box by box.

On conflict, the repo's rule wins over a built-in convention: the review reports the built-in box as overridden, citing the repo rule, instead of failing it. The repo knows its own context; the kit only knows what is portable.

## Using the skills in Gemini CLI or Antigravity

The skills follow the Agent Skills standard, so other agents can read them. `scripts/export-agent-skills.sh` copies every skill into another tool's skills directory, renamed to `kc-<plugin>-<skill>` (for example `kc-conventions-naming`) because those tools share one flat namespace where bare names like `naming` collide. It rewrites `${CLAUDE_PLUGIN_ROOT}` script paths to the exported location and bundles the scripts the skills call, so they still run.

As a Gemini CLI extension:

```bash
scripts/export-agent-skills.sh --gemini-extension ~/src/kc-claude-kit-gemini/kc-claude-kit
gemini extensions link ~/src/kc-claude-kit-gemini/kc-claude-kit
```

Into an Antigravity workspace or its global skills directory ([Antigravity skills](https://antigravity.google/docs/skills)):

```bash
scripts/export-agent-skills.sh /path/to/repo/.agents/skills
scripts/export-agent-skills.sh ~/.gemini/config/skills
```

What does not carry over:

- Gate agents and hooks are Claude Code features, so another tool runs the gates inline from the skills.
- `kc-post-review` is never exported, since its safety depends on the Claude Code hook.
- `kc-conventions:kc-init` is never exported, since it installs into `.claude/rules/`.

The rewritten paths are absolute, so re-run the export instead of moving its output. The script header lists the remaining limits.

## Script reference

The deterministic steps are scripts, each with fixture tests, so the model runs them instead of retyping commands.

**Review steps** (`plugins/kc-gates/scripts/`, tested against a stub `gh`):

| Script | Does |
|---|---|
| `gather-review.sh (<pr> \| --branch [<base>])` | Saves the diff and changed-file list for a PR or a local branch (base: `origin/HEAD`, then `main`, then `master`) and prints `meta.env` with `HEAD_SHA`, `BASE`, `TITLE`, `DIFF_FILE` and `CHANGED_FILES`; prints the fetch command when the local checkout is not the PR head |
| `scope-facts.sh <pr>` | Prints the facts the scope checks need: author, base, commit and file counts, the author's other open PRs, and each linked issue, with the PR description and issue bodies saved to files |
| `review-threads.sh <pr> [--mine <login>]` | Prints every review comment thread, root then replies, and with `--mine` marks the threads you started and whether the author replied after you (requires `jq`) |
| `build-comment-payloads.sh <drafts.json> <diff> <sha> --pr <n>` | Used by `kc-post-review`: checks each drafted comment's path and line against the diff's hunks, writes one payload per comment, and prints the approval-token commands for you to approve; never posts (requires `jq`) |
| `guard-github-post.sh` | The `PreToolUse` hook that blocks GitHub review writes without the approval token |
| `ready-receipt.sh (write <sha> (--rounds <n> --open <n> \| --after <pass-sha>) \| check <sha>)` | Used by `kc-ready-for-review`: writes or checks the receipt for the commit a pass ended on, under `~/.claude/kc-ready-for-review/` (`KC_READY_DIR` overrides) |
| `guard-hand-off.sh` | The `PreToolUse` hook that blocks handing a PR to review until its head commit has a receipt |

**Convention checks** (`plugins/kc-conventions/`):

| Script | Does |
|---|---|
| `skills/kc-<topic>/scripts/*.sh <diff>` | The sweeps: each prints the added lines that match one check (ternaries, `as` casts, `&&`/`||` chains, nested `if`s, class-name assertions, and so on) as `path:line: text` |
| `scripts/added-lines.sh <diff>` | The citation map: every added line with its line number in the source file |
| `skills/kc-naming/scripts/name-collisions.sh <name>` | A name's whole-word hits in the tracked files |
| `skills/kc-i18n/scripts/locale-duplicates.sh <locale-dir> <value> <leaf-key>` | The two duplicate greps a new locale key needs |
| `scripts/install-rules.sh [--dry-run]` | What `/kc-conventions:kc-init` runs: copies the rules and stamps the plugin version; `--dry-run` lists what an update would replace |
| `scripts/build-rules.sh [--check]` | Regenerates `rules/` from the topic skills; `--check` fails when they drift |

## Developing

The layout and the reasoning behind it, with the docs each decision rests on, are in [`docs/architecture.md`](docs/architecture.md). A topic skill lives at `plugins/kc-conventions/skills/kc-<topic>/SKILL.md`, with its sections in a fixed order: `## Rules`, `## Review checklist`, `## Review detail`, `## Sweeps`. Edit the skill, never `rules/`, which is generated.

Load the working copies instead of the installed plugins. Load both, since `kc-gates` depends on `kc-conventions` and a local copy satisfies the dependency:

```bash
claude --plugin-dir ./plugins/kc-conventions --plugin-dir ./plugins/kc-gates
```

Run what CI runs:

```bash
bash plugins/kc-conventions/scripts/build-rules.sh          # regenerate rules/ after editing a topic skill
bash plugins/kc-conventions/scripts/build-rules.sh --check  # fail if rules/ drifted from the skills
bash plugins/kc-conventions/tests/run-sweeps.sh             # sweep fixtures
bash plugins/kc-conventions/tests/run-lookups.sh            # lookup fixtures
for t in plugins/*/tests/*.sh; do bash "$t"; done        # every plugin's test runners
git ls-files '*.sh' | xargs shellcheck
claude plugin validate . --strict
for p in plugins/*/; do claude plugin validate "$p" --strict; done
```

Evals run each case with and without the plugin and cost model calls, so CI only runs them on demand (the `evals` job, `workflow_dispatch`). Locally:

```bash
claude plugin eval plugins/kc-conventions
claude plugin eval . --eval-dir plugins/kc-gates/evals --scaffold --allow-tools Bash Agent
```

kc-gates runs from the repo root because its cases also load `kc-conventions`, and the eval runner only loads plugins inside its containment root: the target plugin when the target is a plugin, otherwise the directory the eval runs against. Its cases build fixture repos, run git and dispatch gate agents, hence `--scaffold` and `--allow-tools`.

Results land in `plugins/<name>/evals/results/`, which is ignored.

### Releasing

`version` lives in each plugin's `plugin.json` only; the marketplace entries carry none, since a marketplace version is silently masked by `plugin.json` ([marketplaces](https://code.claude.com/docs/en/plugin-marketplaces)). To release a plugin, bump its `plugin.json` version, add a `CHANGELOG.md` entry, commit, then tag from the plugin directory:

```bash
cd plugins/kc-conventions
claude plugin tag --push
```

That creates and pushes `kc-conventions--v<version>`. Dependency resolution reads these tags, so a `kc-gates` release that raises its `kc-conventions` range needs the matching `kc-conventions` tag pushed first.
