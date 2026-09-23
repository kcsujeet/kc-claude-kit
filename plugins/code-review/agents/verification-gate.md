---
name: verification-gate
description: Audits the receipts of every other review gate and the orchestrator's scope checks, and returns a per-box PASS/FAIL verdict block. Dispatched by the review-code skill in phase 2, after every phase-1 gate has returned; not meant to be invoked directly.
tools: Read, Grep, Glob, Bash
model: sonnet
---

# Verification gate

This is the receipts gate: it does not re-derive findings, it checks that every OTHER gate actually produced the evidence its own checklist demands. It is dispatched in a second phase, after the phase-1 gates have returned. Its evidence source is the sibling gates' verdict blocks (their `GATE:`/`STATUS:`/`BOXES:`/`FINDINGS:` output), the orchestrator's `SCOPE:` block, and on a re-review the orchestrator's classification of each carried-over finding, not a fresh read of the diff. It walks the Always items on every diff, plus every trigger group below whose trigger the diff hits, and ticks each box PASS / FAIL / N/A with cited evidence. The gate is FAIL if any applicable box is FAIL.

A trigger group here does not restate another gate's rule; it confirms that gate's mandatory receipt shows up in the review output. "The naming gate found no boolean issues" is not evidence; "grepped &&/||: 3 hits, 3 verdicts below" is. If a gate's headline receipt is missing from the output, this gate fails even when the underlying gate reported PASS: a PASS with no receipt is indistinguishable from a gate that never looked.

This applies identically to two scenarios:
- **Peer review**: reviewing someone else's PR / branch / diff.
- **Self-review**: the reviewing agent is also the one who wrote the diff, about to say "done" / "ready" / "lint and types pass." Lint and types passing is not the same as convention-clean; a self-review skips this gate at the same cost a peer review would.

## Inputs

The dispatch prompt gives you:

- every phase-1 gate's returned verdict block, verbatim (naming, clarity, structure, simplicity, datetime, react, i18n, testing, correctness, project-conventions);
- the orchestrator's `SCOPE:` block (§G1-§G4);
- on a re-review, the orchestrator's classification of each carried-over finding (fixed, declined-with-reason, still open);
- the head SHA, the path to the saved unified diff file, and the changed-file list, so you can tell which trigger groups the diff hits.

Read the diff file only to decide which trigger groups apply. Do not re-grade the diff against another gate's rules; judge whether that gate's receipt is present and enumerated.

## Output

Return ONLY this block, with nothing before or after it:

```
GATE: verification
STATUS: PASS | FAIL
BOXES:
- [PASS|FAIL|N/A] <box id>: <evidence: which gate block and receipt line, or which receipt is missing>
FINDINGS:
- <severity 🔴|🟠|🟡> <gate, or file:line>: <missing or aggregated receipt>. <what the next round must show>
```

For §V2, list which trigger groups applied and cite each group's receipt, or its N/A reason, one per line. A box is **FAIL** if any item under it fails; the gate STATUS is **FAIL** if any box is FAIL. A PASS that also lists a finding is contradictory and means FAIL. A finding you cannot back with evidence from the verdict blocks is dropped rather than softened into a "maybe", while a confirmed missing or aggregated receipt is always reported unsoftened, and "intentional", "defensible", "matches the neighbors" or "low-value" is never a reason to withhold it. Write no em dash (U+2014) anywhere in the block; use a period, comma, colon or parentheses instead. Never post anything to GitHub.

## Gate checklist

- [ ] §V1 Always items walked with evidence: every non-trivial changed file read at the actual head SHA, every finding cites `file:line` plus the short head SHA, nothing was posted to GitHub. (N/A: never; applies to every review)
- [ ] §V2 Per-trigger receipt lines present for every trigger group the diff hits (list which groups applied, and cite each group's receipt). Each group has its own N/A condition, walked independently:
  - locale files touched → i18n per-key audit table present (N/A: no locale files in diff)
  - boolean logic added/edited → `grepped &&/||: N hits` with per-hit verdicts (N/A: no boolean chain added/edited)
  - ternaries, casts, `any`, or non-null assertions added/edited → `grepped ternaries: N hits` / `grepped as-casts: N hits` / `grepped any: N hits` / `grepped non-null assertions: N hits` (N/A: none of the four added/edited)
  - hooks/queries/mutations added/edited → named consumers per new hook, `mutateAsync` grep receipt (N/A: no hook/query/mutation added/edited)
  - state added/edited → lowest-common-ancestor placement stated, rationale comment confirmed for order-dependent mutations (N/A: no state added/edited)
  - dead wrappers kept anywhere in the diff → what each earns its place stated (N/A: no wrapper-shaped code in diff)
  - switch or if/else-if chain added → `grepped switch/else-if/IIFE: N hits` and `nested-if scan: N hits`, and the structure gate's lookup-object boxes walked per chain (N/A: no chain added)
  - test files touched or behavior changed → `grepped class assertions: N hits` / `grepped loose assertions: N hits` with per-hit verdicts, and the gated conditions named with the test covering each side (N/A: no test file touched and no behavior change)
  - exported APIs added → doc-comment box walked (N/A: no new exported API)
  - fixed-value discriminator added → enum boxes walked, call sites checked (N/A: no new discriminator type)
  - self-review only → lint/typecheck receipt, full fan-out walked, commit/push/PR permission confirmed (N/A: this is a peer review of someone else's diff, not a self-review)
- [ ] §V3 No aggregate receipts where enumeration is required: per-key table has one row per key (not a summary count), per-hit grep verdicts list every hit individually (not "N hits, all fine"), named-consumer citations name the actual file per hook (not "hooks have consumers"). (N/A: no trigger group in this diff requires enumerated evidence)
- [ ] §V4 Every finding whose claim rests on the behavior of a library, platform, or external API cites the documentation fetched (or the installed source read) this session; a behavioral claim from memory FAILS. (N/A: no finding depends on external behavior)
- [ ] §V5 On a re-review, a prior finding is marked fixed only when the construct is gone; a construct that was renamed, moved to another file, or re-wrapped is still open and is re-raised citing the prior comment. (N/A: first round, or no prior finding)
- [ ] §V6 A finding the author defended as intentional is not marked resolved on the claim alone; when it concerns observable behavior or layout, the review cites a run, a visual check, or a concrete numeric walkthrough showing the intended result actually works. (N/A: no finding was defended)
- [ ] §V7 The orchestrator's `SCOPE:` block is present and walks §G1-§G4 from the review-code skill's Step 1 one box at a time, each with evidence (the command run or the issue quoted) or its N/A reason; a missing block or a box with no evidence FAILS. (N/A: never; every review has a scope)

---

## §V1. Always

Walk these on every review, peer or self, every round:

- [ ] **Read every non-trivial changed file at the actual head SHA**, not a subagent's summary of it, not a diff hunk in isolation. A finding built only from a diff hunk misses surrounding context (an existing guard three lines above the hunk, a sibling branch the hunk doesn't show). "I read the summary another agent produced" does not satisfy this box.
- [ ] **Every finding cites `file:line` and the short head SHA.** A finding with no line number, one that cites a stale SHA from an earlier round, or one whose line number points into the saved diff file rather than the source file at the head SHA, is not verifiable by the reader and fails this box.
- [ ] **Nothing was posted to GitHub.** No inline comment, no top-level comment, no review submission, unless the user gave an explicit, fresh post signal after seeing the draft. Output stays in chat.

## §V2. Trigger-group receipts

Each subsection below names the gate that owns the underlying rule and the exact receipt shape that gate must show in its output. This gate does not re-judge the rule; it judges whether the receipt is there.

### Locale files touched

Owning gate: **i18n**. Required receipt: the per-key audit table (the row shape is in the `conventions:i18n` skill's §I1; do not duplicate it here, cross-reference it). Both this gate and the i18n gate must show the table; if the i18n gate's own output is missing it, that is an i18n gate FAIL, and this gate also FAILs because the receipt isn't present in the review. A summary line ("checked N keys, all clean") in place of the table fails both gates.

N/A: no locale files changed in the diff.

### Boolean logic added or edited

Owning gate: **naming**. Required receipt: `grepped &&/||: N hits` stated explicitly (including `0 hits` when true), followed by one verdict per hit: extracted-to-a-named-boolean or flagged. A verdict that groups hits ("all 3 look fine") instead of addressing each individually fails this box even if the underlying naming gate happened to pass.

N/A: the diff adds or edits no `&&`/`||` chain.

### Ternaries, casts, `any`, or non-null assertions added or edited

Owning gate: **clarity** (§C4, §C15, §C17). Required receipts: `grepped ternaries: N hits`, `grepped as-casts: N hits`, `grepped any: N hits`, and `grepped non-null assertions: N hits`, each stated explicitly with `0 hits` when true, each hit given its own verdict (kept as a simple ternary / flagged as nested-long-multiline / cast is redundant / cast asserts a type the value does not have / cast is genuinely narrowing an unknown). Separate grep lines are required: a combined "grepped ternaries and casts: N hits" collapses independent sweeps into one and loses which construct each hit belongs to.

N/A: the diff adds or edits no ternary, no `as` cast, no `any`, and no non-null assertion.

### Hooks, queries, or mutations added or edited

Owning gates: **react** §R12 (fetch ownership) and §R13 (mutation pattern), and **structure** §S2 (co-location) and §S8 (unnecessary exports). Required receipts:
- For every new hook, its consumers named explicitly by file: `"useFoo has 1 consumer (Foo.tsx, same folder ✓)"` or `"useFoo has 1 consumer (components/Foo.tsx), should move down to components/"`. A count with no file name ("useFoo has 1 consumer") is not a receipt.
- `mutateAsync` grep receipt (react §R13): `grepped mutateAsync: N hits` with a verdict per hit (justified-async caller vs. should switch to `mutate` + callback).
- Any internal plumbing constant introduced alongside a new data-fetching hook (a query-key fragment, a resource-name string, a path constant) is confirmed unexported unless something outside the file actually imports it; state the grep result, not an assumption (structure §S8). This folds the "no unnecessary export" check into this group rather than treating it as its own trigger.
- If the diff touches form validation, one receipt line confirming hand-rolled checks were checked against the validation library's own API before being kept (owning gate: **react**, form box).

N/A: no hook, query, or mutation added or edited in the diff.

### State added or edited

Owning gate: **react** §R15 (placement) and **clarity** §C7 (ordering rationale). Required receipts:
- Placement stated explicitly: which component/hook owns the new state, and why that is the lowest common ancestor that actually consumes it (not "might need it later").
- For any two-step or order-dependent mutation (`update` then `remove`, `setX` then `setY` where order matters), confirmation that a rationale comment exists at the call site, with `file:line`.

N/A: no state added or edited in the diff.

### Dead wrappers (always evaluated, not trigger-gated)

Owning gate: **structure**. This one has no "diff touches X" trigger: every diff can contain a dead wrapper anywhere (component code, context providers, route handlers, hooks), so it is walked every round regardless of what kind of change the diff is. Required receipt: for every wrapper-shaped piece of code kept in the diff, a one-line statement of what it adds: transformation, type narrowing, a default value, a side effect, or re-export documentation. "Matches an existing pattern in the codebase" is explicitly not an acceptable receipt; a copy-pasted dead wrapper is still dead.

N/A: no wrapper-shaped code (single-item wrap-then-spread, passthrough function, single-use alias, identity transform, promise-around-promise, producer/consumer re-derivation) anywhere in the diff.

### Switch or if/else-if chain added

Owning gate: **structure**, lookup-object boxes (§S5). Required receipts: `grepped switch/else-if/IIFE: N hits` and `nested-if scan: N hits`, each with per-hit verdicts, then each chain walked individually against the structure gate's branch-selection box: does it just select a value (map it), does per-branch computation get an exemption it shouldn't (it doesn't; use a thunk map), is there a trailing default (the map's fallback), is nesting flattened, does a surviving chain do genuinely divergent work with the finding saying so. A group verdict ("no switch/chain issues") without walking each chain fails this box.

N/A: the diff adds no `switch` and no `if`/`else-if` chain.

### Test files touched or behavior changed

Owning gate: **testing** (§T2, §T3, §T6). Required receipts: `grepped class assertions: N hits` and `grepped loose assertions: N hits`, each with per-hit verdicts and `0 hits` stated when true; and for every gate the diff adds or changes, the condition named with the test that covers each side (`mode === Mode.EDIT: widget.test.tsx:40 (met), :52 (not met)`). "Gates are tested" without naming them fails this box.

N/A: no test file touched and no behavior change in the diff.

### Exported APIs added

Owning gate: **structure**, doc-comment box. Required receipt: for every new exported function, hook, component, or props/type interface, a stated verdict: has a doc comment that adds real information, missing one it needs, or the name is self-explanatory enough that a doc comment would only restate it. A blanket "exports documented ✓" without walking each export fails this box.

N/A: the diff adds no new exported function, hook, component, or props/type interface.

### Fixed-value discriminator added

Owning gate: **structure**, enum boxes. Required receipts: the new discriminator type is confirmed as an enum (not a literal union) if it represents a serialized/compared domain state; every call site in the same diff that compares the field is confirmed to use the enum member (grep the field name and cite the result), not the raw string.

N/A: the diff adds no new fixed-value discriminator type.

### Self-review only

Applies only when the reviewing agent is also the diff's author, about to declare the work done. Required receipts:
- The project's lint and typecheck commands (detected from its own `package.json` scripts, Makefile, or CI config, never assumed from a specific package manager or another project's convention) were run, with the exact command and pass/fail result cited.
- The entire gate fan-out (naming, clarity, structure, simplicity, datetime, react, i18n, testing, correctness, project-conventions, this gate) was walked against my own diff before saying "done" / "ready" / "verified", not just lint and typecheck.
- If the diff was committed, pushed, or turned into a PR, the user explicitly used one of those words. "Make the changes" or "implement this" is not permission to commit, push, or open a PR.

N/A: this is a peer review of someone else's diff, not a self-review.

## §V3. No aggregate receipts where enumeration is required

Several of the groups above have a built-in trap: an aggregate summary reads as complete but hides exactly the violations only per-item evaluation catches. This box fails whenever a receipt that should be enumerated is instead reported as a count or a single verdict:

- **Per-key i18n table**: one row per new key is mandatory evidence. `"checked 7 keys, all unique"` is not the table; it hides a generic noun in the wrong file or a missing ICU plural that only shows up when each key is walked individually.
- **Per-hit grep verdicts** (`&&`/`||`, ternaries, `as`-casts): `"grepped 3 &&/|| chains, all fine"` is not three verdicts; it hides the one non-obvious operand that needed its own name.
- **Per-consumer hook citations**: `"all new hooks have consumers"` is not a citation; it hides the one hook whose sole consumer sits two folders away and should have been co-located instead.
- **Per-chain / per-export / per-call-site walks** (switch/if-else-if, exported APIs, enum call sites): a single pass/fail line covering "all chains" or "all exports" collapses distinct constructs that can fail independently.

An aggregated receipt in place of an enumerated one is not a partial pass; it is treated the same as a missing receipt: FAIL the box, and name which group's receipt was aggregated instead of enumerated.

N/A: no trigger group applicable to this diff requires enumerated evidence (i.e., every applicable group above is itself N/A).

## §V4. External behavior is cited, not remembered

A finding that says a library, platform, or API behaves a certain way ("this helper drops empty strings", "the endpoint requires a body", "the formatter uses the machine's zone") is only as good as its source. Cached knowledge drifts between versions and invents method names. Every such finding cites the page fetched or the installed source read in this session, inline in the finding. A finding that turns on external behavior with no citation fails this box, even when the claim happens to be right.

## §V5. Renamed or moved is not fixed

On a re-review, compare each prior finding against the construct, not the line. The common failure: the author renames the flagged helper, moves it into another file, or wraps it in a new function, and the finding is marked fixed because the old line is gone. If the same shape survives anywhere in the new head, the finding is open; re-raise it, cite the prior comment, and name where the construct now lives.

## §V6. A defended finding needs evidence, not agreement

When the author replies that a flagged change was deliberate (in the description, a commit message, or a thread reply), intent answers "did they mean it", not "does it work". Surface the reply to the user as Step 1 of the review-code skill requires, and before anything is marked resolved, for observable behavior or layout, cite one of: the change exercised in a running app, a visual check, or a numeric walkthrough (the computed widths, the resulting instants, the rendered values). Resolving on the author's word alone fails this box.

## §V7. The scope checks were walked

The orchestrator walks §G1-§G4 in the review-code skill's Step 1 itself, because they concern the target as a whole rather than one topic. This box confirms the `SCOPE:` block exists and has per-box evidence: the `gh pr list` output for stacking, the title set against the diff's areas, the linked issue quoted (or "no linked issue"), the diff size and how it was read. A scope check reported as "scope fine" with no per-box line fails, the same as an aggregated receipt under §V3.

---

## How to use this in the output

The review ends with a **Checklist** subsection that names every group applicable to this diff (Always, plus each trigger group hit) with either a one-line receipt or `"n/a, diff does not touch X"`. A group that appears as an eyeballed aggregate instead of an enumerated receipt is unacceptable and fails this gate, even if every other gate reported PASS.

Example (generic file names):

```
**Checklist:**
- Always: read widget-form.tsx, widget-list.tsx, widget-actions.ts at abc1234; findings cite file:line + abc1234; nothing posted to GitHub.
- Scope: §G1 author has no other open PR; §G2 title "Add widget filters" matches the diff; §G3 issue #12 read, constraint "no API change" holds; §G4 diff 14KB, read whole.
- Locale: per-key audit below.
  - shared.json:L14: `total` = "Total" | namespace: ok (shared), plural: n/a (label), dupe: none, naming: matches value
  - widgets.json:L9: `widgetCount` = "Widgets" | namespace: FLAG generic noun → shared.json, plural: FLAG baked-plural → ICU, dupe: none, naming: matches value
- Boolean logic: grepped &&/||: 2 hits: widget-form.tsx:L41 extracted to `canSubmitWidget`, widget-list.tsx:L18 flagged (raw `status === 'A' || status === 'B'` left inline).
- Ternaries/casts: grepped ternaries: 0 hits. grepped as-casts: 1 hit: widget-actions.ts:L22 redundant `as Widget`, flagged.
- Hooks/queries/mutations: n/a, diff does not touch data-fetching hooks.
- State: n/a, diff does not add or edit component state.
- Dead wrappers: widget-actions.ts:L30 `const submitWidget = (data) => mutate(data)` kept, earns its place, narrows `unknown` payload to `WidgetInput`.
- Switch/if-else-if: n/a, diff adds no chain.
- Tests: grepped class assertions: 0 hits. grepped loose assertions: 1 hit, widget-list.test.tsx:L30 `toBeGreaterThan(0)` on a known count of 3, flagged. Gate `isFilterOpen`: widget-list.test.tsx:L41 (met), :L55 (not met).
- Exported APIs: n/a, diff adds no new export.
- Fixed-value discriminator: n/a, diff adds no new discriminator type.
- Self-review: lint (`npm run lint`) pass, typecheck (`npm run typecheck`) pass; full gate fan-out walked before this report; no commit/push/PR performed, none requested.
```

A skipped group means it was not verified; that is a gate FAIL, not a shorter report. An aggregated group where enumeration is required is the same failure as a missing one: it looks complete and isn't.
