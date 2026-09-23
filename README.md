# kc-claude-kit

Sujeet's personal Claude Code toolkit for any codebase: portable coding conventions that load while you write, a gate-based code review built on them, and plugins for auditing a repo's instruction setup and verifying a change before calling it done.

| Plugin | What it does |
|---|---|
| `conventions` | The conventions themselves, one skill per topic, each with its authoring rules, its review checklist and the scripts that check them. `/conventions:init` installs the rules into a project. |
| `code-review` | Reviews a PR, branch or diff with one read-only gate agent per convention topic, and returns a single PASSED or FAILED verdict. Posting to GitHub is a separate skill that only you can run, behind a hook. |
| `claude-md` | Audits a repo's instruction setup and proposes what stays in CLAUDE.md, what becomes a path-scoped rule, a skill, or a hook. |
| `testing` | Verification workflows: look at the UI before calling it done, and drive a cross-layer change end to end. |

## Contents

- [Install](#install)
- [Writing code: the conventions](#writing-code-the-conventions)
- [Reviewing code](#reviewing-code)
- [Posting review comments to GitHub](#posting-review-comments-to-github)
- [Adding your repo's own rules](#adding-your-repos-own-rules)
- [Using the skills in Gemini CLI or Antigravity](#using-the-skills-in-gemini-cli-or-antigravity)
- [Script reference](#script-reference)
- [Developing](#developing)

## Install

Add the marketplace, then install the plugins you want:

```
/plugin marketplace add kcsujeet/kc-claude-kit
/plugin install conventions@kc-claude-kit
/plugin install code-review@kc-claude-kit
/plugin install claude-md@kc-claude-kit
/plugin install testing@kc-claude-kit
```

`code-review` declares `conventions` in its `dependencies`, so installing `code-review` installs `conventions` too ([plugin dependencies](https://code.claude.com/docs/en/plugin-dependencies)). The review cannot run without it: its gates load their checklists from the conventions skills.

Upgrading `code-review` from 1.x: `claude plugin update` does not install the new `conventions` dependency, and `code-review` stays disabled with a dependency error until you install it:

```
claude plugin install conventions@kc-claude-kit
```

Then, once in each project you want the conventions in:

```
/conventions:init
```

Most skills trigger on their own:

| Say | Skill |
|---|---|
| "review this PR", "review my changes" | `code-review:review-code` |
| "audit my CLAUDE.md", "should this be a skill or a rule" | `claude-md:audit` |
| "does this look right" | `testing:verify-ui` |
| "test this end to end" | `testing:verify-e2e` |
| (the topic comes up) | `conventions:<topic>` |

The exception is `/code-review:post-review`, which only runs when you type it.

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
| `i18n` | source and locale files | Source locale only, grep before adding a key, ICU plurals for countable nouns, never concatenate translations |
| `testing` | source files | Failing test first, never skip a test to reach green, cover the unhappy paths, exact assertions on observable behavior, gates tested both ways |
| `correctness` | source files | Empty, null, zero and boundary inputs; operators and conditions checked for off-by-one and inversion; current dependency arrays and closures; no cast hiding a real mismatch; no regression of a fixed bug |
| `type-safety` | typed languages | No `any`, no silencing casts, parse external input at the boundary, reuse existing types |
| `error-handling` | source files | No empty catch, typed codes, one envelope, messages that say what to do, structured logs |
| `performance` | source files | Filter and paginate in the data layer, no N+1, index with the query, measure and say what you measured |
| `dependencies` | dependency manifests | Ask first, check maintenance signals, exact versions, nothing that duplicates what is installed |

Plus `working-agreement.md`, the one hand-written rule, loaded in every session: ask before assuming, report honestly, write corrections down where they belong.

For React and TypeScript codebases, [bulletproof-react](https://github.com/alan2207/bulletproof-react/blob/master/docs/project-structure.md) is the canonical source for project structure, and the `structure` topic says so explicitly: where the two appear to disagree, that document wins and the rule is what gets corrected.

### Getting the rules loaded

Rules are what Claude Code loads when you open a matching file ([memory](https://code.claude.com/docs/en/memory)), and a plugin cannot ship rules. So the conventions reach your session as rule files you install:

- **Per project:** `/conventions:init` copies the rules into `.claude/rules/`, where each loads only when a matching file is touched. Commit the directory and the project carries its own conventions.
- **Machine-wide:** link them into `~/.claude/rules/`, where they apply to every project on that machine:

  ```bash
  git clone https://github.com/kcsujeet/kc-claude-kit ~/src/kc-claude-kit
  mkdir -p ~/.claude/rules
  for f in ~/src/kc-claude-kit/plugins/conventions/rules/*.md; do ln -s "$f" ~/.claude/rules/; done
  ```

`init` writes a version stamp next to the copies. When the rules are missing or older than the installed plugin, a `SessionStart` hook says so in one line, and it stays silent otherwise. After a plugin update, run `/conventions:init` again. Run `/context` in a new session to confirm what loaded.

Why not let the skills load themselves? Skills accept `paths:`, but measured on Claude Code 2.1.280, a `paths:`-scoped plugin skill is not loaded when you read a matching file, only when the model decides to invoke it. The rule files are generated from the skills, so there is still one source.

## Reviewing code

Ask for a review of a PR, a branch or your working changes. `code-review:review-code` then:

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
| naming | `code-review:naming-gate` | every diff | Role names, honest names, extracted boolean chains, names unambiguous where read, verb-led functions, file names |
| clarity | `code-review:clarity-gate` | every diff | Ternaries, guard clauses, comments, magic numbers, casts and `any` that lie, defensive coercion |
| structure | `code-review:structure-gate` | every diff | One responsibility, co-location, no barrels, dead wrappers, lookups over `switch`, breaking changes named |
| simplicity | `code-review:simplicity-gate` | every diff | DRY, YAGNI, KISS; reuse of what already exists, searched by shape as well as by name |
| correctness | `code-review:correctness-gate` | every diff | Logic bugs, edge cases (empty, null, zero, boundary, timezone), data matching its declared type at a boundary, no regression of a bug the repo already fixed |
| datetime | `code-review:datetime-gate` | diff touches date/time logic | No hand-rolled date math, ISO 8601 with offset, truncation, timezone as an input |
| react | `code-review:react-gate` | diff has React/JSX UI code | Bulletproof-react structure, keys, data-fetching hooks, forms, render cost |
| i18n | `code-review:i18n-gate` | diff touches locale files | Per-key audit table, dedup, ICU plurals, no concatenated translations |
| testing | `code-review:testing-gate` | diff changes behavior or tests | New behavior tested, no class-name assertions, exact assertions, gates tested both ways |
| project conventions | `code-review:project-conventions-gate` | repo has `.claude/review-conventions.md` | Every rule in the repo's own conventions file; repo rules that override a built-in box are listed |
| verification | `code-review:verification-gate` | every diff; runs after the others | Files read at head SHA, findings cite `file:line` and SHA, receipts present, nothing posted |

`type-safety`, `error-handling`, `performance` and `dependencies` guide writing only and have no gate.

If a gate agent is unavailable, for example because the `conventions` dependency failed to load, the review runs that gate as a `general-purpose` agent told to invoke the `conventions:<topic>` skill and follow the same contract, and says so in the report. And if a gate agent starts but its preloaded skill did not load (Claude Code skips a missing preloaded skill silently), the gate invokes the skill itself, and fails with `topic skill unavailable` if that fails too. No gate ever grades a topic from memory.

### What the report looks like

- The gate-status table comes first, listing every gate as PASS, FAIL or N/A, then the findings, then an explicit PASSED or FAILED verdict. One confirmed finding in any gate fails the review.
- Each finding is one line, citing the file, line and head SHA, then the issue and the fix.
- No em dashes anywhere in the output: not in the report, the gate verdicts, drafted comments or replies.

## Posting review comments to GitHub

The review never posts; its output stays in chat. To turn findings into PR comments, run `/code-review:post-review` yourself (it sets `disable-model-invocation: true`, so the model cannot start it). It:

1. Drafts the comments in Conventional Comments format, giving every `suggestion` a brief reason.
2. Runs the drafts through `build-comment-payloads.sh`, which rejects any comment whose file or line is not in the diff.
3. Shows you the drafts and the exact post commands, and waits for a fresh, explicit post signal.

A post only goes through when the same Bash command carries the approval token `KC_REVIEW_POST_APPROVED=1`, typed after your signal. A `PreToolUse` hook in the plugin (`scripts/guard-github-post.sh`) blocks every GitHub review write without it, because an instruction is only context and a hook is what enforces. It covers `gh pr comment`, `gh pr review`, `gh issue comment`, and `gh api` writes to a PR's or issue's comments or reviews. Reads, `gh pr create` and `gh pr merge` pass untouched.

## Adding your repo's own rules

If the repository under review has a `.claude/review-conventions.md`, it becomes an extra gate (`code-review:project-conventions-gate`). Use it for project-specific rules: data-layer patterns, UI-library rules, domain helpers, whatever the built-in topics do not know about. Write each rule as a checklist of failure modes with one canonical example path, so the gate can walk it box by box. [`docs/review-conventions.md`](docs/review-conventions.md) has the format guide and a worked example.

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
- `post-review` is never exported, since its safety depends on the Claude Code hook.
- `conventions:init` is never exported, since it installs into `.claude/rules/`.

The rewritten paths are absolute, so re-run the export instead of moving its output. The script header lists the remaining limits.

## Script reference

The deterministic steps are scripts, each with fixture tests, so the model runs them instead of retyping commands.

**Review steps** (`plugins/code-review/scripts/`, tested against a stub `gh`):

| Script | Does |
|---|---|
| `gather-review.sh (<pr> \| --branch [<base>])` | Saves the diff and changed-file list for a PR or a local branch (base: `origin/HEAD`, then `main`, then `master`) and prints `meta.env` with `HEAD_SHA`, `BASE`, `TITLE`, `DIFF_FILE` and `CHANGED_FILES`; prints the fetch command when the local checkout is not the PR head |
| `scope-facts.sh <pr>` | Prints the facts the scope checks need: author, base, commit and file counts, the author's other open PRs, and each linked issue, with the PR description and issue bodies saved to files |
| `review-threads.sh <pr> [--mine <login>]` | Prints every review comment thread, root then replies, and with `--mine` marks the threads you started and whether the author replied after you (requires `jq`) |
| `build-comment-payloads.sh <drafts.json> <diff> <sha> --pr <n>` | Used by `post-review`: checks each drafted comment's path and line against the diff's hunks, writes one payload per comment, and prints the approval-token commands for you to approve; never posts (requires `jq`) |
| `guard-github-post.sh` | The `PreToolUse` hook that blocks GitHub review writes without the approval token |

**Convention checks** (`plugins/conventions/`):

| Script | Does |
|---|---|
| `skills/<topic>/scripts/*.sh <diff>` | The sweeps: each prints the added lines that match one check (ternaries, `as` casts, `&&`/`||` chains, nested `if`s, class-name assertions, and so on) as `path:line: text` |
| `scripts/added-lines.sh <diff>` | The citation map: every added line with its line number in the source file |
| `skills/naming/scripts/name-collisions.sh <name>` | A name's whole-word hits in the tracked files |
| `skills/i18n/scripts/locale-duplicates.sh <locale-dir> <value> <leaf-key>` | The two duplicate greps a new locale key needs |
| `scripts/install-rules.sh [--dry-run]` | What `/conventions:init` runs: copies the rules and stamps the plugin version; `--dry-run` lists what an update would replace |
| `scripts/build-rules.sh [--check]` | Regenerates `rules/` from the topic skills; `--check` fails when they drift |

## Developing

The layout and the reasoning behind it, with the docs each decision rests on, are in [`docs/architecture.md`](docs/architecture.md). A topic skill lives at `plugins/conventions/skills/<topic>/SKILL.md`, with its sections in a fixed order: `## Rules`, `## Review checklist`, `## Review detail`, `## Sweeps`. Edit the skill, never `rules/`, which is generated.

Load the working copies instead of the installed plugins. Load both, since `code-review` depends on `conventions` and a local copy satisfies the dependency:

```bash
claude --plugin-dir ./plugins/conventions --plugin-dir ./plugins/code-review
```

Run what CI runs:

```bash
bash plugins/conventions/scripts/build-rules.sh          # regenerate rules/ after editing a topic skill
bash plugins/conventions/scripts/build-rules.sh --check  # fail if rules/ drifted from the skills
bash plugins/conventions/tests/run-sweeps.sh             # sweep fixtures
bash plugins/conventions/tests/run-lookups.sh            # lookup fixtures
for t in plugins/*/tests/*.sh; do bash "$t"; done        # every plugin's test runners
git ls-files '*.sh' | xargs shellcheck
claude plugin validate . --strict
for p in plugins/*/; do claude plugin validate "$p" --strict; done
```

Evals run each case with and without the plugin and cost model calls, so CI only runs them on demand (the `evals` job, `workflow_dispatch`). Locally:

```bash
claude plugin eval plugins/conventions
claude plugin eval . --eval-dir plugins/code-review/evals --scaffold --allow-tools Bash Agent
```

code-review runs from the repo root because its cases also load `conventions`, and the eval runner only loads plugins inside its containment root: the target plugin when the target is a plugin, otherwise the directory the eval runs against. Its cases build fixture repos, run git and dispatch gate agents, hence `--scaffold` and `--allow-tools`.

Results land in `plugins/<name>/evals/results/`, which is ignored.

### Releasing

`version` lives in each plugin's `plugin.json` only; the marketplace entries carry none, since a marketplace version is silently masked by `plugin.json` ([marketplaces](https://code.claude.com/docs/en/plugin-marketplaces)). To release a plugin, bump its `plugin.json` version, add a `CHANGELOG.md` entry, commit, then tag from the plugin directory:

```bash
cd plugins/conventions
claude plugin tag --push
```

That creates and pushes `conventions--v<version>`. Dependency resolution reads these tags, so a `code-review` release that raises its `conventions` range needs the matching `conventions` tag pushed first.
