# Architecture

How the kit is laid out and why. Every decision cites the Claude Code documentation it rests on, or a measurement taken in this repo when the documentation was silent.

## Layout

```
kc-claude-kit/
├── .claude-plugin/marketplace.json      # plugin entries carry no "version"
├── .github/workflows/ci.yml             # validate, rules sync, script tests; evals on demand
├── scripts/export-agent-skills.sh       # copy every skill into another tool's skills directory
├── docs/architecture.md                 # this file
├── docs/review-conventions.md           # how a repo writes its .claude/review-conventions.md
├── CHANGELOG.md
└── plugins/
    ├── conventions/
    │   ├── .claude-plugin/plugin.json   # version lives here only
    │   ├── skills/
    │   │   ├── <topic>/SKILL.md         # one topic = one file: Rules + Review checklist + Review detail
    │   │   ├── <topic>/scripts/*.sh     # that topic's deterministic sweeps
    │   │   └── init/SKILL.md            # copies the generated rules into a project
    │   ├── rules/                       # GENERATED from skills/<topic>/SKILL.md; never edit by hand
    │   │   └── working-agreement.md     # the one hand-written rule (no topic skill, always loaded)
    │   ├── scripts/build-rules.sh       # regenerates rules/, --check fails on drift
    │   ├── scripts/install-rules.sh     # what init runs: copies rules/ and writes the version stamp
    │   ├── tests/                       # sweep and lookup fixtures, their runners, install-rules test
    │   ├── hooks/                       # SessionStart: missing or stale rules
    │   └── evals/
    ├── code-review/
    │   ├── .claude-plugin/plugin.json   # depends on conventions
    │   ├── skills/
    │   │   ├── review-code/SKILL.md     # orchestrator: scope, dispatch, aggregate
    │   │   └── post-review/             # user-invoked only: drafting and posting comments
    │   ├── agents/<topic>-gate.md       # one gate agent per topic, plus project-conventions-gate.md and verification-gate.md
    │   ├── hooks/hooks.json             # blocks unapproved GitHub posts
    │   ├── scripts/guard-github-post.sh
    │   ├── scripts/*.sh                 # gather-review, scope-facts, review-threads, build-comment-payloads
    │   ├── tests/
    │   └── evals/
    ├── claude-md/                       # unchanged
    └── testing/                         # unchanged
```

## Names (the contract every part follows)

Convention topics, each a skill at `plugins/conventions/skills/<topic>/SKILL.md`, invoked as `conventions:<topic>`:

| Topic | Has a review gate | Gate agent |
|---|---|---|
| naming | yes | `code-review:naming-gate` |
| clarity | yes | `code-review:clarity-gate` |
| structure | yes | `code-review:structure-gate` |
| simplicity | yes | `code-review:simplicity-gate` |
| datetime | yes | `code-review:datetime-gate` |
| react | yes | `code-review:react-gate` |
| i18n | yes | `code-review:i18n-gate` |
| testing | yes | `code-review:testing-gate` |
| correctness | yes | `code-review:correctness-gate` |
| type-safety | no (rules only) | |
| error-handling | no (rules only) | |
| performance | no (rules only) | |
| dependencies | no (rules only) | |

Two gate agents own no topic skill: `code-review:project-conventions-gate` (reads the target repo's `.claude/review-conventions.md`) and `code-review:verification-gate` (audits the other gates' receipts, dispatched second).

A topic skill's body has these sections, in this order:

1. `## Rules`: the authoring conventions. `scripts/build-rules.sh` copies this section, with the skill's `paths`, into `rules/<topic>.md`.
2. `## Review checklist`: the `- [ ] §<id> ... (N/A: ...)` boxes a gate agent ticks. Absent for rules-only topics.
3. `## Review detail`: the per-box sections, examples and evidence requirements.
4. `## Sweeps`: the bundled scripts, each run as `bash "${CLAUDE_PLUGIN_ROOT}/skills/<topic>/scripts/<name>.sh" <diff-file>`, printing one `file:line: text` hit per line and nothing else. A lookup, which takes a name or a key instead of a diff (`naming/scripts/name-collisions.sh`, `i18n/scripts/locale-duplicates.sh`), is listed there too and says so.

Posting approval token: a GitHub write passes the code-review guard only when the same Bash command contains `KC_REVIEW_POST_APPROVED=1`, typed after the user's explicit post signal.

## Decisions

### One file per convention, used when writing and when reviewing

Before this layout, every convention was stated twice, once as a rule and once as a review reference, and the two drifted (barrels, `null` inside a map, `if` nesting disagreed). Each topic is now one skill holding both halves.

A gate agent loads its topic through the subagent `skills:` field, which injects the full skill content ([subagents](https://code.claude.com/docs/en/sub-agents)). Measured in this repo on Claude Code 2.1.280: a plugin agent preloads a skill from a different plugin by `plugin:skill` and by bare name, and `${CLAUDE_PLUGIN_ROOT}` inside the preloaded skill expands to the owning plugin's directory, which is how gate agents find the sweep scripts.

### Rules stay, generated, because `paths:` skills do not auto-load

Skills accept `paths:` ([skills](https://code.claude.com/docs/en/skills)), which suggested the rule copies could go. Measured on 2.1.280: after reading a matching file, a `paths:`-scoped plugin skill's content was not in context; it loads only when the model invokes it. Rules load when a matching file is read ([memory](https://code.claude.com/docs/en/memory)), and plugins cannot ship rules, so `/conventions:init` still copies them into `.claude/rules/`.

What changed is that the rules are generated from the skills, so there is one source, and `init` writes a version stamp that the SessionStart hook compares with the installed plugin, so stale copies are reported instead of silently kept.

### Gates are plugin agents

Plugins ship subagents from `agents/`, named `plugin:agent` ([plugins](https://code.claude.com/docs/en/plugins)). The documented practices are single responsibility, restricted tools, and a model matched to the task ([subagents](https://code.claude.com/docs/en/sub-agents)). Each gate is read-only (`Read, Grep, Glob, Bash`) and owns one topic.

### Deterministic checks are scripts

"Prefer scripts for deterministic operations", and for a script that is executed "only the script's output consumes tokens" ([skill best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices)). Sweeps are scripts with fixture tests, so a broken regex fails CI instead of passing a review. The same goes for line numbers: `conventions/scripts/added-lines.sh` prints every added line with its source line number, and gates cite from it. Measured before it existed, gates read positions out of the saved diff file and cited lines that did not exist in the source.

Orchestration steps are scripts too, tested against a stub `gh`: `init` runs `conventions/scripts/install-rules.sh`, `review-code` gathers its diff, scope facts and reply threads with `code-review/scripts/`, and `post-review` validates comment anchors and builds payloads with `build-comment-payloads.sh`.

### Posting is user-invoked and enforced

Posting is task content, the kind that takes `disable-model-invocation: true` ([skills](https://code.claude.com/docs/en/skills)). Instructions are "context, not enforced configuration"; a PreToolUse hook is what blocks an action ([memory](https://code.claude.com/docs/en/memory), [hooks](https://code.claude.com/docs/en/hooks)).

### Versioning

`version` lives in each `plugin.json` only; setting it in the marketplace entry too is masked by `plugin.json` without warning ([marketplaces](https://code.claude.com/docs/en/plugin-marketplaces)). `code-review` declares `conventions` in `dependencies` with a semver range. Releases are tagged `{plugin}--v{version}` with `claude plugin tag`, which dependency resolution reads ([plugin dependencies](https://code.claude.com/docs/en/plugin-dependencies)).

### Tests

`claude plugin validate --strict` and the script tests run on every PR. `claude plugin eval` suites live in each plugin's `evals/` and run each case with and without the plugin ([plugin evals](https://code.claude.com/docs/en/plugin-evals)); they cost model calls, so CI runs them on demand, with the models pinned and a cost ceiling.

### Other agents

Skills follow the Agent Skills standard ([skills](https://code.claude.com/docs/en/skills)). Gemini CLI reads workspace and extension skills, and an extension is a `gemini-extension.json` with `skills/` beside it ([Gemini extensions](https://geminicli.com/docs/extensions/reference/)); Antigravity reads `.agents/skills/` and plugin skills under `~/.gemini/antigravity-cli/plugins/<name>/skills/` ([Antigravity](https://antigravity.google/docs/skills)). `scripts/export-agent-skills.sh` copies the kit's skills into any of those. Gate agents and hooks are Claude Code features and do not carry over; other tools run the gates inline from the skills.
