# Changelog

All notable changes to the plugins in this marketplace. Each plugin is versioned on its own, in its `plugin.json`, and released as a `{plugin}--v{version}` tag.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and each plugin follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- `claude-md` is renamed `instructions` (2.0.0), and its skill `claude-md:audit` is now `instructions:audit`. Claude Code now reserves plugin names that start with `claude-`, so `claude plugin validate --strict` rejected the old name and failed CI. Already installed? Swap it:

  ```
  claude plugin uninstall claude-md@kc-claude-kit
  claude plugin install instructions@kc-claude-kit
  ```

- `conventions` 1.2.0: "twice is the threshold" is gone from simplicity §P1 and naming §N3. DRY is about knowledge, so a plain expression with two callers stays inline (§P11), and a repeated domain check becomes a named `isX` at three copies, with a single enum comparison exempt (§N3). Clarity §C12 says the same.
- `code-review` 2.2.0: a self-review runs the gate fan-out only when the user asks, or once before opening a PR for a big change, never after each fix.
- `conventions` 1.2.0: to stay under the 500-line cap, clarity's ternary detail, structure's export detail and react's data-fetching and forms detail moved to `skills/<topic>/references/`. Gates now read those files.

### Added

- `conventions` 1.2.0, new boxes. Naming: `isOn`-style names fail §N5; a new file follows 2-3 named siblings without breaking §N7 (§N8); a name shows its kind and owner (§N9); parts of one unit keep its prefix and kind (§N10). Simplicity: a helper earns its place by the knowledge it carries (§P11); defaults over per-scenario variants (§P12); a new pattern cites 2 places or asks first (§P13). Clarity: every conditional spread is a finding, with a new `conditional-spreads.sh` sweep (§C19); ternary hits are labelled single-line or MULTI-LINE. Structure: passthrough returns and `onSuccess`-only wrappers are dead (§S4); a module exports what it is named for (§S13); new code acts on its home's subject (§S14); one exported component per file (§S15); `app/` holds routes only (§S16). React: `ref` as a prop on React 19 (§R20), request method matches effect (§R21), narrowest cache key (§R22), write hooks own one resource (§R23), form hooks return plumbing only (§R24), watches in the smallest component (§R25), forms seed the related record (§R26), read hooks wire every option (§R27). Correctness: every submitted value traced per state (§B5), with testing §T7 asserting the request body per state.
- `code-review` 2.2.0: a sweep is never cut short (hit count equals verdict count); every proposed fix passes every gate's rules; the orchestrator verifies each gate finding at the head SHA before relaying it and lists dropped ones on a `Dropped:` line. The verification gate checks fixes re-checked and rewrites checked (§V8), conditional-spread and MULTI-LINE receipts, and, in a self-review, that UI changes were looked at rendered in a browser.

- `code-review` 2.1.0: `post-review` drafts read like a person wrote them. There is no stock opener (the "Could we / Worth" list is gone), and two drafts can't open the same way. The ask comes by the second sentence instead of first. "Simple words" is now a check (no hard words, no sentence over about 25 words, nothing that needs the code open). Proof such as test steps or error text appears only when the reader asked for it or will use it, with no greeting opener, bold list labels or closing restatement. Small nits are left out of the draft set, every new name in a code example is explained, a reply that keeps the code explains gently before saying so, and the label comes from the table rather than the user's reaction. A new "The spec is closed" section lists the shapes that must not be invented.
- `usage-band` 1.1.0: a pill with the current git branch (hidden outside a repository and on a detached HEAD), refreshed at session start, on each prompt and after each Bash call. The context, 5-hour and 7-day percentages turn dark amber from 70% and dark red from 90%, both at least 5.6:1 contrast on their pills (WCAG AA asks 4.5:1). When a narrow terminal wraps the pills, a blank row now separates each line of them.
- `image-preview` 1.0.0: thumbnails of pasted images above the prompt. Ghostty and kitty get the real picture through the `Image` element; other terminals, Apple Terminal among them, get half-block `Raster` cells decoded from a `sips`-resampled BMP. A copied Finder image file (which pastes as its icon) previews the real file, and on send Claude gets a note naming it. The band beneath (another plugin's row) is kept. macOS only. Tests run by `claude plugin test`.
- `usage-band` 1.0.0: a row of pills above the prompt showing the model, the context window's fill, the 5-hour and 7-day rate limits with time until each resets, input, output and cache-read tokens summed over every model request (subagents included), and the session's cost. Built on Claude Code's function hooks (`ui.render` on `AbovePrompt`, `session.measure`, `turn.step`), with tests run by `claude plugin test`.

### Fixed

- The code-review eval suite could not load: its cases list `../../../conventions`, which sits outside the eval runner's containment root when the target is `plugins/code-review`. CI and the README now run it from the repo root with `--eval-dir plugins/code-review/evals`. Measured: all 3 code-review cases pass.
- The README and the code-review 2.0.0 release notes now say that upgrading from 1.x needs `claude plugin install conventions@kc-claude-kit`, since `claude plugin update` does not install the new dependency.

## conventions 1.1.0, code-review 2.0.0 - 2026-09-23

The restructure described in [`docs/architecture.md`](docs/architecture.md): each convention is stated once, as a skill used both when writing and when reviewing.

### conventions 1.1.0

#### Added

- One skill per topic under `skills/<topic>/SKILL.md` (naming, clarity, structure, simplicity, datetime, react, i18n, testing, correctness, type-safety, error-handling, performance, dependencies), invoked as `conventions:<topic>`. Each holds the authoring rules, the review checklist, the per-box review detail, and the topic's sweeps.
- Deterministic sweep scripts under `skills/<topic>/scripts/`, each printing one `file:line: text` hit per line, with fixture tests in `tests/`.
- `scripts/build-rules.sh`, which generates `rules/<topic>.md` from each skill's `## Rules` section and `paths`, and fails on drift with `--check`.
- Eval suite under `evals/`, run with `claude plugin eval`.
- `scripts/install-rules.sh`, which `/conventions:init` now runs: it finds the rules relative to itself, copies them, writes the version stamp, and reports each rule as new, unchanged or replaced (`--dry-run` to preview). Tests in `tests/install-rules.test.sh`.
- Lookups that take a name or key instead of a diff: `skills/naming/scripts/name-collisions.sh` (§N5) and `skills/i18n/scripts/locale-duplicates.sh` (§I3), replacing the inline greps in those sections. Fixtures run by `tests/run-lookups.sh`.
- `correctness` topic (§B1-§B4): logic errors, edge cases including timezone, data that does not match its declared type at a boundary, and regressions of bugs the repo already fixed. Derived from ilamy-calendar's retired review skill.

#### Changed

- `rules/` is generated from the topic skills and never edited by hand. `working-agreement.md` stays the one hand-written rule.
- `/conventions:init` writes a version stamp beside the installed rules, and the `SessionStart` hook now reports stale rules as well as missing ones.

### code-review 2.0.0

#### Changed

- **Breaking:** posting to GitHub moved out of `review-code` into the user-invoked `/code-review:post-review` skill (`disable-model-invocation: true`). A `PreToolUse` hook blocks any GitHub write whose Bash command does not carry `KC_REVIEW_POST_APPROVED=1`.
- **Breaking:** gates are plugin agents under `agents/`: `code-review:<topic>-gate` for naming, clarity, structure, simplicity, datetime, react, i18n, testing and correctness, each read-only (`Read, Grep, Glob, Bash, Skill`, `model: sonnet`) and preloading its `conventions:<topic>` skill, plus `code-review:project-conventions-gate` and `code-review:verification-gate` (phase 2). The `skills/review-code/references/` directory is gone: topic rules moved to the conventions skills, the gate contract into the agents, the repo-author format guide to `docs/review-conventions.md`, and the PR-comment protocol to `post-review`.
- **Breaking:** depends on the `conventions` plugin (`^1.1.0`) through `dependencies`, which installs it automatically.
- `review-code` is now an orchestrator only: it saves the diff to a file, runs the scope checks, dispatches the gates by `subagent_type`, and aggregates. If a gate agent is unavailable it falls back to a `general-purpose` agent that invokes the `conventions:<topic>` skill, and reports the fallback.
- Gates run the conventions sweep scripts against the saved diff instead of ad hoc greps.
- A rule in the target repo's `.claude/review-conventions.md` that contradicts a built-in convention now wins for that repo; the built-in box is reported as overridden, citing the repo rule.
- A topic gate whose preloaded skill did not load (Claude Code skips a missing preloaded skill silently) invokes the skill with the Skill tool, and returns FAIL with `topic skill unavailable` if that fails too, so no gate grades a topic from memory.
- Bug hunting is a mandatory gate: `code-review:correctness-gate` runs on every review, and the optional "Possible bug" report section is gone.
- A finding that cannot be confirmed (an untraced possible bug, a judgment call with no evidence from the code or docs) is dropped instead of softened into a "maybe". A confirmed checklist violation is still never dropped or softened.
- Em dashes are banned in every output surface: the chat report, gate verdict blocks, drafted comments and replies. Output templates and examples in the skills and agents no longer use them.
- Every drafted `suggestion` comment carries a brief reason inside the one-to-three-sentence budget.

#### Added

- `hooks/hooks.json` and `scripts/guard-github-post.sh`: a `PreToolUse` guard on Bash that denies `gh pr comment`, `gh pr review`, `gh issue comment` and `gh api` writes to PR or issue comments and reviews unless the command carries `KC_REVIEW_POST_APPROVED=1`, with tests in `tests/guard-github-post.test.sh`.
- Orchestration scripts under `scripts/`, which `review-code` Step 1 now runs in place of inline `gh`/`git` commands: `gather-review.sh` (diff, changed files and `meta.env` for a PR or a branch), `scope-facts.sh` (the §G1-§G3 facts), and `review-threads.sh` (reply threads on a re-review). Gates receive `DIFF_FILE` and `HEAD_SHA` from `meta.env`.
- `scripts/build-comment-payloads.sh`: `post-review` passes every draft through it before a post. It validates each draft's path and line against the diff's hunks, writes the payloads, and prints the approval-token commands the user approves. It never posts.
- Tests for all four under `tests/`, run against a stub `gh` in `tests/lib/`.
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
