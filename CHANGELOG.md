# Changelog

All notable changes to the plugins in this marketplace. Each plugin is versioned on its own, in its `plugin.json`, and released as a `{plugin}--v{version}` tag.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and each plugin follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

The restructure described in [`docs/architecture.md`](docs/architecture.md): each convention is stated once, as a skill used both when writing and when reviewing.

### conventions 1.1.0

#### Added

- One skill per topic under `skills/<topic>/SKILL.md` (naming, clarity, structure, simplicity, datetime, react, i18n, testing, type-safety, error-handling, performance, dependencies), invoked as `conventions:<topic>`. Each holds the authoring rules, the review checklist, the per-box review detail, and the topic's sweeps.
- Deterministic sweep scripts under `skills/<topic>/scripts/`, each printing one `file:line: text` hit per line, with fixture tests in `tests/`.
- `scripts/build-rules.sh`, which generates `rules/<topic>.md` from each skill's `## Rules` section and `paths`, and fails on drift with `--check`.
- Eval suite under `evals/`, run with `claude plugin eval`.

#### Changed

- `rules/` is generated from the topic skills and never edited by hand. `working-agreement.md` stays the one hand-written rule.
- `/conventions:init` writes a version stamp beside the installed rules, and the `SessionStart` hook now reports stale rules as well as missing ones.

### code-review 2.0.0

#### Changed

- **Breaking:** posting to GitHub moved out of `review-code` into the user-invoked `/code-review:post-review` skill (`disable-model-invocation: true`). A `PreToolUse` hook blocks any GitHub write whose Bash command does not carry `KC_REVIEW_POST_APPROVED=1`.
- **Breaking:** gates are plugin agents under `agents/`: `code-review:<topic>-gate` for naming, clarity, structure, simplicity, datetime, react, i18n and testing, each read-only (`Read, Grep, Glob, Bash`, `model: sonnet`) and preloading its `conventions:<topic>` skill, plus `code-review:project-conventions-gate` and `code-review:verification-gate` (phase 2). The `skills/review-code/references/` directory is gone: topic rules moved to the conventions skills, the gate contract into the agents, the repo-author format guide to `docs/review-conventions.md`, and the PR-comment protocol to `post-review`.
- **Breaking:** depends on the `conventions` plugin (`^1.1.0`) through `dependencies`, which installs it automatically.
- `review-code` is now an orchestrator only: it saves the diff to a file, runs the scope checks, dispatches the gates by `subagent_type`, and aggregates. If a gate agent is unavailable it falls back to a `general-purpose` agent that invokes the `conventions:<topic>` skill, and reports the fallback.
- Gates run the conventions sweep scripts against the saved diff instead of ad hoc greps.
- A rule in the target repo's `.claude/review-conventions.md` that contradicts a built-in convention now wins for that repo; the built-in box is reported as overridden, citing the repo rule.

#### Added

- `hooks/hooks.json` and `scripts/guard-github-post.sh`: a `PreToolUse` guard on Bash that denies `gh pr comment`, `gh pr review`, `gh issue comment` and `gh api` writes to PR or issue comments and reviews unless the command carries `KC_REVIEW_POST_APPROVED=1`, with tests in `tests/guard-github-post.test.sh`.
- Eval suite under `evals/` (seeded violations, a clean diff, an unrelated request), with scaffold scripts that build fixture repos. Run with `--scaffold --allow-tools Bash Agent`.
- `docs/review-conventions.md`: how to write a repo's `.claude/review-conventions.md`.

### Marketplace

- Plugin entries no longer carry a `version`; `plugin.json` is the only source.
- CI: manifest validation, rules drift check, shellcheck and script tests on every PR; evals on demand.
- `scripts/export-agent-skills.sh` exports the skills to Gemini CLI and Antigravity.

## code-review 1.1.0 - 2026-09-23

Ported the portable rules from ilamy-calendar's retired review skill ([#3](https://github.com/kcsujeet/kc-claude-kit/pull/3)).

### Added

- `testing` gate: new behavior has a test, no class-name assertions standing in for behavior, gates tested both ways, repeated setup becomes a helper, tests beside their unit, exact assertions.
- Orchestrator scope checks: stacked branches, diff against title, linked-issue constraints, large diffs read in chunks.
- New boxes across naming, clarity, structure, simplicity, datetime, react and verification.

### Fixed

- The `COMMENT` review payload.

## conventions 1.0.2 - 2026-09-23

### Changed

- Rules aligned with the boxes ported in code-review 1.1.0 ([#3](https://github.com/kcsujeet/kc-claude-kit/pull/3)).

## code-review 1.0.1 - 2026-09-08

### Added

- Naming gate catches names that only read at their declaration ([#2](https://github.com/kcsujeet/kc-claude-kit/pull/2)).
- An output length budget for review reports and PR comments.
- Code examples inside PR comments are gated ([#1](https://github.com/kcsujeet/kc-claude-kit/pull/1)).

## conventions 1.0.1 - 2026-09-08

### Changed

- `naming` rule: a name must read unambiguously where it is used, not only where it is declared ([#2](https://github.com/kcsujeet/kc-claude-kit/pull/2)).
- `working-agreement` rule: answer a question as a question, not as a change request.

## conventions 1.0.0 - 2026-08-21

### Added

- Portable convention rules, installed into a project with `/conventions:init`, and a `SessionStart` hook that reports when they are missing.

## claude-md 1.0.0, testing 1.0.0 - 2026-08-21

### Added

- `claude-md:audit`: audits a repo's instruction setup and proposes a restructure.
- `testing:verify-ui` and `testing:verify-e2e`: verification workflows.

## code-review 1.0.0 - 2026-08-11

### Added

- Initial release: the `review-code` skill, with one subagent per gate reference (naming, clarity, structure, simplicity, datetime, react, i18n, project conventions, verification), per-box PASS/FAIL verdicts, and a drafting and posting protocol for PR comments.
