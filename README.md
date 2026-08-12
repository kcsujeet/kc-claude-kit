# kc-claude-kit

Sujeet's personal Claude Code toolkit: reusable plugins for any codebase.

## Install

Add the marketplace:

```
/plugin marketplace add kcsujeet/kc-claude-kit
```

Install the code-review plugin:

```
/plugin install code-review@kc-claude-kit
```

The skill triggers automatically on requests like "review this PR" or "review my changes" (skill id `code-review:review-code`).

## What's inside

| Plugin | Skill | Description |
|--------|-------|-------------|
| `code-review` | `review-code` | Gate-based code review with one subagent per rule file and per-box PASS/FAIL verdicts |

## How the review works

The code-review plugin dispatches one subagent per gate, in parallel. Each agent owns exactly one reference file, reads its gate checklist, and returns a structured per-box verdict with evidence. Any finding fails its gate. The orchestrator aggregates all gate results into a single PASSED/FAILED verdict and leads the report with a gate-status table showing which gates passed or failed.

## Per-repo extension

If the target repository has a `.claude/review-conventions.md` file, it becomes an extra gate. This file lets you encode project-specific code review rules without modifying the plugin. For documentation on the expected format and examples, see `plugins/code-review/skills/review-code/references/project-conventions.md`.

## Gate registry

| Gate | Dispatch | Contents |
|---|---|---|
| **naming** | always | Role-not-type names (`data`/`result`/`temp` in business logic); honest names (read as a sentence: subject elision, context-as-subject, stale-after-refactor, familiar-shaped names hiding different behavior); boolean-chain extraction (operands too, not just the outer name); repeated predicate → named helper/type guard; mechanical `&&`/`\|\|` grep sweep with per-hit verdicts. |
| **clarity** | always | Ternary checklist (nested/long/multi-line/non-trivial-branch; value ternaries too); dense guard clauses; defensive coercion on typed values; redundant `as T`; comment rules (earn their place, density is itself a finding); two-step mutations without ordering rationale; magic spreads; inline anonymous structural types; 3+-operand fallback chains; unhappy-path tangled into happy path; thin-wrapper over-extraction (the symmetric smell); dense inlined sub-expressions; magic numbers → named constant or token; ternary/cast grep sweep. |
| **structure** | always | Separation of concerns (one observable responsibility; directory path is part of the contract; `hooks/` promises hooks, `utils/` promises pure functions); co-location and nearest-common-ancestor promotion (YAGNI-gated for view-local helpers, role-driven for shared-layer code); flatten single-file folders; no re-export barrels; dead wrappers (all shapes: single-item array wrap-then-spread, async-await passthrough, destructure-and-reconstruct, one-use alias, identity transform, producer/consumer double-derivation, Promise-around-Promise); lookup objects over `switch`/nested `if` (thunk maps for per-branch interpolation; chained-ternary key derivation banned); named exports for new files (inline `export const`, not trailing blocks); JSDoc on exported APIs; string enums over literal unions for backend-serialized discriminators (would-the-backend-return-this test). |
| **simplicity** | always | DRY/YAGNI/KISS as a standing lens with any-finding-fails weight; assume-it-exists (check props/slots → shared hooks/utils → component variants → existing data before hand-rolling; hook-reuse doesn't excuse component-reinvention); NaN-risky coercion (`Number(x) \|\| 0` swallows legit 0; use the project's safe-coercion helper if one exists); non-trivial conversion repeated at 2+ sites → one named helper (esp. both directions of one encoding). |
| **datetime** | conditional: diff touches date/time logic | No hand-rolled date math (`split(':')`, `getTime()` arithmetic, `+86_400_000` breaks on DST, manual `padStart`); use the project's date library; serialize instants as full ISO 8601 with offset (date-only is fine for genuinely date-only fields); truncation accounting (serialized value / round-trip key / comparison; `format`+`parseISO` is local↔local, `new Date(str)` reads UTC and shifts a day west of UTC); `new Date()` in render/memo (frozen vs never-memoized; use day-granularity timestamp keys); timezone, week-start, and 12/24-hour are **inputs** from user/app settings, never constants; earliest/latest via the date lib's `max`/`min`. |
| **react** | conditional: diff has React/TS code | **Bulletproof-react project structure** ([reference](https://github.com/alan2207/bulletproof-react/blob/master/docs/project-structure.md)): feature-based layout (`features/<feature>/{api,components,hooks,stores,types,utils}`; only the subfolders a feature needs), shared code at app level (`components/`, `hooks/`, `utils/`, `types/`, `stores/`), **no cross-feature imports** (compose at the app level), unidirectional flow (shared → features → app). Plus: React keys (no index for reorderable items, no mixed filtered/unfiltered indices); prop drilling when a child could read the same hook/context; repeated sibling JSX (3+ structurally identical blocks → map an array with stable keys); hook-call purity (assign the hook result, derive on the next line); a component owns its own container and never assumes its parent's context (no root `size`/`flexGrow`/self-margins that only work under one ancestor); conditional element assembly → named local component with early returns; no side-effect-only components (`useEffect` + `return null`; use a hook or HOC); no skip-via-ternary in map callbacks; no `renderXxx()` inline render functions; data-fetching principles (reads and writes in separate hooks, no raw fetch/mutation calls in components, cache-patch before invalidate, `mutate`+callbacks over `mutateAsync`+`await` when the value only drives side effects, fetch lives with its consumer; no over-fetch for a derived boolean); forms: the form is the single source of truth (no shadowing `useState`), check the validation library's API before hand-rolling a check. |
| **i18n** | conditional: diff touches locale/translation files | Per-key audit table mandatory (one row per new key), never an aggregate grep; dedup (value grep + unscoped leaf-key grep across the whole locale tree, plus semantic-equivalent reasoning, since re-phrasings evade value greps); ICU plurals for every countable noun (even singular-only labels; no baked-plural keys; no separate `x`/`xs` pairs); never concatenate translations (word order varies by language); verb+noun values decompose into an action template + noun key; label + runtime data value is interpolation, not concatenation (don't invent `fooWithBar` composite keys); key name matches value; generic nouns belong in the common/shared namespace, not feature files; if the project machine-generates non-source locales, edits to them are flagged as lost-on-deploy. |
| **project-conventions** | conditional: target repo has `.claude/review-conventions.md` | The agent reads the repo's own conventions file and walks the diff against every rule in it, same per-box contract. This is the extension point for company- or project-specific rules: a repo encodes its own data-layer patterns, UI-library rules, domain-math helpers, etc. there. The reference file documents the expected format (checklist of failure modes, one canonical example path per rule) so repos write gate-consumable conventions. |
| **verification** | always | Receipts checklist: read every non-trivial changed file at head SHA; every finding cites `file:line` + short SHA; nothing posted to GitHub; per-trigger receipt lines (grep counts, per-key table when i18n applies); self-review variant (when the reviewer authored the diff: lint/types green is not gate-clean; explicit commit/push authorization check). |
