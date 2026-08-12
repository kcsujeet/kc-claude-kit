# kc-claude-kit — `code-review` plugin design

**Date:** 2026-08-11
**Repo:** `kcsujeet/kc-claude-kit` (public, new)
**Origin:** Generalization of Event Temple's internal `review-NFE-code` skill. All Event Temple-specific rules removed; generic principles kept.

## Goal

A shareable Claude Code plugin marketplace under the `kcsujeet` GitHub profile, installable in any codebase:

```
/plugin marketplace add kcsujeet/kc-claude-kit
/plugin install code-review@kc-claude-kit
```

First (and initially only) plugin: `code-review`, containing skill `review-code` — a gate-based code review that fans out one subagent per rule file and aggregates per-box PASS/FAIL verdicts into a single PASSED/FAILED result.

## Repo layout

```
kc-claude-kit/
├── .claude-plugin/
│   └── marketplace.json            # marketplace: kc-claude-kit
├── README.md                       # what it is, install instructions
└── plugins/
    └── code-review/
        ├── .claude-plugin/
        │   └── plugin.json
        └── skills/
            └── review-code/
                ├── SKILL.md        # orchestrator
                └── references/
                    ├── naming.md
                    ├── clarity.md
                    ├── structure.md
                    ├── simplicity.md
                    ├── datetime.md
                    ├── react.md
                    ├── i18n.md
                    ├── project-conventions.md
                    ├── verification.md
                    └── pr-comments.md   # not a gate — drafting/posting protocol
```

## Architecture (ported from the ET skill)

- **Agent-per-gate fan-out.** The review is never a single inline pass. The orchestrator gathers the diff + head SHA, then dispatches one subagent per gate, in parallel. Each agent owns exactly one reference file, reads its `## Gate checklist`, and returns a structured per-box verdict with evidence.
- **Every gate, every round.** Conditional gates are still dispatched; the *agent* declares `PASS (N/A)` with a reason. The orchestrator never assumes inapplicability. Re-reviews re-run all gates from scratch against the new head SHA.
- **Any finding fails its gate.** A gate is PASS only when nothing was found. Severity (🔴/🟠/🟡) calibrates communication weight, never whether a finding is reported. A single 🟡 fails the review.
- **Surface everything.** The reviewer detects and reports; "intentional / defensible / matches the neighbors / low-value" are descriptions for the human, never reasons to withhold.
- **Verify before flagging.** Conventions are confirmed against the target codebase by grep (2–3 existing examples) before being cited. Accuracy check, not a suppression license.
- **Grep-don't-eyeball.** Greppable constructs (ternaries, `as` casts, `&&`/`||` chains, locale keys) are enumerated mechanically over added lines before reading for meaning; every hit gets a per-line verdict; `0 hits` is stated explicitly. Silence is indistinguishable from never having looked.
- **Precedent is a yellow flag.** Matching nearby code is never a pass; a violation extended is the diff's own violation.
- **Never posts to GitHub unprompted.** Output stays in chat. Posting requires the drafting protocol in `references/pr-comments.md` and a fresh, standalone post signal.
- **Gate-status table leads the report**, then deduped findings (one line each, `file:line` first), then the explicit PASSED/FAILED verdict.

## Gate registry

| Gate | Dispatch | Contents (generalized from ET source) |
|---|---|---|
| **naming** | always | Role-not-type names (`data`/`result`/`temp` in business logic); honest names (read as a sentence: subject elision, context-as-subject, stale-after-refactor, familiar-shaped names hiding different behavior); boolean-chain extraction — operands too, not just the outer name; repeated predicate → named helper/type guard; mechanical `&&`/`||` grep sweep with per-hit verdicts. |
| **clarity** | always | Ternary checklist (nested/long/multi-line/non-trivial-branch — value ternaries too); dense guard clauses; defensive coercion on typed values; redundant `as T`; comment rules (earn their place, density is itself a finding); two-step mutations without ordering rationale; magic spreads; inline anonymous structural types; 3+-operand fallback chains; unhappy-path tangled into happy path; thin-wrapper over-extraction (the symmetric smell); dense inlined sub-expressions; magic numbers → named constant or token; ternary/cast grep sweep. |
| **structure** | always | Separation of concerns (one observable responsibility; directory path is part of the contract — `hooks/` promises hooks, `utils/` promises pure functions); co-location and nearest-common-ancestor promotion (YAGNI-gated for view-local helpers, role-driven for shared-layer code); flatten single-file folders; no re-export barrels; dead wrappers (all shapes: single-item array wrap-then-spread, async-await passthrough, destructure-and-reconstruct, one-use alias, identity transform, producer/consumer double-derivation, Promise-around-Promise); lookup objects over `switch`/nested `if` (thunk maps for per-branch interpolation; chained-ternary key derivation banned); named exports for new files (inline `export const`, not trailing blocks); JSDoc on exported APIs; string enums over literal unions for backend-serialized discriminators (would-the-backend-return-this test). |
| **simplicity** | always | DRY/YAGNI/KISS as a standing lens with any-finding-fails weight; assume-it-exists (check props/slots → shared hooks/utils → component variants → existing data before hand-rolling; hook-reuse doesn't excuse component-reinvention); NaN-risky coercion (`Number(x) \|\| 0` swallows legit 0 — use the project's safe-coercion helper if one exists); non-trivial conversion repeated at 2+ sites → one named helper (esp. both directions of one encoding). |
| **datetime** | conditional: diff touches date/time logic | No hand-rolled date math (`split(':')`, `getTime()` arithmetic, `+86_400_000` breaks on DST, manual `padStart`) — use the project's date library; serialize instants as full ISO 8601 with offset (date-only is fine for genuinely date-only fields); truncation accounting (serialized value / round-trip key / comparison — `format`+`parseISO` is local↔local, `new Date(str)` reads UTC and shifts a day west of UTC); `new Date()` in render/memo (frozen vs never-memoized; use day-granularity timestamp keys); timezone, week-start, and 12/24-hour are **inputs** from user/app settings, never constants; earliest/latest via the date lib's `max`/`min`. |
| **react** | conditional: diff has React/TS code | **Bulletproof-react project structure** ([reference](https://github.com/alan2207/bulletproof-react/blob/master/docs/project-structure.md)): feature-based layout (`features/<feature>/{api,components,hooks,stores,types,utils}` — only the subfolders a feature needs), shared code at app level (`components/`, `hooks/`, `utils/`, `types/`, `stores/`), **no cross-feature imports** (compose at the app level), unidirectional flow (shared → features → app). Plus: React keys (no index for reorderable items, no mixed filtered/unfiltered indices); prop drilling when a child could read the same hook/context; repeated sibling JSX (3+ structurally identical blocks → map an array with stable keys); hook-call purity (assign the hook result, derive on the next line); a component owns its own container and never assumes its parent's context (no root `size`/`flexGrow`/self-margins that only work under one ancestor); conditional element assembly → named local component with early returns; no side-effect-only components (`useEffect` + `return null` — use a hook or HOC); no skip-via-ternary in map callbacks; no `renderXxx()` inline render functions; data-fetching principles (reads and writes in separate hooks, no raw fetch/mutation calls in components, cache-patch before invalidate, `mutate`+callbacks over `mutateAsync`+`await` when the value only drives side effects, fetch lives with its consumer — no over-fetch for a derived boolean); forms: the form is the single source of truth (no shadowing `useState`), check the validation library's API before hand-rolling a check. |
| **i18n** | conditional: diff touches locale/translation files | Per-key audit table mandatory (one row per new key), never an aggregate grep; dedup — value grep + unscoped leaf-key grep across the whole locale tree, plus semantic-equivalent reasoning (re-phrasings evade value greps); ICU plurals for every countable noun (even singular-only labels; no baked-plural keys; no separate `x`/`xs` pairs); never concatenate translations (word order varies by language) — verb+noun values decompose into an action template + noun key; label + runtime data value is interpolation, not concatenation (don't invent `fooWithBar` composite keys); key name matches value; generic nouns belong in the common/shared namespace, not feature files; if the project machine-generates non-source locales, edits to them are flagged as lost-on-deploy. |
| **project-conventions** | conditional: target repo has `.claude/review-conventions.md` | The agent reads the repo's own conventions file and walks the diff against every rule in it, same per-box contract. This is the extension point that replaces all the dropped ET-specific gates — a repo encodes its own `useXResource` split, UI-library rules, domain-math helpers, etc. there. The reference file documents the expected format (checklist of failure modes, one canonical example path per rule) so repos write gate-consumable conventions. |
| **verification** | always | Receipts checklist: read every non-trivial changed file at head SHA; every finding cites `file:line` + short SHA; nothing posted to GitHub; per-trigger receipt lines (grep counts, per-key table when i18n applies); self-review variant (when the reviewer authored the diff: lint/types green is not gate-clean; explicit commit/push authorization check). |

`references/pr-comments.md` (not a gate): Conventional Comments format (label on its own line), label table, tone rules (soft framing, action-first, ≤3 sentences, no em dashes, no praise openers, no internal-rule-number citations in posted comments), pre-draft self-prompt + post-draft audit, the explicit-fresh-post-signal protocol, verify-repo-state-after-any-write.

## What was dropped from the ET skill

`getIncludes` registry, tax math (`@repo/utils/tax`), `NoRecordsFound`, MUI Grid-over-Stack layout gate, `safeNumber` (kept as principle, not helper name), `useDateTime`/`useRefetch`/`useQueryCacheUpdater` (kept as principles), `useXForm`/`DrawerFormProps` drawer-ref pattern, `QueryParams<T>`, et-types enum placement, Crowdin specifics, Rails backend triggers, all `apps/client/...` canonical paths, hardcoded `eventtemple/eventtemple-frontend` repo references. Repos that need equivalents encode them in their own `.claude/review-conventions.md`.

## Genericization rules for writing the reference files

- Code examples use placeholder names (`flagA`, `someStatus`, `useXs`) and generic shapes, never ET identifiers.
- No canonical ET file paths. Where the ET skill said "canonical: apps/client/...", the generic version says "grep the target repo for 2–3 examples before citing the convention".
- Repo/PR commands are parameterized: `gh pr diff <num>` (repo inferred from the working directory), `git diff <default-branch>...HEAD` with the default branch detected, never hardcoded.
- Rules stay expressed as checklists of independent failure modes, each box self-contained with its own N/A condition (the gate-agent contract depends on this).
- Every reference file carries a `## Gate checklist` block; every `.md` stays under 500 lines.

## Output format

Same as the ET skill: gate-status table first (all gates, every round), then findings grouped by gate (one line each: severity emoji, `file:line`, issue, fix), then explicit `✅ PASSED` / `❌ FAILED (<n> gate(s) failing)` verdict. Terse; no explanation paragraphs.

## Skill description / triggering

The skill description triggers on generic review signals ("review this PR", "review my changes", "is this good to merge", a PR URL, a branch name) — without the ET-repo-identity clause. It does not claim priority over other skills; in repos with a more specific review skill (like eventtemple-frontend), that skill's own description claims priority.

## Delivery

1. Build the repo locally at `~/Desktop/kc-claude-kit`.
2. Create public GitHub repo `kcsujeet/kc-claude-kit`, push (with explicit user approval before any commit/push).
3. Verify installability: `/plugin marketplace add kcsujeet/kc-claude-kit` → `/plugin install code-review@kc-claude-kit`.
4. Smoke-test the skill on a real diff in a side project.

## Non-goals

- No hooks, agents, or commands in v1 — skill only.
- No `--quick` inline mode (decided against; fan-out always).
- No stack profiles beyond the react gate (config file covers per-repo needs).
- Not a bug scanner or security reviewer; conventions + clarity only, same as the source skill.
