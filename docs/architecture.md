# Architecture

How the kit is laid out and why. Every decision cites the Claude Code documentation it rests on, or a measurement taken in this repo when the documentation was silent.

## Layout

```
kc-claude-kit/
├── .claude-plugin/marketplace.json      # plugin entries carry no "version"
├── .github/workflows/ci.yml             # validate, rules sync, script tests; evals on demand
├── scripts/export-agent-skills.sh       # copy every skill into another tool's skills directory
├── docs/architecture.md                 # this file
├── CHANGELOG.md
└── plugins/
    ├── kc-conventions/
    │   ├── .claude-plugin/plugin.json      # version lives here only
    │   ├── skills/
    │   │   ├── kc-<topic>/SKILL.md         # one topic = one file: Rules + Review checklist + Review detail
    │   │   ├── kc-<topic>/scripts/*.sh     # that topic's deterministic sweeps
    │   │   ├── kc-<topic>/references/*.md  # Review detail moved out to keep SKILL.md under 500 lines
    │   │   └── kc-init/SKILL.md            # copies the generated rules into a project
    │   ├── rules/                          # GENERATED from skills/kc-<topic>/SKILL.md; never edit by hand
    │   │   └── kc-working-agreement.md     # the one hand-written rule (no topic skill, always loaded)
    │   ├── scripts/build-rules.sh          # regenerates rules/, --check fails on drift
    │   ├── scripts/install-rules.sh        # what kc-init runs: copies rules/ and writes the version stamp
    │   ├── tests/                          # sweep and lookup fixtures, their runners, install-rules test
    │   ├── hooks/                          # SessionStart: missing or stale rules
    │   └── evals/
    ├── kc-gates/
    │   ├── .claude-plugin/plugin.json      # depends on kc-conventions
    │   ├── skills/
    │   │   ├── kc-code-review/SKILL.md     # orchestrator: scope, dispatch, aggregate
    │   │   ├── kc-post-review/             # user-invoked only: drafting and posting comments
    │   │   └── kc-ready-for-review/SKILL.md # the one pass before a PR goes to a reviewer
    │   ├── agents/<topic>-gate.md          # one gate agent per topic, plus project-conventions-gate.md and verification-gate.md
    │   ├── hooks/hooks.json                # blocks unapproved GitHub posts and unreviewed hand-offs
    │   ├── scripts/guard-github-post.sh, guard-hand-off.sh, lib/hook-input.sh
    │   ├── scripts/*.sh                    # gather-review, scope-facts, review-threads, build-comment-payloads
    │   ├── tests/
    │   └── evals/
    ├── kc-autopilot/
    │   ├── .claude-plugin/plugin.json      # depends on kc-gates, kc-conventions, kc-verify
    │   ├── skills/
    │   │   ├── kc-init/SKILL.md            # user-invoked: writes and proves .claude/autopilot.json
    │   │   └── kc-run/                     # the staff engineer: validate, decide, contract, start the workflow, report
    │   ├── workflows/deliver.js            # per-unit pipeline: engineer, review, QA, verify, ship
    │   ├── agents/<role>.md                # engineer, staff-reviewer, review-prep, lens-reviewer, skeptic, triage, qa-persona, verifier, ops, shipper
    │   ├── hooks/hooks.json                # PreToolUse guard for kc-autopilot:* agents
    │   ├── scripts/*.sh                    # guard, read-config, validate-plan, worktree, boot-app, run-checks, qa-browser, pr-body, ...
    │   └── tests/                          # script runners, workflow syntax and simulation; e2e/ is manual and costs money
    ├── kc-verify/                          # kc-ui and kc-e2e skills
    ├── kc-instructions/                    # kc-audit skill; the claude- prefix is reserved
    ├── kc-usage-band/                      # mod
    └── kc-image-preview/                   # mod
```

## Names (the contract every part follows)

Convention topics, each a skill at `plugins/kc-conventions/skills/kc-<topic>/SKILL.md`, invoked as `kc-conventions:kc-<topic>`:

| Topic | Has a review gate | Gate agent |
|---|---|---|
| naming | yes | `kc-gates:naming-gate` |
| clarity | yes | `kc-gates:clarity-gate` |
| structure | yes | `kc-gates:structure-gate` |
| simplicity | yes | `kc-gates:simplicity-gate` |
| datetime | yes | `kc-gates:datetime-gate` |
| react | yes | `kc-gates:react-gate` |
| i18n | yes | `kc-gates:i18n-gate` |
| testing | yes | `kc-gates:testing-gate` |
| correctness | yes | `kc-gates:correctness-gate` |
| type-safety | no (rules only) | |
| error-handling | no (rules only) | |
| performance | no (rules only) | |
| dependencies | no (rules only) | |

Two gate agents own no topic skill: `kc-gates:project-conventions-gate` (reads the target repo's `.claude/review-conventions.md`) and `kc-gates:verification-gate` (audits the other gates' receipts, dispatched second).

Autopilot agents, at `plugins/kc-autopilot/agents/<role>.md`, dispatched by `workflows/deliver.js` as `agentType: 'kc-autopilot:<role>'`:

| Agent | Model | Does |
|---|---|---|
| `kc-autopilot:engineer` | `sonnet` | Proposes approaches, then builds the chosen one, tests first, in the unit's worktree |
| `kc-autopilot:staff-reviewer` | `best` | Picks the approach before any code; judges the final diff before a PR opens |
| `kc-autopilot:review-prep` | `sonnet` | Runs `kc-gates`'s gather step and writes the SCOPE block; returns them verbatim |
| `kc-autopilot:lens-reviewer` | `sonnet` | Reviews the diff through one lens (security, data, compatibility, and so on) |
| `kc-autopilot:skeptic` | `sonnet` | Read-only: tries to refute one serious lens finding; two run per finding |
| `kc-autopilot:triage` | `sonnet` | Sorts findings into fix or dismiss, with reasons |
| `kc-autopilot:qa-persona` | `sonnet` | Drives the running app in a headless browser as one persona and reports bugs |
| `kc-autopilot:verifier` | `sonnet` | Reproduces QA bugs and checks every criterion itself; never the author of the code |
| `kc-autopilot:ops` | `sonnet` | Runs a bundled script and returns its output verbatim |
| `kc-autopilot:shipper` | `sonnet` | Pushes the branch, opens the ready PR, stacks it, waits for CI |

A topic skill's body has these sections, in this order:

1. `## Rules`: the authoring conventions. `scripts/build-rules.sh` copies this section, with the skill's `paths`, into `rules/kc-<topic>.md`.
2. `## Review checklist`: the `- [ ] §<id> ... (N/A: ...)` boxes a gate agent ticks. Absent for rules-only topics.
3. `## Review detail`: the per-box sections, examples and evidence requirements. When the skill nears 500 lines, a cluster of these sections moves to `references/<cluster>.md`, linked by its `${CLAUDE_PLUGIN_ROOT}` path; gates read it from there.
4. `## Sweeps`: the bundled scripts, each run as `bash "${CLAUDE_PLUGIN_ROOT}/skills/kc-<topic>/scripts/<name>.sh" <diff-file>`, printing one `file:line: text` hit per line and nothing else. A lookup, which takes a name or a key instead of a diff (`kc-naming/scripts/name-collisions.sh`, `kc-i18n/scripts/locale-duplicates.sh`), is listed there too and says so.

Posting approval token: a GitHub write passes the kc-gates guard only when the same Bash command contains `KC_REVIEW_POST_APPROVED=1`, typed after the user's explicit post signal.

## Decisions

### One file per convention, used when writing and when reviewing

Before this layout, every convention was stated twice, once as a rule and once as a review reference, and the two drifted (barrels, `null` inside a map, `if` nesting disagreed). Each topic is now one skill holding both halves.

A gate agent loads its topic through the subagent `skills:` field, which injects the full skill content ([subagents](https://code.claude.com/docs/en/sub-agents)). Measured in this repo on Claude Code 2.1.280: a plugin agent preloads a skill from a different plugin by `plugin:skill` and by bare name, and `${CLAUDE_PLUGIN_ROOT}` inside the preloaded skill expands to the owning plugin's directory, which is how gate agents find the sweep scripts.

### Rules stay, generated, because `paths:` skills do not auto-load

Skills accept `paths:` ([skills](https://code.claude.com/docs/en/skills)), which suggested the rule copies could go. Measured on 2.1.280: after reading a matching file, a `paths:`-scoped plugin skill's content was not in context; it loads only when the model invokes it. Rules load when a matching file is read ([memory](https://code.claude.com/docs/en/memory)), and plugins cannot ship rules, so `/kc-conventions:kc-init` still copies them into `.claude/rules/`.

What changed is that the rules are generated from the skills, so there is one source, and `init` writes a version stamp that the SessionStart hook compares with the installed plugin, so stale copies are reported instead of silently kept.

### Gates are plugin agents

Plugins ship subagents from `agents/`, named `plugin:agent` ([plugins](https://code.claude.com/docs/en/plugins)). The documented practices are single responsibility, restricted tools, and a model matched to the task ([subagents](https://code.claude.com/docs/en/sub-agents)). Each gate is read-only (`Read, Grep, Glob, Bash`, plus `Skill` so it can load its topic skill itself if the preload was skipped) and owns one topic.

### Deterministic checks are scripts

"Prefer scripts for deterministic operations", and for a script that is executed "only the script's output consumes tokens" ([skill best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices)). Sweeps are scripts with fixture tests, so a broken regex fails CI instead of passing a review. The same goes for line numbers: `conventions/scripts/added-lines.sh` prints every added line with its source line number, and gates cite from it. Measured before it existed, gates read positions out of the saved diff file and cited lines that did not exist in the source.

Orchestration steps are scripts too, tested against a stub `gh`: `kc-init` runs `kc-conventions/scripts/install-rules.sh`, `kc-code-review` gathers its diff, scope facts and reply threads with `kc-gates/scripts/`, and `kc-post-review` validates comment anchors and builds payloads with `build-comment-payloads.sh`.

### Posting is user-invoked and enforced

Posting is task content, the kind that takes `disable-model-invocation: true` ([skills](https://code.claude.com/docs/en/skills)). Instructions are "context, not enforced configuration"; a PreToolUse hook is what blocks an action ([memory](https://code.claude.com/docs/en/memory), [hooks](https://code.claude.com/docs/en/hooks)).

### kc-autopilot: orchestration is a workflow, judgment is the staff model

Measured on Claude Code 2.1.292 unless stated.

**Orchestration is a workflow script.** A unit's loop (engineer, review, triage, QA, verify, fix, ship) is a fixed sequence with fan-out and a bounded number of rounds, which is what a workflow script is for: plain JavaScript that dispatches agents and returns a result, with no model deciding the control flow ([workflows](https://code.claude.com/docs/en/workflows)). The script keeps to the documented rules: a pure-literal `meta` first and no clocks, randomness or `import()`, so a run is resumable. A skill starts it by name: a skill that called the Workflow tool with `spike:s1` started a plugin workflow, and the commit landed only in the worktree it was given (spike S3). Approval-prompt behaviour could not be observed headlessly, so the README tells users to pre-allow `Workflow(kc-autopilot:deliver)` or use auto mode ([permission modes](https://code.claude.com/docs/en/permission-modes)).

**Judgment is the staff model, and only there.** The decisions a junior cannot be trusted with, the cross-unit approach, each unit's contract and personas, picking among the engineer's approaches and the final proportionality gate, belong to the `run` skill and `kc-autopilot:staff-reviewer`, on `best`. Everything mechanical runs on `sonnet`. Both come from `.claude/autopilot.json` `models` ([model config](https://code.claude.com/docs/en/model-config)), and the skill's own `model: best` applies to that skill's turn only, so the README suggests `/model best` for users who want the main session on it throughout.

**Workers are plugin agents.** A workflow resolves a plugin agent by `agentType`; the hook input for such an agent carries `agent_type` as `<plugin>:<name>`, here `kc-autopilot:engineer` (spike S1, [subagents](https://code.claude.com/docs/en/sub-agents)). A worktree is chosen by the absolute path in the agent's prompt: both the agents' and the hooks' `cwd` stay at the launch repo, not the worktree (spike S1, confirmed in the e2e run). So `guard.sh` decides on `tool_input` paths and never on `cwd`.

**Workflow agents cannot spawn agents.** Measured in the e2e run: an agent dispatched from a workflow has no `Agent` tool. `kc-gates:kc-code-review` fans out its gates by dispatching agents, so inside a unit it cannot run as written; `deliver.js` runs the gate fan-out itself, using kc-gates's gather script and gate agents (found through `scripts/plugin-root.sh`) and aggregating the receipts the same way.

**QA is a real browser, driven by Bash.** Three parallel runs of a pinned Playwright 1.64.0 script, started within 7 ms of each other, each produced its screenshot with no profile-lock errors, because `launch()` uses a temporary profile per browser (spike S2). So each persona drives its own headless browser against its unit's own app instance, whose port comes from `launch.ports` and whose data must be isolated per unit by the recipe, otherwise `init` sets `max_parallel_units` to 1.

**The guard is a hook, and a guardrail rather than a sandbox.** Instructions are context; a `PreToolUse` hook is what blocks ([hooks](https://code.claude.com/docs/en/hooks)). `scripts/guard.sh` acts only when `agent_type` starts with `kc-autopilot:`, so it never touches the user's own session or other plugins' agents, and it fails closed for those agents (missing `jq`, unparseable input, a decision slower than its deadline, since a timed-out hook is non-blocking). It reads Bash the way bash does for the cases that matter, joined continuations and allowlisted heredoc bodies, and denies merges and auto-merge, force-pushes and pushes to `main`, edits to run files and the config, skipped or deleted tests, and, for the engineer, risky paths and new dependencies. It cannot see what a script an agent writes and then runs will do. The backstop is the staff reviewer's final gate on every diff and the fact that the user merges.

**Stacks use GitHub's native API, with a fallback.** Units that depend on each other are linked as stacked pull requests through the REST API ([stacks](https://docs.github.com/en/rest/pulls/stacks)), pinned to an API version, not through a `gh` subcommand whose behaviour varies with the installed version. Any failure leaves a plain base-branch chain and says so in the report; nothing is merged to make a stack linear.

**Cost is real and measured, not estimated.** A 2-unit dry run on the fixture in `plugins/kc-autopilot/tests/e2e/` cost about $6 to $8 and 8 to 12 minutes, with roughly 75 to 110 agents. That path is manual, not in CI, for the reason evals are on demand: it spends model calls.

### Versioning

`version` lives in each `plugin.json` only; setting it in the marketplace entry too is masked by `plugin.json` without warning ([marketplaces](https://code.claude.com/docs/en/plugin-marketplaces)). `kc-gates` declares `kc-conventions` in `dependencies` with a semver range. Releases are tagged `{plugin}--v{version}` with `claude plugin tag`, which dependency resolution reads ([plugin dependencies](https://code.claude.com/docs/en/plugin-dependencies)).

### Tests

`claude plugin validate --strict` and the script tests run on every PR. `claude plugin eval` suites live in each plugin's `evals/` and run each case with and without the plugin ([plugin evals](https://code.claude.com/docs/en/plugin-evals)); they cost model calls, so CI runs them on demand, with the models pinned and a cost ceiling.

### Other agents

Skills follow the Agent Skills standard ([skills](https://code.claude.com/docs/en/skills)). Gemini CLI reads workspace and extension skills, and an extension is a `gemini-extension.json` with `skills/` beside it ([Gemini extensions](https://geminicli.com/docs/extensions/reference/)); Antigravity reads `.agents/skills/` and plugin skills under `~/.gemini/antigravity-cli/plugins/<name>/skills/` ([Antigravity](https://antigravity.google/docs/skills)). `scripts/export-agent-skills.sh` copies the kit's skills into any of those. Gate agents and hooks are Claude Code features and do not carry over; other tools run the gates inline from the skills.
