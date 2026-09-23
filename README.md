# kc-claude-kit

Sujeet's personal Claude Code toolkit for any codebase: portable coding conventions that load while you write, plus plugins for reviewing a diff, auditing a repo's instruction setup, and verifying a change before calling it done.

Four plugins:

| Plugin | What it does |
|---|---|
| `conventions` | The conventions themselves, one skill per topic. Each topic skill holds the authoring rules, the review checklist, and the deterministic sweeps that check them. `/conventions:init` installs the rules into a project. |
| `code-review` | Gate-based review of a PR, branch or diff. One read-only gate agent per convention topic returns per-box PASS/FAIL verdicts, and a verification gate audits their receipts. Posting to GitHub is a separate, user-invoked skill behind a hook. |
| `claude-md` | Audits a repo's instruction setup and proposes what stays in CLAUDE.md, what becomes a path-scoped rule, a skill, or a hook. |
| `testing` | Verification workflows: look at the UI before calling it done, and drive a cross-layer change end to end. |

The layout and the reasoning behind it, with the docs each decision rests on, are in [`docs/architecture.md`](docs/architecture.md).

## Install

Add the marketplace:

```
/plugin marketplace add kcsujeet/kc-claude-kit
```

Install the plugins you want:

```
/plugin install conventions@kc-claude-kit
/plugin install code-review@kc-claude-kit
/plugin install claude-md@kc-claude-kit
/plugin install testing@kc-claude-kit
```

`code-review` declares `conventions` in its `dependencies`, so installing `code-review` installs `conventions` too ([plugin dependencies](https://code.claude.com/docs/en/plugin-dependencies)). The gate agents load their checklists from the conventions skills, so the review cannot run without them.

Then, once per project you want the conventions in:

```
/conventions:init
```

The model-invoked skills trigger on their own: `code-review:review-code` on "review this PR" or "review my changes", `claude-md:audit` on "audit my CLAUDE.md" or "should this be a skill or a rule", `testing:verify-ui` on "does this look right", `testing:verify-e2e` on "test this end to end", and each `conventions:<topic>` skill when its topic comes up. `/code-review:post-review` is the exception: it only runs when you type it.

## Conventions

Each topic is one skill at `plugins/conventions/skills/<topic>/SKILL.md`, with its sections in a fixed order: `## Rules` (how to write it), `## Review checklist` (the boxes a gate ticks), `## Review detail` (examples and evidence per box), and `## Sweeps` (the bundled scripts). One file per convention means the rule you write against and the box a reviewer ticks cannot drift apart, which they used to.

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

Plus `working-agreement.md`, the one hand-written, always-loaded rule: ask before assuming, report honestly, write corrections down where they belong.

For React and TypeScript codebases, [bulletproof-react](https://github.com/alan2207/bulletproof-react/blob/master/docs/project-structure.md) is the canonical source for project structure, and the `structure` topic says so explicitly: where the two appear to disagree, that document wins and the rule is what gets corrected.

### Why `/conventions:init` still exists

Skills accept `paths:`, which looks like it should make the rule copies unnecessary. It does not: measured on Claude Code 2.1.280, a `paths:`-scoped plugin skill is not loaded when you read a matching file, only when the model decides to invoke it. Rules are what load on file read ([memory](https://code.claude.com/docs/en/memory)), and plugins cannot ship rules. So the plugin keeps a `rules/` directory, and `init` copies it where Claude Code looks:

- **Per project**, `/conventions:init` copies the rules into `.claude/rules/`, which keeps the `paths:` frontmatter working so each rule loads only when a matching file is touched. Commit the directory and the project carries its own conventions.
- **Machine-wide**, put them in `~/.claude/rules/` instead, where they apply to every project on that machine:

```bash
git clone https://github.com/kcsujeet/kc-claude-kit ~/src/kc-claude-kit
mkdir -p ~/.claude/rules
for f in ~/src/kc-claude-kit/plugins/conventions/rules/*.md; do ln -s "$f" ~/.claude/rules/; done
```

`rules/` is generated from the topic skills by `plugins/conventions/scripts/build-rules.sh`, so there is still one source, and CI fails if the two drift. `init` writes a version stamp next to the copies, and a `SessionStart` hook prints one line when the rules are missing or older than the installed plugin. It stays silent otherwise, so the normal case costs no context.

Run `/context` in a new session to confirm what loaded.

## How the review works

Before the fan-out, `code-review:review-code` runs the scope checks itself: is the PR stacked on another, does it do more than its title says, what constraints does the linked issue set, and was a large diff read in full. Then it dispatches one gate agent per applicable topic, in parallel. Each gate is a read-only plugin agent (`Read, Grep, Glob, Bash`) that preloads its conventions skill, runs that topic's sweep scripts over the diff, walks every checklist box, and returns a per-box verdict with evidence. Any finding fails its gate. The verification gate runs second and audits the other gates' receipts. The orchestrator aggregates everything into a single PASSED/FAILED verdict and leads with a gate-status table.

The gates are dispatched by `subagent_type` (`code-review:naming-gate` and so on). If a gate agent is unavailable, for example because the `conventions` dependency failed to load, the orchestrator runs that gate as a `general-purpose` agent told to invoke the `conventions:<topic>` skill and follow the same contract, and says so in the report.

| Topic | Gate agent | Dispatch | Checks, in short |
|---|---|---|---|
| naming | `code-review:naming-gate` | always | Role names, honest names, extracted boolean chains, names unambiguous where read, verb-led functions, file names |
| clarity | `code-review:clarity-gate` | always | Ternaries, guard clauses, comments, magic numbers, casts and `any` that lie, defensive coercion |
| structure | `code-review:structure-gate` | always | One responsibility, co-location, no barrels, dead wrappers, lookups over `switch`, breaking changes named |
| simplicity | `code-review:simplicity-gate` | always | DRY, YAGNI, KISS; reuse of what already exists, searched by shape as well as by name |
| datetime | `code-review:datetime-gate` | diff touches date/time logic | No hand-rolled date math, ISO 8601 with offset, truncation, timezone as an input |
| react | `code-review:react-gate` | diff has React/JSX UI code | Bulletproof-react structure, keys, data-fetching hooks, forms, render cost |
| i18n | `code-review:i18n-gate` | diff touches locale files | Per-key audit table, dedup, ICU plurals, no concatenated translations |
| testing | `code-review:testing-gate` | diff changes behavior or tests | New behavior tested, no class-name assertions, exact assertions, gates tested both ways |
| correctness | `code-review:correctness-gate` | always | Logic bugs, edge cases (empty, null, zero, boundary, timezone), data matching its declared type at a boundary, no regression of a bug the repo already fixed |
| project conventions | `code-review:project-conventions-gate` | repo has `.claude/review-conventions.md` | Every rule in the repo's own conventions file; repo rules that override a built-in box are listed |
| verification | `code-review:verification-gate` | always, second | Files read at head SHA, findings cite `file:line` and SHA, receipts present, nothing posted |

`type-safety`, `error-handling`, `performance` and `dependencies` are rules-only topics: they guide writing and have no gate.

### Posting to GitHub

The review never posts. Its output stays in chat.

To turn findings into PR comments, run `/code-review:post-review`. It is user-invoked only (`disable-model-invocation: true`), drafts the comments in Conventional Comments format, shows you the draft, and waits for a fresh, explicit post signal. The actual `gh` write only goes through when the same Bash command carries the approval token `KC_REVIEW_POST_APPROVED=1`, typed after your signal. A `PreToolUse` hook in the plugin (`scripts/guard-github-post.sh`) blocks any GitHub review write without it, because an instruction is context and only a hook enforces anything. It covers `gh pr comment`, `gh pr review`, `gh issue comment`, and `gh api` writes to a PR's or issue's comments or reviews; reads, `gh pr create` and `gh pr merge` pass untouched.

### Per-repo extension

If the target repository has a `.claude/review-conventions.md`, it becomes an extra gate (`code-review:project-conventions-gate`). Use it for project-specific rules: data-layer patterns, UI-library rules, domain helpers, whatever the built-in topics do not know about. Write each rule as a checklist of failure modes with one canonical example path, so a gate can walk it box by box. [`docs/review-conventions.md`](docs/review-conventions.md) has the format guide and a worked example.

On conflict, the repo's rule wins over a built-in convention: the review reports the built-in box as overridden, citing the repo rule, instead of failing it. The repo knows its own context; the kit only knows what is portable.

## Using the skills in Gemini CLI or Antigravity

The skills follow the Agent Skills standard, so other agents can read them. `scripts/export-agent-skills.sh` copies every skill into another tool's skills directory, renamed to `kc-<plugin>-<skill>` (for example `kc-conventions-naming`) because those tools share one flat namespace where bare names like `naming` collide. It rewrites `${CLAUDE_PLUGIN_ROOT}` script paths to the exported location and bundles the shared sweep library, so the sweeps still run.

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

What does not carry over: gate agents and hooks are Claude Code features, so another tool runs the gates inline from the skills. `post-review` is never exported, since its safety depends on the Claude Code hook, and neither is `conventions:init`, which installs into `.claude/rules/`. The rewritten paths are absolute, so re-run the export rather than moving its output. The script header lists the remaining limits.

## Developing

Load the working copies instead of the installed plugins. Load both, since `code-review` depends on `conventions` and a local copy satisfies the dependency:

```bash
claude --plugin-dir ./plugins/conventions --plugin-dir ./plugins/code-review
```

Run what CI runs:

```bash
bash plugins/conventions/scripts/build-rules.sh          # regenerate rules/ after editing a topic skill
bash plugins/conventions/scripts/build-rules.sh --check  # fail if rules/ drifted from the skills
bash plugins/conventions/tests/run-sweeps.sh             # sweep fixtures
for t in plugins/*/tests/*.sh; do bash "$t"; done        # every plugin's test runners
git ls-files '*.sh' | xargs shellcheck
claude plugin validate . --strict
for p in plugins/*/; do claude plugin validate "$p" --strict; done
```

Evals run each case with and without the plugin and cost model calls, so CI only runs them on demand (the `evals` job, `workflow_dispatch`). Locally:

```bash
claude plugin eval plugins/conventions
claude plugin eval plugins/code-review --scaffold --allow-tools Bash Agent   # its cases build fixture repos and run git
```

Results land in `plugins/<name>/evals/results/`, which is ignored.

### Releasing

`version` lives in each plugin's `plugin.json` only; the marketplace entries carry none, since a marketplace version is silently masked by `plugin.json` ([marketplaces](https://code.claude.com/docs/en/plugin-marketplaces)). To release a plugin, bump its `plugin.json` version, add a `CHANGELOG.md` entry, commit, then tag from the plugin directory:

```bash
cd plugins/conventions
claude plugin tag --push
```

That creates and pushes `conventions--v<version>`. Dependency resolution reads these tags, so a `code-review` release that raises its `conventions` range needs the matching `conventions` tag pushed first.
