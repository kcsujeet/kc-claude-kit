# kc-claude-kit `code-review` Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the public `kcsujeet/kc-claude-kit` Claude Code plugin marketplace containing the `code-review` plugin, whose `review-code` skill is a generalized, repo-agnostic port of Event Temple's `review-NFE-code` gate-based review skill.

**Architecture:** A marketplace repo (`.claude-plugin/marketplace.json`) wrapping one plugin (`plugins/code-review/`) with one skill (`skills/review-code/`). The skill is an orchestrator `SKILL.md` plus 10 reference files — 9 gates + 1 PR-comment protocol. Each gate file carries a `## Gate checklist` block that a dedicated subagent walks per review.

**Tech Stack:** Markdown + JSON only. No build step. Validation via `jq`, `wc -l`, and `grep`.

## Global Constraints

- Every `.md` file in the skill stays **under 500 lines** (hard cap from the source skill's own rule).
- **Zero Event Temple identifiers** in any output file. Banned tokens (grep must return 0 hits across the repo): `eventtemple`, `EventTemple`, `Event Temple`, `NFE`, `et-types`, `@repo/`, `@eventtemple/`, `useDateTime`, `useRefetch`, `useQueryCacheUpdater`, `useProposalTranslations`, `safeNumber`, `getIncludes`, `DrawerFormProps`, `Crowdin`, `apps/client`, `apps/portal`, `valibot`, `Ransack`, `common.json`, `actions.json` (the i18n gate speaks of "the shared/common namespace file" and "an actions/verb-template file *if the project has one*", not ET's literal filenames).
- Code examples use **generic placeholder names** (`flagA`, `someStatus`, `useXs`, `Widget`) and generic shapes — never identifiers or operations lifted from the ET source.
- No canonical ET file paths. Where the source says "canonical: apps/client/…", the port says "grep the target repo for 2–3 existing examples before citing the convention".
- All `gh`/`git` commands in the skill are **parameterized**: repo inferred from working directory, default branch detected via `git remote show origin` or `gh repo view --json defaultBranchRef`, never hardcoded.
- Every rule is expressed as a **checklist of independent failure modes**; every gate file has a `## Gate checklist` block; every box states its own N/A condition.
- Names are fixed: repo `kc-claude-kit`, plugin `code-review`, skill `review-code`.
- **Source material** lives at `/Users/sujeetkc/.claude/plugins/marketplaces/event-temple/plugins/event-temple-typescript/skills/review-NFE-code/` (referred to below as `$SRC`). Implementers MUST read the named source file before writing each port.
- **Git:** initialize the repo and commit locally after each task — but ONLY after the user has explicitly approved local commits at the start of execution (ask once). Creating the GitHub repo and pushing (Task 13) each require their own explicit user approval. Never push without the literal word from the user.
- Design spec: `docs/design.md` in this repo — the gate registry table there is the authoritative scope for each gate file.

---

### Task 1: Repo scaffolding + manifests

**Files:**
- Create: `.claude-plugin/marketplace.json`
- Create: `plugins/code-review/.claude-plugin/plugin.json`
- Create: `README.md`
- Create: `.gitignore`

**Interfaces:**
- Produces: marketplace name `kc-claude-kit`, plugin name `code-review` — Task 13's install commands depend on these exact strings.

- [ ] **Step 1: Init git repo**

```bash
cd /Users/sujeetkc/Desktop/kc-claude-kit && git init -b main
```

- [ ] **Step 2: Write marketplace.json**

```json
{
  "$schema": "https://anthropic.com/claude-code/marketplace.schema.json",
  "name": "kc-claude-kit",
  "owner": {
    "name": "Sujeet Kc",
    "email": "kcsujeet@gmail.com"
  },
  "metadata": {
    "description": "Sujeet's personal Claude Code toolkit — reusable plugins for any codebase"
  },
  "plugins": [
    {
      "name": "code-review",
      "source": "./plugins/code-review",
      "description": "Gate-based code review: one subagent per rule file, per-box PASS/FAIL verdicts, zero rationalized skips",
      "version": "1.0.0"
    }
  ]
}
```

(Verify the owner email: run `git config user.email` and use that value if it differs.)

- [ ] **Step 3: Write plugin.json**

```json
{
  "name": "code-review",
  "description": "Gate-based code review: one subagent per rule file, per-box PASS/FAIL verdicts, zero rationalized skips",
  "version": "1.0.0",
  "author": {
    "name": "Sujeet Kc",
    "email": "kcsujeet@gmail.com"
  }
}
```

- [ ] **Step 4: Write README.md**

Content requirements (write actual prose, ~60 lines):
- Title `# kc-claude-kit`, one-line pitch.
- Install section:
  ```
  /plugin marketplace add kcsujeet/kc-claude-kit
  /plugin install code-review@kc-claude-kit
  ```
- "What's inside" table: `code-review` plugin → `review-code` skill, one-line description.
- How the review works: 3–4 sentences on the gate fan-out (one agent per rule file, any finding fails its gate, gate-status table leads the report).
- Per-repo extension: document `.claude/review-conventions.md` — if the target repo has this file, it becomes an extra gate; link to `plugins/code-review/skills/review-code/references/project-conventions.md` for the format.
- Gate list table (9 gates + dispatch conditions, copy from `docs/design.md`).

- [ ] **Step 5: Write .gitignore**

```
.DS_Store
```

- [ ] **Step 6: Validate JSON**

Run: `jq . .claude-plugin/marketplace.json && jq . plugins/code-review/.claude-plugin/plugin.json`
Expected: both print parsed JSON, exit 0.

- [ ] **Step 7: Commit** (if user approved local commits)

```bash
git add -A && git commit -m "Scaffold kc-claude-kit marketplace with code-review plugin manifests"
```

---

### Task 2: SKILL.md orchestrator

**Files:**
- Create: `plugins/code-review/skills/review-code/SKILL.md`
- Read first: `$SRC/SKILL.md`

**Interfaces:**
- Produces: the gate registry table mapping gate names → `references/<file>.md`; the gate-agent contract format (`GATE:/STATUS:/BOXES:/FINDINGS:`); the output format. Every gate file task (3–12) must match the gate names and verdict format defined here.

- [ ] **Step 1: Read the source** `$SRC/SKILL.md` in full.

- [ ] **Step 2: Write SKILL.md** with this structure (port each section, applying Global Constraints):

**Frontmatter:**
```yaml
---
name: review-code
description: Gate-based code review for a PR, branch, or set of changes in any repo. Trigger on "review this PR", "review my code", "review my changes", "review my branch", "is this clean", "is this good to merge", "code review please", a bare PR URL, or a branch name. Fans out one subagent per rule file (naming, clarity, structure, simplicity, datetime, react, i18n, project conventions, verification), aggregates per-box PASS/FAIL verdicts into a single PASSED/FAILED result. Reads the target repo's own .claude/review-conventions.md as an extra gate when present. Output stays in chat only - never posts comments to the PR without explicit approval.
---
```

**Hard rules** (port from source, generalized — keep ALL of these):
1. Failing even ONE checklist item is worth raising (walk each box independently; don't pattern-match a rule to its example domain).
2. DRY / YAGNI / KISS as a standing lens on every diff, any-finding-fails weight.
3. Never post anything to GitHub on your own — chat only; posting follows `references/pr-comments.md`.
4. Verify conventions against the target codebase before flagging (grep for 2–3 existing examples, cite paths).
5. Confirm it's a deviation, not a misread — accuracy check, NOT a suppression license.
6. Surface everything; "intentional / defensible / matches the neighbors / low-value" are descriptions for the human, never reasons to withhold.
7. Any finding fails its gate; severity (🔴/🟠/🟡) calibrates weight communicated, never whether the gate passes.
8. Examples in rules are illustrations, never an exhaustive boundary.
9. Read the actual changed code with the Read tool; subagent summaries are a starting point.
10. Cite `file:line` + head SHA for every finding.
11. Locale diffs require the per-key audit table (see `references/i18n.md`) — never an aggregate grep. (Drop the ET-specific common.json/dictionary war stories; keep the rule and the "no new keys / matches neighbors / low-value are the three invalid rationalizations" warning.)

**Workflow** (port Steps 1–4):
- Step 1 gather context: `gh pr diff <num>` / `gh pr view <num> --json headRefOid,title,files` (repo inferred from cwd), or `git diff $(git rev-parse --abbrev-ref origin/HEAD | sed 's|origin/||')...HEAD` for a branch; fetch PR head if needed; on re-review fetch reply threads and classify author responses (fixed-with-SHA → verify the whole class / reasoned-push-back → don't re-post, surface to user / no-reply → re-raise).
- Step 2 fan out one agent per reference file, ALL gates EVERY round. Gate registry table:

| Gate | Reference file | Dispatch note |
|------|----------------|---------------|
| naming | `references/naming.md` | always |
| clarity | `references/clarity.md` | always |
| structure | `references/structure.md` | always |
| simplicity | `references/simplicity.md` | always |
| datetime | `references/datetime.md` | agent returns PASS (N/A) if no date/time logic in diff |
| react | `references/react.md` | agent returns PASS (N/A) if no React/TS code in diff |
| i18n | `references/i18n.md` | agent returns PASS (N/A) if no locale files in diff |
| project-conventions | `references/project-conventions.md` | agent returns PASS (N/A) if target repo has no `.claude/review-conventions.md` |
| verification | `references/verification.md` | always |

Every gate is dispatched even when it looks inapplicable; N/A is the agent's verdict, never the orchestrator's assumption.
- Step 3 gate-agent contract (verbatim structure from source): agent gets gate name, owned reference file path, head SHA, changed-file list, diff; must (1) read the ENTIRE reference file including `## Gate checklist`, (2) sweep greppable constructs FIRST with per-hit `file:line` verdicts and explicit `0 hits`, (3) evaluate every box against every matching construct, grep the target repo before citing a convention, (4) return only:
  ```
  GATE: <name>
  STATUS: PASS | PASS (N/A) | FAIL
  BOXES:
  - [PASS|FAIL|N/A] <box id> — <evidence: file:line, grep result, or "no matching construct in diff">
  FINDINGS:
  - <severity 🔴|🟠|🟡> <file>:<line> — <issue> — <fix>
  ```
  (5) FAIL semantics: any violating construct fails the box; any failed box fails the gate; no averaging.
- Step 4 aggregate: PASSED only when every gate is PASS / PASS (N/A); single FAIL box ⇒ FAILED; a gate that lists a finding cannot be PASS; emit gate-status table → deduped findings → explicit verdict.
- Self-review trigger paragraph (when the reviewer authored the diff, same fan-out before declaring done; gates may run inline for small self-reviews but every box still gets walked).
- "Matches the existing pattern is a yellow flag, not a green light" paragraph.

**Output format** (port verbatim, adjusting the gate list in the table to the 9 gates):
- Terse; one finding = one line; severity emoji prefix; `file:line` first; no explanation paragraphs; skip empty section headers; gate-status table is mandatory and leads the report; the good-vs-bad finding examples (genericize the file names in them).

**Drafting and posting PR comments** section: two-line summary + pointer to `references/pr-comments.md` (label-on-own-line is mandatory; posting needs a fresh standalone signal).

**What this skill is not**: not a bug scan (mention real bugs under "Possible bug" but don't let it take over), not a security review, does not post to GitHub on its own.

**Notes for iteration** (port items 1–8, updating the file-routing table to the new gate files: naming→naming.md, ternaries/comments/magic numbers→clarity.md, placement/dead wrappers/exports/enums→structure.md, reuse/DRY→simplicity.md, dates→datetime.md, React/data-fetching/forms/bulletproof-react→react.md, translations→i18n.md, comment protocol→pr-comments.md, workflow/hard rules→SKILL.md; repo-specific feedback → suggest the user put it in that repo's `.claude/review-conventions.md` instead). Keep: generic-names-AND-generic-shape rule for examples, checklist-of-failure-modes rule, gate-checklist-block-mandatory rule, 500-line cap, topic-not-proximity splits, don't over-fragment.

- [ ] **Step 3: Verify**

Run: `wc -l plugins/code-review/skills/review-code/SKILL.md` → under 500.
Run the banned-token grep from Global Constraints against the file → 0 hits.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "Add review-code SKILL.md orchestrator"
```

---

### Task 3: references/naming.md

**Files:**
- Create: `plugins/code-review/skills/review-code/references/naming.md`
- Read first: `$SRC/references/naming.md`

**Interfaces:**
- Produces: gate name `naming` with boxes §N1–§N4 (renumber from the source's §5/§5.1/§5.3 — each gate file renumbers its boxes with a gate-letter prefix so findings never cite ET section numbers).

- [ ] **Step 1: Read the source**, then write the port. Keep/transform map:

| Source | Action |
|---|---|
| §5 role-not-type (incl. `handleX` hiding the effect) | Keep whole. Replace the two ET canonical examples with generic ones; drop file paths. |
| §5 inline boolean chains + operands-not-just-outer-name rule | Keep whole (this is the gate's core). Keep the "outer named boolean does NOT exempt its RHS" block with generic example. |
| §5 repeated predicate → named helper / type guard | Keep; genericize the ApiError example to `SomeError` + `status`/`code`. |
| §5 defensive `?.` + `!== undefined` stacked on `Boolean()` | Keep with generic field names. |
| §5.1 honest names (all five failure modes + worked example) | Keep whole; the `chainLoginPath → chainMemberLoginPath` example becomes a generic `orgLoginPath → orgMemberLoginPath`-style example with placeholder domain words (e.g. `groupInvitePath` that actually builds a member-invite URL). |
| §5.3 grep sweep | Keep whole; command becomes `gh pr diff <num> \| grep -nE '^\+.*(\&\&\|\|\|)'` (already generic); evidence format with per-hit verdicts + `0 hits` receipt. |

**Gate checklist block** (write exactly):

```markdown
## Gate checklist

The naming gate agent ticks every box against the diff. A box is FAIL if any matching identifier/expression violates the rule; the gate is FAIL if any box is FAIL. N/A only when the diff adds no new identifiers or boolean expressions.

- [ ] §N1 Role-not-type names: new variables/functions describe the role, not the type (no `data`/`result`/`value`/`temp`/`item`/`obj` for behavior-bearing values); function names describe the effect, not just the trigger. (N/A: no new identifiers)
- [ ] §N2 Inline boolean chains — evaluate the OPERANDS, not just the outer name: any `&&`/`||` chain with 2+ non-obvious operands (raw comparisons, enum (in)equalities, negations, `?.` field access) has EACH non-obvious operand extracted to its own named boolean. Assigning the whole chain to a named boolean does NOT satisfy this. Enumerate by grep, do not eyeball. (N/A: only when the grep returns 0 hits, stated as `grepped &&/||: 0 hits`)
- [ ] §N3 Cross-call-site predicate: the same predicate repeated in 2+ places is extracted to a named helper (type guard when narrowing helps). (N/A: no repeated predicate)
- [ ] §N4 Honest names: each new name reads as a sentence that matches the actual behavior/subject — no surface-word gluing, no subject elision, no context-as-subject, no stale-after-refactor names, no familiar-shaped name hiding a different behavior or constraint. (N/A: no new names)
```

- [ ] **Step 2: Verify** — `wc -l` under 500; banned-token grep → 0 hits; file contains `## Gate checklist`.

- [ ] **Step 3: Commit** — `git add -A && git commit -m "Add naming gate reference"`

---

### Task 4: references/clarity.md

**Files:**
- Create: `plugins/code-review/skills/review-code/references/clarity.md`
- Read first: `$SRC/references/clarity.md` and `$SRC/references/layout.md` (§4.7 only)

**Interfaces:**
- Produces: gate name `clarity` with boxes §C1–§C16.

- [ ] **Step 1: Read the sources**, write the port. Keep/transform map:

| Source | Action |
|---|---|
| §1 dense guard clauses | Keep. |
| §2 defensive coercion | Keep, including the form/input-context exception (genericized: "form libraries and HTML inputs pass strings at runtime; `String(a) === String(b)` where one side comes from an input/form read is genuinely defensive"). |
| §2.1 field access not on the type | Generalize: "every new `record.someField` access is declared on the record's type/interface; optional-chained access to an undeclared field widens to `any` and TS catches nothing — the interface needs updating in the same PR". Drop et-types paths. |
| §2.2 redundant `as T` | Keep whole. |
| §3 logic/rendering tangled | Keep the skip-via-ternary-in-map block and the side-effect-only-component blocker, but MOVE both to react.md (they're React-specific). In clarity.md keep only the general "side-effects out of render/computation closures; pull into named handlers" principle. |
| §4 comments | Keep whole (earn-their-place, density-is-a-finding, flag/don't-flag lists). |
| §5 two-step mutations | Keep. |
| §6 magic spreads | Keep. |
| §6.1 inline anonymous structural types | Keep, generic example already. |
| §6.2 3+-operand fallback chains | Keep. |
| §6.3 unhappy-path tangled | Keep with the generic request/ApiError example (already placeholder-ish; rename to `SomeError`). |
| §6.4 thin-wrapper over-extraction | Keep whole. |
| §6.5 dense inlined sub-expressions | Keep. |
| §7 circular imports (soft) | Keep. |
| §7.1 ternary checklist | Keep whole — nested/long/multi-line/non-trivial-branch boxes, value-ternaries-count-too block, named-boolean fix examples. |
| §7.2 renderXxx() | MOVE to react.md (React-specific). |
| §7.3 compound booleans | Keep (note the overlap with naming §N2; keep §7.3's "finding must include the refactored version" requirement). |
| §9.1 grep sweep for ternaries + casts | Keep whole with the generic grep commands and receipt format. |
| layout.md §4.7 magic numbers | Generalize and add as a clarity box: bare numeric literals for dimensions/thresholds/timeouts → named constant with a why, or a design token if the project has them; same value repeated 2+ times is also a DRY finding. Drop MUI-specific fix examples. |

**Gate checklist block**: one box per kept rule above (§C1 guard clauses, §C2 defensive coercion, §C3 undeclared field access, §C4 redundant casts w/ grep receipt, §C5 side effects out of closures, §C6 comments, §C7 two-step mutations, §C8 magic spreads, §C9 anonymous structural types, §C10 fallback chains, §C11 unhappy path, §C12 thin wrappers, §C13 dense sub-expressions, §C14 circular imports (soft), §C15 ternaries w/ grep receipt, §C16 magic numbers). Each box self-contained with its own N/A condition, following the source file's box phrasing.

- [ ] **Step 2: Verify** — `wc -l` under 500 (if over, split `clarity-expressions.md` out per the topic-split rule and update SKILL.md's registry — but prefer tightening prose first); banned-token grep → 0; `## Gate checklist` present.

- [ ] **Step 3: Commit** — `git add -A && git commit -m "Add clarity gate reference"`

---

### Task 5: references/structure.md

**Files:**
- Create: `plugins/code-review/skills/review-code/references/structure.md`
- Read first: `$SRC/references/conventions.md`

**Interfaces:**
- Produces: gate name `structure` with boxes §S1–§S9.

- [ ] **Step 1: Read the source**, write the port. Keep/transform map:

| Source | Action |
|---|---|
| §1.1 separation of concerns (incl. "directory path is part of the contract") | Keep whole; genericize hook examples to "a data-reading unit that also bundles formatters"; drop the apps/client vs apps/portal placement subsection, replace with "place the extracted helper where its shape implies, following the target repo's existing layout — grep for where similar helpers live". |
| §2 code placement | Keep the generic core: one consumer → co-locate; multiple → nearest common ancestor judged by scope/coupling not raw count; YAGNI-gated promotion for view-local helpers; role-overrides-YAGNI for inherently-shared-layer code; audit trigger on folder moves; flatten single-file folders; no `export { default } from './X'` re-export barrels. Drop bulletproof-react layout diagram (moves to react.md), drop ET worked examples (rewrite the promotion + counter-example with placeholder names). |
| §5.2 dead wrappers | Keep whole — all seven shapes + legitimate-wrapper list + the fast test. Genericize the react-query examples (`refetch`, `mutate`) to generic `fn`/`callback` shapes, keeping one library-flavored example since the shape is universal. |
| §6 lookup objects over switch | Keep whole — the checklist, thunk-map rule, fallback rule, chained-ternary key derivation ban, "fixing one violation must not introduce another". Genericize the map example (already uses a generic-ish shape; rename PMS identifiers to `someProviderFormMap` with `ProviderKind.A/B`). |
| §6.1 mutate vs mutateAsync | MOVE to react.md. |
| §7 code placement (general) | Keep, generic. |
| §8 JSDoc on exported APIs | Keep whole; drop ET canonical paths ("grep the target repo to confirm it uses doc comments before flagging density; the restates-the-name flag applies everywhere"). |
| §11 + §11.1 named exports, inline export | Keep whole including the "flag on new files even when the codebase is overwhelmingly default-export" override and the framework-default exemption (Next.js `page.tsx`/`layout.tsx` and equivalents). Drop ET canonical paths. |
| §12 enums over literal unions | Keep the rule + naming shape + the five reasons + the "would the backend ever return this value?" test + what-not-to-flag. Placement rule becomes generic: "shared/serialized types live wherever the target repo keeps its model types — grep for sibling enums and match". Drop §12.1 entirely (et-types package plumbing). |

**Gate checklist block**: §S1 separation of concerns, §S2 co-location/promotion, §S3 flatten single-file folders + no re-export barrels, §S4 dead wrappers, §S5 lookup objects over switch/nested if, §S6 helpers placed by consumer count, §S7 JSDoc on exported APIs, §S8 named exports for new files (+ inline `export const` nitpick), §S9 string enums for serialized discriminators. Each with N/A condition.

- [ ] **Step 2: Verify** — `wc -l` under 500; banned-token grep → 0; `## Gate checklist` present.

- [ ] **Step 3: Commit** — `git add -A && git commit -m "Add structure gate reference"`

---

### Task 6: references/simplicity.md

**Files:**
- Create: `plugins/code-review/skills/review-code/references/simplicity.md`
- Read first: `$SRC/references/reuse.md`

**Interfaces:**
- Produces: gate name `simplicity` with boxes §P1–§P5.

- [ ] **Step 1: Read the source**, write the port. Keep/transform map:

| Source | Action |
|---|---|
| Standing DRY/YAGNI/KISS lens (from SKILL.md hard rule 2 + reuse gate DRY box) | Make this the file's opening section: the three questions, each a first-class smell with any-finding-fails weight. YAGNI list: unused params/props, single-caller abstraction built for a hypothetical second caller, config options nothing passes, dead branches. KISS list: lookup over nested conditionals, early return over nesting, existing util/stdlib over hand-roll. |
| §4 reuse over reinvention | Keep the method (two greps: symbol name + behavior keywords; suggest extending the near-miss rather than letting the copy stand). Drop the ET hook table entirely. |
| §4.3 assume-it-exists | Keep whole — the layered search (prop/slot on the component already in use → shared hook/util → component variant → data already available in state/store) and the "hook-reuse camouflages component-reuse" trap, genericized (`useXValues` + generic input hand-assembled when `<XPicker>` already packages them). Keep the helper-text-prop concrete instance with generic component names. |
| §4.4 safe numeric coercion | Keep the principle: flag `Number(x) || 0` (swallows a legit 0), `value ?? 0` on nullable-numeric, NaN-risky `Number(x)`. Fix: "use the project's safe-coercion helper if one exists (grep for it); otherwise a small named helper — and never wrap an already-guaranteed number (that's the clarity redundant-coercion flag)". |
| §4.6 repeated conversion → named helper | Keep whole (the Mode.ON/OFF example is already generic). Keep the severity calibration (2-site trivial = nitpick, both-directions or 3+ = suggestion). |
| §4.7 getIncludes, §4.8 tax math, §4.9 NoRecordsFound | DROP (design decision; repos encode equivalents in their own conventions file). |

**Gate checklist block**: §P1 DRY (no duplicated logic/value/literal/markup that should be a single source), §P2 YAGNI (no speculative/unused code), §P3 KISS (no materially simpler equivalent left on the table), §P4 assume-it-exists search exhausted before hand-rolling (incl. hook-reuse ≠ component-reuse), §P5 NaN-risky coercions and repeated conversions extracted. Each with N/A condition.

- [ ] **Step 2: Verify** — `wc -l` under 500; banned-token grep → 0; `## Gate checklist` present.

- [ ] **Step 3: Commit** — `git add -A && git commit -m "Add simplicity gate reference"`

---

### Task 7: references/datetime.md

**Files:**
- Create: `plugins/code-review/skills/review-code/references/datetime.md`
- Read first: `$SRC/references/datetime.md`

**Interfaces:**
- Produces: gate name `datetime` with boxes §D1–§D6.

- [ ] **Step 1: Read the source**, write the port. Keep/transform map:

| Source | Action |
|---|---|
| Preamble ("date/time is high risk; walk every box even for 2-line diffs") | Keep, minus ET-specific workaround inventory. |
| §4.1 no hand-rolled math | Keep whole: `split(':')` parsing, `new Date(str)` ad-hoc parsing, `getTime()` arithmetic, `+86_400_000` (wrong across DST — a calendar day is 23 or 25 hours), manual `padStart`, reimplementing `addDays`/`startOfDay`/`isBefore`/`isValid`. Fix: "use the project's date library (date-fns, dayjs, luxon, Temporal — grep the repo's imports to find which); if the project wraps it in its own hook/util, use that wrapper". Keep the `hoursBetween` canonical replacement example (already generic). Keep the "comparing two Date objects with </> is fine; comparing a Date to a string is the finding" exception. |
| §4.1a start+end range helper | Generalize to a soft check: "if the repo has a shared range-formatting helper (grep for it), hand-composing `${format(start)} - ${format(end)}` with its own same-day/all-day branching is a finding". |
| §4.2 full ISO with offset | Keep whole — both failure modes (truncating an instant to `yyyy-MM-dd`; sending local-time string with no offset), the "date-only is fine for genuinely date-only fields" carve-out, generic backend framing ("most backends coerce a bare date to midnight in *their* timezone"). |
| §4.2a truncation accounting | Keep whole — the three-purpose table (serialized value / round-trip key / comparison), the `format`+`parseISO` local↔local vs `new Date(str)` UTC demonstration, "the fix is usually to delete the round trip". |
| §4.2b `new Date()` in render/memo | Keep whole — frozen vs never-memoized, day-granularity timestamp key example. |
| §4.2c timezone/week-start as inputs | Generalize: "three clocks exist — the browser's, the user/org's configured zone, the server's; anything user-visible or query-bound must say which. Week boundaries, 12/24-hour format, and first-day-of-week come from user/app settings, never hardcoded and never inferred from locale alone. Server-rendered artifacts (emails, PDFs, background jobs) have no browser context — only stored settings are available there." Drop ET field names and landmine table. |
| §4.2d min/max over dates | Keep: use the date lib's `max`/`min`, not `new Date(Math.max(...dates.map(d => d.getTime())))`. |

**Gate checklist block**: §D1 no hand-rolled math, §D2 range helper reuse (soft), §D3 instants serialize as full ISO with offset, §D4 truncation accounted for (purpose named; parse matches format locality), §D5 `new Date()` in render/memo has a granularity-keyed dep or is genuinely per-render, §D6 timezone/week-start/hour-format are inputs from settings + min/max via the date lib. Each with N/A; whole gate N/A only when the diff contains no date/time handling.

- [ ] **Step 2: Verify** — `wc -l` under 500; banned-token grep → 0; `## Gate checklist` present.

- [ ] **Step 3: Commit** — `git add -A && git commit -m "Add datetime gate reference"`

---

### Task 8: references/react.md

**Files:**
- Create: `plugins/code-review/skills/review-code/references/react.md`
- Read first: `$SRC/references/component-structure.md`, `$SRC/references/data-fetching.md`, `$SRC/references/forms.md`, `$SRC/references/clarity.md` (§3, §7.2), `$SRC/references/conventions.md` (§2 layout diagram, §6.1)

**Interfaces:**
- Produces: gate name `react` with boxes §R1–§R14.

- [ ] **Step 1: Read the sources**, write the port in four sections:

**Section 1 — Project structure (bulletproof-react).** New content, cite https://github.com/alan2207/bulletproof-react/blob/master/docs/project-structure.md as the reference:
- Feature-based layout: `src/features/<feature>/{api,components,hooks,stores,types,utils}` — only the subfolders a feature needs.
- Shared code at app level: `src/{components,hooks,utils,types,stores,lib,config}` for cross-feature code.
- **No cross-feature imports** (`features/A` importing from `features/B`) — compose at the app/routes level instead.
- Unidirectional flow: shared → features → app; nothing in shared imports from features.
- Applicability guard: "enforce only when the target repo already follows (or is migrating to) a feature-based structure — grep for `src/features/`. In a legacy flat layout, flag only placements that make the layout *more* inconsistent; don't demand a bulletproof migration in a feature PR."
- Suggest an ESLint `import/no-restricted-paths` config as the durable fix when cross-feature imports are found (bulletproof-react's own recommendation).

**Section 2 — Components & JSX** (port component-structure.md whole, all rules are generic React; genericize MUI `Grid size` mentions to "a prop that only works under a specific ancestor container"):
- §R-keys (index keys for reorderable items, mixed filtered/unfiltered indices, redundant `indexOf` after `find`), §R-vestigial aliases, §R-prop drilling (2+ props derived from one context/hook the parent fetched; when-not-to-flag list), §R-repeated sibling JSX (3+ → map an array, stable key, Fragment), §R-hook-call purity (assign then derive), §R-owns-container (a component wraps its container-dependent children itself), §R-no-parent-assumptions (no root props/margins that only work under one specific ancestor), §R-conditional element assembly (no `let`-then-`if/else` building JSX; named local component with early returns; same-file until it grows).
- Plus from clarity.md: skip-via-ternary in map callbacks (block body + guard), side-effect-only components are a blocker (HOC > hook > component for gating; check the existing thing's actual responsibility before suggesting consolidation), `renderXxx()` inline render functions anti-pattern (keep the developerway.com link).

**Section 3 — Data fetching** (port data-fetching.md principles, drop ET type/hook names):
- Reads and writes live in separate hooks; no raw `fetch`/`axios`/`useMutation` calls inside components — they belong in the project's data-hook layer (grep how sibling features do it).
- §1.3 fetch ownership: the fetch lives with the consumer; duplicated ownership with different params = two requests; over-fetch for a derived boolean (full list to compute is-empty) is a finding.
- §9 invalidation last resort: mutation-result cache patching → surgical cache update → invalidate, in that order (react-query framing, since that's the dominant library; note "if the repo uses SWR/RTK-Query, map to its equivalents").
- §6.1 `mutate` + callbacks over `mutateAsync` + `await` when the resolved value only drives side effects; the three legitimate `mutateAsync` cases.

**Section 4 — Forms** (port forms.md generic subset):
- §3.1 the form is the single source of truth: no `useState` shadowing a value the form already holds; one-shot reads via `getValues`/submit data, reactive reads via `useWatch`-equivalent; the shadowing anti-example (already generic in source).
- Validation schemas: check the validation library's API (zod/yup/valibot-class libraries) before hand-rolling a `check`/`refine`/regex; coerce once in a transform, then validate; optionality via the library's own optional/nullable combinators.

**Gate checklist block**: §R1 bulletproof-react placement (with the applicability guard as its N/A condition), §R2 no cross-feature imports, §R3 keys/indices, §R4 vestigial aliases, §R5 prop drilling, §R6 repeated sibling JSX, §R7 hook-call purity, §R8 owns-container / no-parent-assumptions, §R9 conditional element assembly, §R10 no side-effect-only components + no skip-via-ternary maps + no renderXxx(), §R11 read/write hook separation + no raw calls in components, §R12 fetch ownership/over-fetch, §R13 invalidation last resort + mutate-over-mutateAsync, §R14 form single source of truth + validation-API check. Whole gate N/A only when the diff contains no React/TS UI code.

- [ ] **Step 2: Verify** — `wc -l` under 500 (this is the biggest file; if over, split `react-data.md` for sections 3–4 and register both in SKILL.md's table as the same `react` gate reading two files — prefer tightening first); banned-token grep → 0; `## Gate checklist` present.

- [ ] **Step 3: Commit** — `git add -A && git commit -m "Add react gate reference with bulletproof-react structure rules"`

---

### Task 9: references/i18n.md

**Files:**
- Create: `plugins/code-review/skills/review-code/references/i18n.md`
- Read first: `$SRC/references/translations.md`, `$SRC/references/checklist.md` (locale trigger section)

**Interfaces:**
- Produces: gate name `i18n` with boxes §I1–§I7, and the per-key audit table format that `verification.md` (Task 11) and SKILL.md hard rule 11 reference.

- [ ] **Step 1: Read the sources**, write the port. Keep/transform map:

| Source | Action |
|---|---|
| Per-key audit table (checklist.md) | Keep as the mandatory first output. Row shape: `<file>:L<n> — <key> = "<value>" \| namespace: <ok / move to shared>, plural: <icu / bare-noun → flag>, dupe: <none / clash with X>, naming: <matches value / mismatch>`. An aggregate grep ("N keys, all unique ✓") is an automatic incomplete review. |
| §10.1 dedup dual-grep | Keep: value grep + unscoped leaf-key grep across the whole source-locale tree; flat-key collision warning (namespaced key duplicating a top-level key); semantic-equivalent reasoning (re-phrasings like "Must be at least {min}" duplicating an existing "Min: {val}" evade value greps — judge by meaning); pre-existing duplicates in a touched file count. |
| §10.1 generic nouns → shared namespace | Generalize: "a generic noun/label/heading a sibling feature could reuse belongs in the project's shared/common locale file, not the feature file — even when not yet duplicated. Grep the repo to identify which file plays the common role." |
| §10.2 key matches value | Keep: camelCase match or established short-form suffix (grep the repo for which suffixes are established rather than hardcoding a list); no generic leaves (`title`/`description`/`text`/`label`) under a nested object. |
| §10.3 ICU plurals | Keep whole: every countable noun is an ICU plural even as a singular-only label (`{count, plural, =0 {Xs} =1 {X} other {# Xs}}`, call with `{ count: 1 }`); no separate `x`/`xs` pairs; no baked-plural compound keys; plain-string siblings are pre-existing violations, not precedent. Guard: "applies when the project uses an ICU-capable i18n library (next-intl, i18next with ICU, FormatJS) — check before flagging". |
| §10.4 never concatenate | Keep whole: word order varies across languages; no `t('edit') + ' ' + t('event')`; verb+noun values decompose into an action template + noun key if the project has (or should have) action templates; label + runtime data value is interpolation NOT concatenation (don't flag it, and don't let anyone invent `fooWithBar: "Foo: {bar}"` composite keys that re-bake an existing label); the both-sides-translatable test. |
| Machine-generated locales / only-edit-source | Generalize: "if the project machine-generates non-source locales (TMS-style pipelines, translation exports), edits to generated locale files are lost on deploy — flag them. Determine the source locale from the repo (usually `en`); if all locales are hand-maintained, this box is N/A." Use "TMS-style", never the ET vendor name, so the banned-token sweep stays strict. |

**Gate checklist block**: §I1 per-key audit table produced (absence = automatic FAIL), §I2 only the source locale edited (N/A if all locales hand-maintained), §I3 no duplicates (dual grep + semantic reasoning, per key, no exemptions), §I4 key name matches value, §I5 generic nouns in the shared namespace (independent of the dup grep result), §I6 ICU plurals for countable nouns, §I7 no concatenation / verb-template decomposition / interpolation carve-out. Whole gate N/A only when the diff touches no locale files.

- [ ] **Step 2: Verify** — `wc -l` under 500; banned-token grep → 0 (the ban list includes literal `common.json` / `actions.json` — phrase as "the shared locale file" / "the action-template file"); `## Gate checklist` present.

- [ ] **Step 3: Commit** — `git add -A && git commit -m "Add i18n gate reference"`

---

### Task 10: references/project-conventions.md

**Files:**
- Create: `plugins/code-review/skills/review-code/references/project-conventions.md`

**Interfaces:**
- Produces: gate name `project-conventions`; the `.claude/review-conventions.md` contract that README (Task 1) links to.

- [ ] **Step 1: Write the file** (new content, ~120 lines). Structure:

**Purpose:** this gate turns the target repo's own conventions into first-class review rules. The agent looks for `.claude/review-conventions.md` at the target repo root; if absent, the gate is `PASS (N/A: no .claude/review-conventions.md in target repo)`.

**Agent instructions:**
1. Read the ENTIRE conventions file.
2. Treat every rule in it exactly like a built-in gate rule: any single violation is a finding; severity per the built-in rubric unless the file specifies its own.
3. Before flagging, verify each cited convention is real in that repo (grep for 2–3 examples) — repo conventions files can go stale; a rule contradicted by the dominant current pattern gets flagged back to the user as "conventions file may be stale", not silently enforced or silently dropped.
4. If the conventions file has its own `## Gate checklist`, walk it box-by-box. If it's prose-only, derive one box per rule and say so in the evidence.
5. Rules in the conventions file that duplicate a built-in gate defer to the built-in (report under the built-in gate; don't double-report).

**Format guide for repo authors** (this section is what the README links to):
- One rule per section; state the principle first, examples second (labeled as illustrations).
- Express each rule as a checklist of independent failure modes with per-box N/A conditions.
- Include at least one real file path from the repo per rule as the canonical example.
- End the file with a `## Gate checklist` block (one box per rule).
- A minimal worked example (~20 lines) showing one rule in that shape, using placeholder names.

**Gate checklist block** for this gate itself:

```markdown
## Gate checklist

- [ ] §X1 The target repo's `.claude/review-conventions.md` was read in full and every rule in it was walked against the diff, one box per rule, with per-box evidence. (N/A: no `.claude/review-conventions.md` in the target repo — state that the file was looked for)
- [ ] §X2 Each convention cited in a finding was verified against the repo (2–3 existing examples greped and cited); stale rules were reported as possibly-stale rather than enforced or dropped. (N/A: no findings from this gate)
```

- [ ] **Step 2: Verify** — `wc -l` under 500; banned-token grep → 0; `## Gate checklist` present.

- [ ] **Step 3: Commit** — `git add -A && git commit -m "Add project-conventions gate reference"`

---

### Task 11: references/verification.md

**Files:**
- Create: `plugins/code-review/skills/review-code/references/verification.md`
- Read first: `$SRC/references/checklist.md`

**Interfaces:**
- Produces: gate name `verification` with the Always items + trigger groups keyed to the new gate names.

- [ ] **Step 1: Read the source**, write the port. Structure:

**Preamble:** the verification gate agent owns this file; walks the Always items plus every trigger group whose trigger the diff hits; FAIL if any applicable box is FAIL. Applies identically to peer review and self-review ("lint + types is not convention-clean").

**Always:**
- [ ] Read every non-trivial changed file at the actual head SHA (not subagent summaries).
- [ ] Every finding cites `file:line` and the short head SHA.
- [ ] Nothing was posted to GitHub — chat only.

**Trigger groups** (each a receipts checklist, generalized; drop ET-only triggers — locale table lives in i18n.md, cross-reference it):
- Diff touches locale files → the i18n per-key audit table is present in the output (cross-check with the i18n gate; both must have it).
- Diff adds/edits boolean logic → `grepped &&/||: N hits` receipt present with per-hit verdicts (naming gate's sweep).
- Diff adds/edits ternaries or casts → `grepped ternaries: N hits` / `grepped as-casts: N hits` receipts present (clarity gate's sweep).
- Diff adds/edits hooks/queries/mutations → consumers of each new hook named explicitly (`"useFoo has 1 consumer (Foo.tsx, same folder ✓)"`); `mutateAsync` grep receipt present.
- Diff adds/edits state → state at the lowest common consuming ancestor; order-dependent mutations carry a rationale comment.
- Dead wrappers (always) → for every wrapper kept, the review states what it adds (transformation / narrowing / default / side effect / re-export documentation); "matches an existing pattern" does not count.
- Diff adds a switch or if/else-if chain → the structure gate's §S5 boxes walked per chain.
- Diff adds exported APIs → doc-comment box walked.
- Diff adds a fixed-value discriminator → enum boxes walked; call sites in the same diff use the enum member.
- Self-review only → the project's lint + typecheck commands ran and pass (detect from package.json/Makefile; cite the command and result); the entire gate fan-out was walked on my own diff before saying "done"; if I committed/pushed/PR'd, the user explicitly said one of those words.

**How to use in output** section: end the review with a Checklist subsection naming each applicable group with a one-line receipt or "n/a, diff does not touch X"; an aggregated group means eyeballed-not-enumerated — unacceptable.

**Gate checklist block**: §V1 Always items, §V2 per-trigger receipt lines present for every applicable trigger group, §V3 no aggregate receipts where enumeration is required. N/A conditions per group.

- [ ] **Step 2: Verify** — `wc -l` under 500; banned-token grep → 0; `## Gate checklist` present.

- [ ] **Step 3: Commit** — `git add -A && git commit -m "Add verification gate reference"`

---

### Task 12: references/pr-comments.md

**Files:**
- Create: `plugins/code-review/skills/review-code/references/pr-comments.md`
- Read first: `$SRC/references/pr-comment-drafts.md`

**Interfaces:**
- Produces: the drafting/posting protocol SKILL.md's "Drafting and posting PR comments" section points to.

- [ ] **Step 1: Read the source**, write the port. Keep/transform map:

| Source | Action |
|---|---|
| Pre-draft self-prompt checklist | Keep whole (≤3 sentences, label on own line, no em dashes, no internal-rule-number citations, no praise openers, action-first, one topic per draft, soft framing / no command-form openers). |
| Conventional Comments format + label table + decorations | Keep whole (link to conventionalcomments.org). |
| Tone rules | Keep whole (they're the user's own preferences and travel with the plugin). Genericize the translation-finding example to placeholder keys. |
| Worked examples | Keep, genericizing identifiers. |
| Post-draft audit | Keep whole. |
| "Wait for an explicit, fresh signal" protocol | Keep whole — the does-NOT-count / does-count lists and the 5-step protocol verbatim (this is the load-bearing section). |
| Verify state after any write | Keep whole. |
| Posting via the GitHub API | Keep, parameterized: `gh api repos/{owner}/{repo}/pulls/<NUM>/reviews -X POST --input /tmp/review-<NUM>.json` with `{owner}/{repo}` resolved from the working directory (`gh repo view --json nameWithOwner -q .nameWithOwner`). Keep the JSON payload shape (commit_id, event COMMENT, single- and multi-line comment forms) and the PATCH-to-edit flow. |

- [ ] **Step 2: Verify** — `wc -l` under 500; banned-token grep → 0.

- [ ] **Step 3: Commit** — `git add -A && git commit -m "Add PR comment drafting and posting protocol"`

---

### Task 13: Whole-repo validation, publish, install test

**Files:**
- Modify: none expected (fixes only if validation fails)

- [ ] **Step 1: Structural validation**

```bash
cd /Users/sujeetkc/Desktop/kc-claude-kit
jq . .claude-plugin/marketplace.json > /dev/null && echo marketplace-ok
jq . plugins/code-review/.claude-plugin/plugin.json > /dev/null && echo plugin-ok
find plugins -name '*.md' -exec wc -l {} + | sort -n   # every file < 500
for f in naming clarity structure simplicity datetime react i18n project-conventions verification; do
  grep -L '## Gate checklist' "plugins/code-review/skills/review-code/references/$f.md"
done   # expect no output (every gate file has the block)
```

- [ ] **Step 2: Banned-token sweep**

```bash
grep -rniE 'eventtemple|Event Temple|NFE|et-types|@repo/|useDateTime|useRefetch|useQueryCacheUpdater|useProposalTranslations|safeNumber|getIncludes|DrawerFormProps|Crowdin|apps/client|apps/portal|valibot|Ransack' plugins/ README.md .claude-plugin/
```
Expected: 0 hits.

- [ ] **Step 3: Cross-reference check**

Verify SKILL.md's gate registry table lists exactly the 9 reference files that exist, with matching names; verify README's gate table matches; verify SKILL.md's iteration-notes routing table points only at existing files.

- [ ] **Step 4: Local install smoke test**

```bash
# Add the local directory as a marketplace and install from it
claude plugin marketplace add /Users/sujeetkc/Desktop/kc-claude-kit 2>/dev/null || echo "run inside Claude Code: /plugin marketplace add /Users/sujeetkc/Desktop/kc-claude-kit"
```
If the CLI subcommand isn't available, ask the user to run `/plugin marketplace add /Users/sujeetkc/Desktop/kc-claude-kit` then `/plugin install code-review@kc-claude-kit` in a Claude Code session and confirm the `code-review:review-code` skill appears in their skill list.

- [ ] **Step 5: ASK THE USER, then create the GitHub repo and push**

Show the user the final file tree and ask explicitly: "Ready to create public repo `kcsujeet/kc-claude-kit` and push?" Only on an explicit yes:

```bash
gh repo create kcsujeet/kc-claude-kit --public --source . --description "Sujeet's personal Claude Code toolkit — reusable plugins for any codebase" --push
```

- [ ] **Step 6: Remote install verification**

Ask the user to run in any Claude Code session:
```
/plugin marketplace add kcsujeet/kc-claude-kit
/plugin install code-review@kc-claude-kit
```
and confirm the skill triggers on "review my changes" in a side project. Suggest a smoke review on a small real diff there.
