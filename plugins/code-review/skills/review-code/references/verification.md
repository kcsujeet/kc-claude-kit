# Verification gate

This is the receipts gate: it does not re-derive findings, it checks that every OTHER gate actually produced the evidence its own reference file demands. The verification gate agent owns this file. It walks the Always items on every diff, plus every trigger group below whose trigger the diff hits, and ticks each box PASS / FAIL / N/A with cited evidence. The gate is FAIL if any applicable box is FAIL.

A trigger group here does not restate another gate's rule — it confirms that gate's mandatory receipt shows up in the review output. "The naming gate found no boolean issues" is not evidence; "grepped &&/||: 3 hits, 3 verdicts below" is. If a gate's headline receipt is missing from the output, this gate fails even when the underlying gate reported PASS — a PASS with no receipt is indistinguishable from a gate that never looked.

This applies identically to two scenarios:
- **Peer review** — reviewing someone else's PR / branch / diff.
- **Self-review** — the reviewing agent is also the one who wrote the diff, about to say "done" / "ready" / "lint and types pass." Lint and types passing is not the same as convention-clean; a self-review skips this gate at the same cost a peer review would.

## Gate checklist

- [ ] §V1 Always items walked with evidence: every non-trivial changed file read at the actual head SHA, every finding cites `file:line` plus the short head SHA, nothing was posted to GitHub. (N/A: never — applies to every review)
- [ ] §V2 Per-trigger receipt lines present for every trigger group the diff hits (list which groups applied, and cite each group's receipt). Each group has its own N/A condition, walked independently:
  - locale files touched → i18n per-key audit table present (N/A: no locale files in diff)
  - boolean logic added/edited → `grepped &&/||: N hits` with per-hit verdicts (N/A: no boolean chain added/edited)
  - ternaries or casts added/edited → `grepped ternaries: N hits` / `grepped as-casts: N hits` (N/A: no ternary or cast added/edited)
  - hooks/queries/mutations added/edited → named consumers per new hook, `mutateAsync` grep receipt (N/A: no hook/query/mutation added/edited)
  - state added/edited → lowest-common-ancestor placement stated, rationale comment confirmed for order-dependent mutations (N/A: no state added/edited)
  - dead wrappers kept anywhere in the diff → what each earns its place stated (N/A: no wrapper-shaped code in diff)
  - switch or if/else-if chain added → structure gate's lookup-object boxes walked per chain (N/A: no chain added)
  - exported APIs added → doc-comment box walked (N/A: no new exported API)
  - fixed-value discriminator added → enum boxes walked, call sites checked (N/A: no new discriminator type)
  - self-review only → lint/typecheck receipt, full fan-out walked, commit/push/PR permission confirmed (N/A: this is a peer review of someone else's diff, not a self-review)
- [ ] §V3 No aggregate receipts where enumeration is required: per-key table has one row per key (not a summary count), per-hit grep verdicts list every hit individually (not "N hits, all fine"), named-consumer citations name the actual file per hook (not "hooks have consumers"). (N/A: no trigger group in this diff requires enumerated evidence)

---

## §V1. Always

Walk these on every review, peer or self, every round:

- [ ] **Read every non-trivial changed file at the actual head SHA** — not a subagent's summary of it, not a diff hunk in isolation. A finding built only from a diff hunk misses surrounding context (an existing guard three lines above the hunk, a sibling branch the hunk doesn't show). "I read the summary another agent produced" does not satisfy this box.
- [ ] **Every finding cites `file:line` and the short head SHA.** A finding with no line number, or one that cites a stale SHA from an earlier round, is not verifiable by the reader and fails this box.
- [ ] **Nothing was posted to GitHub.** No inline comment, no top-level comment, no review submission, unless the user gave an explicit, fresh post signal after seeing the draft. Output stays in chat.

## §V2. Trigger-group receipts

Each subsection below names the gate that owns the underlying rule and the exact receipt shape that gate must show in its output. This gate does not re-judge the rule — it judges whether the receipt is there.

### Locale files touched

Owning gate: **i18n**. Required receipt: the per-key audit table (see `references/i18n.md` §I1 for the row shape — do not duplicate the row shape here, cross-reference it). Both this gate and the i18n gate must show the table; if the i18n gate's own output is missing it, that is an i18n gate FAIL, and this gate also FAILs because the receipt isn't present in the review. A summary line ("checked N keys, all clean") in place of the table fails both gates.

N/A: no locale files changed in the diff.

### Boolean logic added or edited

Owning gate: **naming**. Required receipt: `grepped &&/||: N hits` stated explicitly (including `0 hits` when true), followed by one verdict per hit — extracted-to-a-named-boolean or flagged. A verdict that groups hits ("all 3 look fine") instead of addressing each individually fails this box even if the underlying naming gate happened to pass.

N/A: the diff adds or edits no `&&`/`||` chain.

### Ternaries or casts added or edited

Owning gate: **clarity**. Required receipts: `grepped ternaries: N hits` and `grepped as-casts: N hits`, each stated explicitly with `0 hits` when true, each hit given its own verdict (kept as a simple ternary / flagged as nested-long-multiline / cast is redundant / cast is genuinely narrowing an unknown). Two separate grep lines are required — a combined "grepped ternaries and casts: N hits" collapses two independent sweeps into one and loses which construct each hit belongs to.

N/A: the diff adds or edits no ternary and no `as` cast.

### Hooks, queries, or mutations added or edited

Owning gates: **react** (fetch ownership, mutation pattern) and **structure** (co-location, unnecessary exports). Required receipts:
- For every new hook, its consumers named explicitly by file: `"useFoo has 1 consumer (Foo.tsx, same folder ✓)"` or `"useFoo has 1 consumer (components/Foo.tsx) — should move down to components/"`. A count with no file name ("useFoo has 1 consumer") is not a receipt.
- `mutateAsync` grep receipt: `grepped mutateAsync: N hits` with a verdict per hit (justified-async caller vs. should switch to `mutate` + callback).
- Any internal plumbing constant introduced alongside a new data-fetching hook (a query-key fragment, a resource-name string, a path constant) is confirmed unexported unless something outside the file actually imports it — state the grep result, not an assumption. This folds the "no unnecessary export" check into this group rather than treating it as its own trigger.
- If the diff touches form validation, one receipt line confirming hand-rolled checks were checked against the validation library's own API before being kept (owning gate: **react**, form box).

N/A: no hook, query, or mutation added or edited in the diff.

### State added or edited

Owning gate: **structure** (placement) and **clarity** (ordering rationale). Required receipts:
- Placement stated explicitly: which component/hook owns the new state, and why that is the lowest common ancestor that actually consumes it (not "might need it later").
- For any two-step or order-dependent mutation (`update` then `remove`, `setX` then `setY` where order matters), confirmation that a rationale comment exists at the call site, with `file:line`.

N/A: no state added or edited in the diff.

### Dead wrappers (always evaluated, not trigger-gated)

Owning gate: **structure**. This one has no "diff touches X" trigger — every diff can contain a dead wrapper anywhere (component code, context providers, route handlers, hooks), so it is walked every round regardless of what kind of change the diff is. Required receipt: for every wrapper-shaped piece of code kept in the diff, a one-line statement of what it adds — transformation, type narrowing, a default value, a side effect, or re-export documentation. "Matches an existing pattern in the codebase" is explicitly not an acceptable receipt; a copy-pasted dead wrapper is still dead.

N/A: no wrapper-shaped code (single-item wrap-then-spread, passthrough function, single-use alias, identity transform, promise-around-promise, producer/consumer re-derivation) anywhere in the diff.

### Switch or if/else-if chain added

Owning gate: **structure**, lookup-object boxes. Required receipt: each chain walked individually against the structure gate's branch-selection box — does it just select a value (map it), does per-branch computation get an exemption it shouldn't (it doesn't — use a thunk map), is there a trailing default (the map's fallback), is nesting flattened, does a surviving chain do genuinely divergent work with the finding saying so. A group verdict ("no switch/chain issues") without walking each chain fails this box.

N/A: the diff adds no `switch` and no `if`/`else-if` chain.

### Exported APIs added

Owning gate: **structure**, doc-comment box. Required receipt: for every new exported function, hook, component, or props/type interface, a stated verdict — has a doc comment that adds real information, missing one it needs, or the name is self-explanatory enough that a doc comment would only restate it. A blanket "exports documented ✓" without walking each export fails this box.

N/A: the diff adds no new exported function, hook, component, or props/type interface.

### Fixed-value discriminator added

Owning gate: **structure**, enum boxes. Required receipts: the new discriminator type is confirmed as an enum (not a literal union) if it represents a serialized/compared domain state; every call site in the same diff that compares the field is confirmed to use the enum member (grep the field name and cite the result), not the raw string.

N/A: the diff adds no new fixed-value discriminator type.

### Self-review only

Applies only when the reviewing agent is also the diff's author, about to declare the work done. Required receipts:
- The project's lint and typecheck commands — detected from its own `package.json` scripts, Makefile, or CI config, never assumed from a specific package manager or another project's convention — were run, with the exact command and pass/fail result cited.
- The entire gate fan-out (naming, clarity, structure, simplicity, datetime, react, i18n, project-conventions, this gate) was walked against my own diff before saying "done" / "ready" / "verified" — not just lint and typecheck.
- If the diff was committed, pushed, or turned into a PR, the user explicitly used one of those words. "Make the changes" or "implement this" is not permission to commit, push, or open a PR.

N/A: this is a peer review of someone else's diff, not a self-review.

## §V3. No aggregate receipts where enumeration is required

Several of the groups above have a built-in trap: an aggregate summary reads as complete but hides exactly the violations only per-item evaluation catches. This box fails whenever a receipt that should be enumerated is instead reported as a count or a single verdict:

- **Per-key i18n table** — one row per new key is mandatory evidence. `"checked 7 keys, all unique"` is not the table; it hides a generic noun in the wrong file or a missing ICU plural that only shows up when each key is walked individually.
- **Per-hit grep verdicts** (`&&`/`||`, ternaries, `as`-casts) — `"grepped 3 &&/|| chains, all fine"` is not three verdicts; it hides the one non-obvious operand that needed its own name.
- **Per-consumer hook citations** — `"all new hooks have consumers"` is not a citation; it hides the one hook whose sole consumer sits two folders away and should have been co-located instead.
- **Per-chain / per-export / per-call-site walks** (switch/if-else-if, exported APIs, enum call sites) — a single pass/fail line covering "all chains" or "all exports" collapses distinct constructs that can fail independently.

An aggregated receipt in place of an enumerated one is not a partial pass — it is treated the same as a missing receipt: FAIL the box, and name which group's receipt was aggregated instead of enumerated.

N/A: no trigger group applicable to this diff requires enumerated evidence (i.e., every applicable group above is itself N/A).

---

## How to use this in the output

The review ends with a **Checklist** subsection that names every group applicable to this diff — Always, plus each trigger group hit — with either a one-line receipt or `"n/a, diff does not touch X"`. A group that appears as an eyeballed aggregate instead of an enumerated receipt is unacceptable and fails this gate, even if every other gate reported PASS.

Example (generic file names):

```
**Checklist:**
- Always: read widget-form.tsx, widget-list.tsx, widget-actions.ts at abc1234; findings cite file:line + abc1234; nothing posted to GitHub.
- Locale: per-key audit below.
  - shared.json:L14 — `total` = "Total" | namespace: ok (shared), plural: n/a (label), dupe: none, naming: matches value
  - widgets.json:L9 — `widgetCount` = "Widgets" | namespace: FLAG generic noun → shared.json, plural: FLAG baked-plural → ICU, dupe: none, naming: matches value
- Boolean logic: grepped &&/||: 2 hits — widget-form.tsx:L41 extracted to `canSubmitWidget`, widget-list.tsx:L18 flagged (raw `status === 'A' || status === 'B'` left inline).
- Ternaries/casts: grepped ternaries: 0 hits. grepped as-casts: 1 hit — widget-actions.ts:L22 redundant `as Widget`, flagged.
- Hooks/queries/mutations: n/a, diff does not touch data-fetching hooks.
- State: n/a, diff does not add or edit component state.
- Dead wrappers: widget-actions.ts:L30 `const submitWidget = (data) => mutate(data)` kept — earns its place, narrows `unknown` payload to `WidgetInput`.
- Switch/if-else-if: n/a, diff adds no chain.
- Exported APIs: n/a, diff adds no new export.
- Fixed-value discriminator: n/a, diff adds no new discriminator type.
- Self-review: lint (`npm run lint`) pass, typecheck (`npm run typecheck`) pass; full gate fan-out walked before this report; no commit/push/PR performed, none requested.
```

A skipped group means it was not verified — that is a gate FAIL, not a shorter report. An aggregated group where enumeration is required is the same failure as a missing one: it looks complete and isn't.
