# Changelog

All notable changes to the plugins in this marketplace. Each plugin is versioned on its own, in its `plugin.json`, and released as a `{plugin}--v{version}` tag.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and each plugin follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- Every plugin and skill is renamed with a `kc-` prefix, so none collides with other public plugins and skills, and no plugin shares a name with one of its skills. Plugins: `conventions` is `kc-conventions` (2.0.0), `code-review` is `kc-gates` (3.0.0), `testing` is `kc-verify` (2.0.0), `instructions` is `kc-instructions` (3.0.0), `autopilot` is `kc-autopilot` (0.2.0), `usage-band` is `kc-usage-band` (2.0.0), `image-preview` is `kc-image-preview` (2.0.0). Skills: every conventions topic is `kc-<topic>` (`kc-conventions:kc-naming`), the review skill is `kc-gates:kc-code-review` and the posting skill `kc-gates:kc-post-review`, the verify skills are `kc-verify:kc-ui` and `kc-verify:kc-e2e`, and `kc-autopilot:kc-init`, `kc-autopilot:kc-run`, `kc-instructions:kc-audit`. Agents keep their names under the new plugin (`kc-gates:naming-gate`). The rules a project installs are now `.claude/rules/kc-<topic>.md`; run `/kc-conventions:kc-init` again and delete the old unprefixed copies. Exported skills for other tools are named `<plugin>-<skill>` (`kc-gates-code-review`). Already installed? Reinstall under the new names:

  ```
  claude plugin uninstall conventions@kc-claude-kit code-review@kc-claude-kit testing@kc-claude-kit instructions@kc-claude-kit autopilot@kc-claude-kit usage-band@kc-claude-kit image-preview@kc-claude-kit
  claude plugin install kc-conventions@kc-claude-kit kc-gates@kc-claude-kit kc-verify@kc-claude-kit
  ```

- `claude-md` is renamed `instructions` (2.0.0), and its skill `claude-md:audit` is now `instructions:audit`. Claude Code now reserves plugin names that start with `claude-`, so `claude plugin validate --strict` rejected the old name and failed CI. Already installed? Swap it:

  ```
  claude plugin uninstall claude-md@kc-claude-kit
  claude plugin install instructions@kc-claude-kit
  ```

- `conventions` 1.2.0: "twice is the threshold" is gone from simplicity §P1 and naming §N3. DRY is about knowledge, so a plain expression with two callers stays inline (§P11), and a repeated domain check becomes a named `isX` at three copies, with a single enum comparison exempt (§N3). Clarity §C12 says the same.
- `code-review` 2.2.0: a self-review runs the gate fan-out only when the user asks, or once before opening a PR for a big change, never after each fix.
- `conventions` 1.2.0: to stay under the 500-line cap, clarity's ternary detail, structure's export detail and react's data-fetching and forms detail moved to `skills/<topic>/references/`. Gates now read those files.

### Added

- `kc-conventions` testing §T12: a UI test awaits only the testing library's waits and events between an action and its last assertion, and ends hover state an action leaves behind, so a slow runner can't land a tooltip or transition update outside them. A CI-only failure is reproduced locally with a delay at the suspected gap before a fix is called done.
- `kc-conventions` 2.0.0: lessons from a cleanup pass on a finished feature, where most of the work was undoing things that were right line by line but built differently from similar code already in the app. Simplicity §P13 now covers everything new, not only new abstractions: every new or reshaped unit (an endpoint, a data read, a function, a file, a message, a test) is matched against about ten pieces of similar code, wherever it lives, in shape, name, place and wording, and a new pattern is the last resort. Rails §RL1 and a new React §R32 say the same for their stacks, with a table of what to match per layer (Rails: validation, the write, controllers and API shape, associations, serializers, queries, jobs and specs; React: data, forms, state, components and styling, names and exports, tests). "Siblings" is gone from these rules: similar code is found by what it does, not by which folder it sits in. Naming §N4 gains a fifth lie, the dropped qualifier: a unit doing the public, archived, cached or admin version of a job is named for it, as its family is, once on the container (`usePublicStore`, and inside it `getStore`). Structure §S19, the caller asks and the provider serves: no trimming or rewriting the request, no loading what nobody asked for. Structure §S18, a moved or renamed file is graded as new code. Correctness §B13, when one becomes many, nothing picks "the" one. Clarity §C20, a comment about other code is checked against that code. Simplicity §P15, deferred work is done in the change that meets its condition. I18n §I8, text shown to people is never also an identifier. Rails §RL5b no longer recommends creating a required record on its first write: it is created with its parent, the way the parent's other default records are. The working agreement gains three lines: read the rules before writing, not only at review; a remark about one detail is about that detail; check what a handed-off audit kept as well as what it found.
- `kc-conventions` 2.0.0: three react rules from QA on a settings screen. §R33, a form with Save and Discard sends nothing before Save: picked and removed files wait in form state and apply in the submit, so Discard leaves the record as it was. §R34, a section out of edit mode shows its saved values through the codebase's read-only display, not inputs disabled until Edit. §R35, an empty slot reads as empty, with muted styling and an icon that names what belongs there (an image icon for a logo, a person only for a person's photo). §R20's detail moved to `references/components.md` with §R35's, to keep the skill under the line cap.
- `kc-conventions` 2.0.0: react §R30's "unless the server can't" no longer covers an endpoint that only lacks the filter. When the team owns the endpoint, the fix is a server filter, shipped before the client that sends it; filtering in code is for data or endpoints out of the team's hands.
- `kc-conventions` 2.0.0: react §R36, a field that picks a record is the codebase's picker component for that kind of record, shaped like the existing ones, not a fetch and an options list inside a form. React §R37, markup two components share is a component taking the differences as props, not a hook that returns JSX. Structure §S15 no longer keeps every single-consumer subcomponent private in its consumer's file: only a small one stays; a bigger one gets its own file in the unit's folder.
- `kc-conventions` 2.0.0: structure §S20, a unit's own helpers share one file named for the unit, `<unit>.utils.ts` beside it, with its constants and types in `<unit>.constants.ts` and `<unit>.types.ts`; shared helpers sit in a file named for their subject. Never a file per function or constant, which scatters one unit's logic over many files and import lines, and never a bare `utils.ts`, `constants.ts` or `types.ts` in a unit's folder, whose repeated name makes file search and editor tabs useless. §S3's detail moved with §S20's to `references/files.md` to keep the skill under the line cap.
- `kc-conventions` 2.0.0: structure §S3 bans big barrels (an `index.ts` gathering a folder, a feature or a package) and allows one unit's `index.ts` re-exporting only its main file with named exports, as bulletproof-react's components do.
- `kc-conventions` 2.0.0: naming says what case files and folders take: `kebab-case` (`order-form/order-form.tsx`, `use-order-form.ts`), as bulletproof-react and most JavaScript and TypeScript codebases do, unless the language names files after their type or the repo already uses another casing. Structure examples use it too.
- `kc-verify` 2.0.0: `kc-ui` walks each section's Discard after a field change, a picked file and a removed file, and checks what each create-form choice adds and the state a new record lands in against the design.
- `kc-verify` 2.0.0: `kc-ui` keeps archived, deactivated and soft-deleted records around and checks every count, list and picker leaves them out; views a record linked to another tenant's records and expects no raw ids and nothing of theirs editable; saves each field with an invalid value as well as cleared; and reads alerts and helper text for plain wording. They come from QA findings that counted archived items, showed another tenant's records as bare ids, and worded a destructive alert in internal terms.
- `kc-gates` 3.0.0: three hard rules. A round reviews one version of the code: no edits while gates run, and a fix made during or after a round is unreviewed until a new round covers the whole diff. A duplication finding on a one- or two-line expression is answered by leaving it inline. When two gates' fixes for one construct conflict, both go to the user to choose.
- `conventions` 1.3.0: react §R30, a read asks the server for what the screen shows: any list, table, picker, search, count or lookup sends its narrowing in the request, as sibling reads do, and names related records from the response that already carries them instead of a second fetch. React §R31, a form that shows only part of a set (one storefront's links) seeds that part and sends the rest back unchanged. Rails §RL5e, a write that replaces a set checks access to the ids it removes as well as the ones it adds. Rails §RL4d now names an association's ids as an attribute as the same copy, with its per-record query risk. They come from a form that showed another storefront's links as bare ids, let them be removed, and fetched its picker's list a second time to find out which to show.
- `conventions` 1.3.0: correctness §B11, a client that mirrors a server calculation reads each input from the record the server reads. It comes from a checkout that read a discount from a record a shop could delete while the server read a settings row, so it showed full price and the payment failed. Correctness §B12, a list shows only what the viewer can open, by the same check each item's page applies.
- `conventions` 1.3.0: testing §T11, a test pins every input its result depends on, instead of a factory default that may be sampled. It comes from a new case that left a sampled offset unset and failed about one run in fifty.
- `conventions` 1.3.0: testing §T10, time comes from a clock the test can freeze: code compared against now binds the app's time instead of reading the database clock, and its tests freeze it. It comes from a scheduled-job spec that failed only when CI ran across 23:59 or midnight.
- `conventions` 1.3.0: correctness §B10, a fix covers its whole class: the cause is written as a pattern, grepped across code and tests, and every hit gets a verdict. Testing §T9, a test names its expected record (the one it created, or an order ending on a unique key) instead of `first` over an order that can tie. Both come from a flaky ordering fixed in the code while a test written the same day kept the same tied query.
- `conventions` 1.3.0: correctness §B9, a claim about what a value holds comes from all its writers, included modules and their callbacks among them. It comes from a flaky test blamed on positions being blank, when an included concern numbered them within each group, so two rows tied at the first position.
- `testing` 1.1.0 and `code-review` 2.2.0: the browser check is not optional. A UI fix is seen fixed in a browser before it is reported done or anyone is told it is fixed, and the check is never offered as a choice ("QA first, or post as is?"). The verification gate's self-review item fails both, and the "say it could not be rendered" exit now applies only when the session has no way to render the UI at all. It comes from a QA round whose fixes were reported to the tester after tests alone.
- `conventions` 1.3.0: react §R29, a minimum size on a flex item is checked against its parent. An explicit `min-height` replaces the default `min-*: auto`, so under a fixed-height flex parent the item shrinks to that minimum and long content runs past its background; `flex-shrink: 0` keeps it at least one screen tall under any parent. `testing` 1.1.0: `verify-ui` traces a reported layout defect through its ancestors in code and reproduces it at the reported content size instead of parking it for a browser look, and Step 5 looks for a background that stops before the content does. Both come from a page whose background ended one screen down once its list grew.
- `conventions` 1.3.0: simplicity §P14, a branch for a data state (a blank field, a legacy shape) needs evidence the state can still occur; one that create-time defaults, validations or a finished backfill rule out fails. Rails §RL4e, serializer params carry the data, not a flag worked out for one consumer.
- `conventions` 1.3.0: rails §RL4d, the client asks for what it needs. A serializer exposes its own model's attributes; another model's data reaches the client only through a relationship the client includes, not as attributes copied across serializers or sent by default.
- `testing` 1.1.0: `verify-ui` gains Step 3b, the flows around a change, with a gate box for each: switch the current tenant on each changed page, visit every screen that shows data derived from a write, use records in states the new UI can't create, do each interaction twice, clear every field and save, check each confirmation's words against what happened, check signed-in state everywhere it shows, fill a page past the viewport, and take a freshly created record through its whole flow. They come from a QA round that found fifteen issues in a feature whose screens each passed their state matrix.
- `conventions` 1.3.0: react §R28, cached data follows its context and its filters: a query key includes the current tenant or user when the response depends on it, a write refetches filtered lists rather than patching them, and refetches counts derived from it. Correctness §B7, a count uses the same filter as its list, and §B8, when a value's meaning changes every reader of it is checked, untouched ones included.
- `conventions` 1.3.0: simplicity §P11 also fails a helper whose body is one call to an existing function on a field of its argument (`toWidgetId = (widget) => toNumber(widget.id)`). The conversion already lives in the function it calls, so a comment calling the helper a conversion no longer earns it a pass, and the evidence shows how the repo writes the same expression elsewhere.
- `conventions` 1.3.0: naming §N11, a name follows what its subject became. When a change turns one thing into many (a settings page into a list with a page per record), the route segments, folders, files, keys and paths that still describe the old shape are checked against siblings that already have the new shape, including names the diff never touched, and renamed or given a stated reason to wait.
- `conventions` 1.3.0: two boxes for failures that raise no error. Correctness §B6: a new reference between modules is traced for a load cycle, and a cycle through code that does work at definition time (a subclass copying its parent's fields, a registry, class-level configuration) fails unless the reference is lazy; clarity §C14 stays soft for plain cycles and points there. Testing §T8: a test of an output asserts a value inside it, so an empty response fails, and shared response helpers are held to the same rule. Both come from a serializer that silently lost its fields in production while every status-only request test passed.
- `testing` 1.1.0: `verify-e2e` gains three hard rules. Run the flow in what users get (the app, its demo or default configuration), not only the test harness; "loads with no errors" is not "works"; and a probe counts only after it has been shown it can both fail and pass, with the target confirmed under the pointer. It carries the example of a release whose headline drag feature passed every harness spec and QA round, then looked broken in the project's public demo because the demo's defaults refused the drop, and a first investigation with flawed probes reported a bug that did not exist. Step 2 now brings up the shipped system. `verify-ui` points to the same rule: look at the shipped screen, not a story or fixture page.
- `conventions` 1.2.0: a testing rule: when the end-to-end suite runs in a harness or fixture app, each headline feature also gets a test that drives the shipped app with its default configuration and seed data.
- `autopilot` 0.1.0: plan in, PRs out. `/autopilot:init` writes and proves a per-repo recipe (boot, seed, login, checks) in `.claude/autopilot.json`; `/autopilot:run <plan.md> [--dry-run]` has the staff-engineer `run` skill (on `best`) validate the plan, decide the cross-unit approach and write each unit's contract and QA personas, then starts the `autopilot:deliver` workflow. Each unit runs an engineer, `code-review`'s gates, lens reviewers, persona QA in a headless Playwright browser and an independent verifier until clean, then opens a ready PR, linked as a GitHub native stacked PR when units depend on each other (falling back to a base-branch chain), with screenshots attached when they help. Blocked units come back with reasons, and bugs QA found that the change did not cause are reported, not fixed. Workers run on `sonnet` and staff roles on `best`. A `PreToolUse` guard keeps autopilot's own agents from editing run files or the config, skipping or deleting tests, and (engineer) touching risky paths or adding dependencies. Depends on `code-review` (`^2.0.0`), `conventions` (`^1.1.0`) and `testing`. It never merges, enables auto-merge, force-pushes or pushes to `main`. Measured on Claude Code 2.1.292: a 2-unit dry run cost about $6 to $8 and 8 to 12 minutes. Script tests run by CI; the end-to-end dry run is manual (`plugins/autopilot/tests/e2e/README.md`).
- `conventions` 1.2.0, new boxes. Naming: `isOn`-style names fail §N5; a new file follows 2-3 named siblings without breaking §N7 (§N8); a name shows its kind and owner (§N9); parts of one unit keep its prefix and kind (§N10). Simplicity: a helper earns its place by the knowledge it carries (§P11); defaults over per-scenario variants (§P12); a new pattern cites 2 places or asks first (§P13). Clarity: every conditional spread is a finding, with a new `conditional-spreads.sh` sweep (§C19); ternary hits are labelled single-line or MULTI-LINE. Structure: passthrough returns and `onSuccess`-only wrappers are dead (§S4); a module exports what it is named for (§S13); new code acts on its home's subject (§S14); one exported component per file (§S15); `app/` holds routes only (§S16). React: `ref` as a prop on React 19 (§R20), request method matches effect (§R21), narrowest cache key (§R22), write hooks own one resource (§R23), form hooks return plumbing only (§R24), watches in the smallest component (§R25), forms seed the related record (§R26), read hooks wire every option (§R27). Correctness: every submitted value traced per state (§B5), with testing §T7 asserting the request body per state.
- `code-review` 2.2.0: a sweep is never cut short (hit count equals verdict count); every proposed fix passes every gate's rules; the orchestrator verifies each gate finding at the head SHA before relaying it and lists dropped ones on a `Dropped:` line. The verification gate checks fixes re-checked and rewrites checked (§V8), conditional-spread and MULTI-LINE receipts, and, in a self-review, that UI changes were looked at rendered in a browser.

- `code-review` 2.1.0: `post-review` drafts read like a person wrote them. There is no stock opener (the "Could we / Worth" list is gone), and two drafts can't open the same way. The ask comes by the second sentence instead of first. "Simple words" is now a check (no hard words, no sentence over about 25 words, nothing that needs the code open). Proof such as test steps or error text appears only when the reader asked for it or will use it, with no greeting opener, bold list labels or closing restatement. Small nits are left out of the draft set, every new name in a code example is explained, a reply that keeps the code explains gently before saying so, and the label comes from the table rather than the user's reaction. A new "The spec is closed" section lists the shapes that must not be invented.
- `usage-band` 1.1.0: a pill with the current git branch (hidden outside a repository and on a detached HEAD), refreshed at session start, on each prompt and after each Bash call. The context, 5-hour and 7-day percentages turn dark amber from 70% and dark red from 90%, both at least 5.6:1 contrast on their pills (WCAG AA asks 4.5:1). When a narrow terminal wraps the pills, a blank row now separates each line of them.
- `image-preview` 1.0.0: thumbnails of pasted images above the prompt. Ghostty and kitty get the real picture through the `Image` element; other terminals, Apple Terminal among them, get half-block `Raster` cells decoded from a `sips`-resampled BMP. A copied Finder image file (which pastes as its icon) previews the real file, and on send Claude gets a note naming it. The band beneath (another plugin's row) is kept. macOS only. Tests run by `claude plugin test`.
- `usage-band` 1.0.0: a row of pills above the prompt showing the model, the context window's fill, the 5-hour and 7-day rate limits with time until each resets, input, output and cache-read tokens summed over every model request (subagents included), and the session's cost. Built on Claude Code's function hooks (`ui.render` on `AbovePrompt`, `session.measure`, `turn.step`), with tests run by `claude plugin test`.

### Fixed

- Removed links to `docs/review-conventions.md` from the README, `review-code`, `project-conventions-gate` and `docs/architecture.md`. The file was never committed; the README's own paragraph describes the `.claude/review-conventions.md` format.
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
