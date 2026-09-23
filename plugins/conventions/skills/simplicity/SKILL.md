---
name: simplicity
description: "DRY, YAGNI and KISS conventions for TypeScript, JavaScript and other source files: reuse before writing, search for an existing capability first, delete or collapse what adds nothing, numeric coercion, types as narrow as their consumers, refactor leftovers, and props added to a shared component for one caller. Use when writing or reviewing code that adds a helper, component, type, prop, option or abstraction, or that repeats logic."
user-invocable: false
paths:
  - "**/*.{ts,tsx,js,jsx,mjs,cjs,rb,py,swift,go,java,kt,php,cs,rs}"
---

# Simplicity

## Contents

- Rules
- Review checklist
- Review detail
  - §P1–P3. The DRY / YAGNI / KISS standing lens
  - §P4. Reuse over reinvention
  - §P5. Numeric hygiene
  - §P6. The delete-or-collapse test
  - §P7. A type is as narrow as its sink needs
  - §P8. "This mirrors X" is diffed, not asserted
  - §P9. Refactor leftovers
  - §P10. A shared prop added for one caller

## Rules

The simplest code that does the job is the easiest to read, change and delete. Every construct earns its place.

- DRY: logic, a value, a literal or a block of markup has one source. Twice is the threshold: at the second copy, extract it to a named helper or constant.
- YAGNI: no speculative code. No param, prop or config option that nothing passes, no abstraction built for a hypothetical second caller, no dead branch. A generality the change does not use is removed, even if it might be needed later.
- KISS: take the materially simpler equivalent when one exists. A lookup object beats nested conditionals, an early return beats nesting, an existing util or standard-library call beats a hand-roll.
- Reuse before writing. Assume the capability already exists and look for it, in order: a prop or slot on the component already in use, a shared hook or util, a variant of an existing component, data already in state or the store. Search by shape (a type's field set, a component's props and markup), not only by name.
- Ask what breaks if a new construct is deleted or collapsed. If nothing does, use the simpler form. A named intermediate that makes a line readable is not a candidate.
- Finish the refactor: no leftover duplicate block, unused import, parameter nobody reads, or commented-out code.
- A prop added to a shared component for one caller's case makes every other caller carry it. Let that caller own or compose the behavior instead.

## Review checklist

The simplicity gate agent ticks every box against the diff. A box is FAIL if any matching construct violates the rule; the gate is FAIL if any box is FAIL. N/A a box only when the diff has no matching construct (state which).

- [ ] §P1 DRY: no logic, value, literal, or markup duplicated that should be a single source (a copied block, a re-declared constant, a re-implemented helper). (N/A: nothing duplicated in the diff)
- [ ] §P2 YAGNI: no speculative or unused code — no unused params/props, no abstraction with a single caller built for a hypothetical second one, no config option nothing passes, no dead branch. (N/A: no new abstraction, param, prop, or config option in the diff)
- [ ] §P3 KISS: no materially simpler equivalent left on the table — a lookup object beats nested conditionals, an early return beats nesting, an existing util/stdlib call beats a hand-roll. (N/A: nothing in the diff has a simpler available equivalent)
- [ ] §P4 Assume-it-exists: any new hand-rolled capability was checked against a prop/slot on the component already in use, a shared hook/util, a component variant, and data already in state/store, in that order, before being written; a component that only reuses a shared *hook* is still checked against a shared *component* that composes that same hook; a new type was grepped by its field set and a new component by its core props and markup, not only by name. (N/A: nothing hand-rolled in the diff)
- [ ] §P5 Numeric hygiene: coercions are NaN-safe and don't silently swallow a legitimate `0` (no bare `value ?? 0` on a nullable/optional numeric, no `Number(x) || 0`, no NaN-risky `Number(x)` on a possibly-empty/non-numeric value; no wrapping of an already-guaranteed `number`); a non-trivial conversion/encoding repeated at 2+ call sites is extracted to a named helper rather than re-inlined per site. (N/A: no numeric coercion and no repeated conversion in the diff)
- [ ] §P6 Delete-or-collapse: every new construct (variable, branch, guard, helper, prop, param, option, type, default, wrapper) passes "what breaks if I delete or collapse this?"; one that collapses to a simpler form with identical behavior FAILS, and the finding gives the concrete simpler form. "It works", "it's defensive", and "it's more explicit" are not justifications. A named intermediate kept for readability is exempt (clarity §C18). (N/A: no new construct in the diff)
- [ ] §P7 Types as narrow as their sink: every new or changed return/param type carries no member its consumers treat identically to another (a `=> T | undefined`, `| null`, or `| ''` whose sink handles the empty value exactly like the default narrows to `=> T`); the sink's behavior was opened or run before the finding claims it. (N/A: no new or changed signature)
- [ ] §P8 Mirror claims are diffed: wherever the PR or the review says a new member mirrors, follows, or matches an existing sibling, the two signatures are set side by side in the evidence; an unjustified difference between siblings is a finding. (N/A: no new member beside an existing sibling, and no such claim)
- [ ] §P9 No refactor leftovers: no markup or block left duplicated by an incomplete refactor, no import nothing uses, no prop or param threaded through and never read, no commented-out code. (N/A: none in the diff)
- [ ] §P10 A prop or option added to a shared component or shared helper for a single caller's case is questioned: could the caller own it, or compose the shared piece instead? (N/A: no shared component or helper signature changed)

## Review detail

Covers the standing DRY/YAGNI/KISS lens applied to every diff, reuse-over-reinvention (including the "assume it already exists" search), two numeric-hygiene rules (safe coercion and repeated-conversion extraction), the delete-or-collapse test on every new construct, type signatures wider than their sink needs, unverified "this mirrors X" claims, refactor leftovers, and shared-component props added for one caller.

### §P1–P3. The DRY / YAGNI / KISS standing lens

Apply this to every diff, not just the constructs called out elsewhere in this file. Evaluate every change against three questions and surface a finding whenever the answer is "no" — these are first-class smells with the same any-finding-fails weight as any other rule here, not stylistic extras to mention only if there's room.

- **DRY (§P1)** — is any logic, value, literal, or markup duplicated that should be a single source? A copied block, a re-declared constant, a re-implemented helper, a repeated JSX shape. (Repeated *conversions* have their own rule, §P5 below; repeated *sibling JSX* is covered by the `react` skill's §R6 — don't double-flag the same instance under both.)
- **YAGNI (§P2)** — is there speculative or unused code? Concretely: unused params/props; an abstraction built for a hypothetical second caller when there is only one; a config option nothing in the diff actually passes; a dead branch. A generality the PR doesn't use is a finding even if it "might be needed later."
- **KISS (§P3)** — is there a materially simpler equivalent already available? Concretely: a lookup object beating nested conditionals; an early return beating nesting; an existing util or stdlib call beating a hand-roll. Fewer moving parts for the same behavior wins.

Surface each with evidence and let the reader judge — never withhold a finding because the complexity seemed "probably needed."

### §P4. Reuse over reinvention

Before accepting a new component, util, hook, or type, grep for it. Most target repos are large enough that most domain primitives already exist somewhere.

When you spot a candidate for duplication, run two greps before flagging: one for the symbol name, one for keywords describing the behavior. If the existing thing is close but not quite right, suggest extending it — a variant, a new prop — rather than letting the new copy stand.

#### Assume the capability already exists — exhaust the search before hand-rolling

This is the general form of the rule above. The default assumption for any new code is **"this probably already exists,"** not "I'll build it." The failure mode is concluding *"there's no built-in way to do this, so I'll implement it"* without actually looking — and the hand-rolled version then drifts from the existing thing's styling, behavior, spacing, and edge-case handling. Reaching for a fresh implementation is the **last** step, taken only after the search comes up empty.

"Already exists" spans every layer — check all of them before writing new code:

- **A prop or slot on the component you're already using.** Before rendering an element *next to* a shared component, check its props/type definitions for one that produces it (e.g. `helperText`, `label`, `error`, adornments, `placeholder`, icon/empty-state slots). Illustrative, not exhaustive.
- **A shared hook or util** already present in the codebase for this exact concern.
- **An existing component or a variant of one** — extend it (`variant`/`size`/prop) rather than inlining styles.
- **Data already in a store or in state already fetched on the page** — filter or derive it client-side rather than adding a redundant endpoint or a new piece of state.

**Hook-reuse camouflages component-reuse.** A component can *look* compliant because it reuses a shared hook, while still reinventing a shared component that already wraps that same hook. When a component assembles a shared values hook (`useXValues`) + a generic input (a select/autocomplete/picker primitive) + option/filter wiring, that assembled trio is usually already packaged as a shared component (e.g. `<XPicker>` = `useXValues` + the generic input + scoping/filtering). "It uses the shared hook" is NOT enough — grep for a shared component that composes the same hook and prefer it, expressing the delta through its props (an exclude list, a disabled predicate, a query filter) instead of re-hand-assembling.

```tsx
// Flag — hand-assembles what <XPicker> already packages, even though useXValues is "reused"
const { options } = useXValues({ type: X, scopeId })
const available = options.filter((o) => !selectedIds.includes(o.value))
<GenericAutocomplete multiple name="x_ids" values={available} />

// Prefer — the shared component composes useXValues + the generic input; pass the delta as props
<XPicker multiple name="x_ids" excludeIds={selectedIds} />
```

When flagging, grep the target repo for the shared component's path and cite it — note that hook-level reuse does not exempt the finding.

Concrete instance (the recurring one): a sibling element hand-rendering a field's helper text, with manual padding to approximate alignment —

```tsx
<SomeField name="x" label={label} />
<Typography sx={{ color: 'text.secondary', fontSize: 11, pl: 1 }} variant="caption">{helper}</Typography>
```

— when the field already takes the prop and renders it correctly (right layout/alignment, and it yields to the validation error when invalid):

```tsx
<SomeField name="x" label={label} helperText={helper} />
```

When flagging: grep for the existing thing (the component's prop types, the hook, the store) and cite it, then flag the hand-rolled version. Don't flag if a genuine search confirms nothing fits.

**Search by shape, not only by name.** A duplicate usually has a different name, so a name grep alone misses it:

- For a new **type**, grep for its field set (two or three of its distinctive field names together), not its name. A second interface with the same fields is the duplicate.
- For a new **component**, grep for its core props and its distinctive markup (the primitive it renders, the prop combination it takes). A near-copy of an existing component rarely shares its name.
- For a new **helper**, grep for the calls it makes and the keywords of what it computes.

### §P5. Numeric hygiene

#### Safe numeric coercion

Flag numeric coercion/fallback that is either unsafe or redundant:

- `value ?? 0` where `value` is a nullable/optional numeric (or numeric string) and the `0` is standing in as a numeric default.
- `Number(x) || 0` — the `||` also swallows a legitimate `0`-after-coercion result, which reads as a hack.
- `Number(x)` where `x` may be empty/`null`/non-numeric and downstream math would otherwise see `NaN`.

```ts
// Flag
const amount = balanceDue ?? 0
const rate = Number(input) || 0

// Prefer — a single named call the rest of the codebase reads the same way
const amount = coerceNumber(balanceDue)
const rate = coerceNumber(input)
```

Fix: use the project's safe-coercion helper if one already exists (grep for it before proposing a new one). If none exists, propose a small named helper rather than repeating the `?? 0` / `|| 0` pattern inline. **Do NOT wrap an already-guaranteed `number`.** If the value is typed `number` with no `null`/`undefined`/string in its union, wrapping it in a coercion call is redundant — that's the clarity redundant-coercion flag, not an improvement. The rule applies only when a coercion or fallback is genuinely needed.

#### A non-trivial conversion repeated across call sites → one named helper

When the same small conversion/encoding is written inline at 2+ call sites, extract a named helper so the encoding lives in one place. This is easy to miss because each instance is individually a "fine short ternary": no single one trips a ternary-complexity rule, and a boolean-to-value mapping isn't discriminator-selection, so other gates pass each instance in isolation. The smell is the *repetition of the mapping*, especially both directions of the same encoding (encode at write, decode at read) — adding one more case then means editing N sites, and it's easy to get a branch backwards.

```ts
// Flag — the same boolean<->Mode encoding inlined at four sites (read + write, two fields)
fieldA: (saved?.fieldA ?? Mode.ON) === Mode.ON,            // decode
fieldB: (saved?.fieldB ?? Mode.ON) === Mode.ON,            // decode
// ...elsewhere...
fieldA: form.fieldA ? Mode.ON : Mode.OFF,                  // encode
fieldB: form.fieldB ? Mode.ON : Mode.OFF,                  // encode

// Prefer — the encoding is defined once, each direction a named helper
const isOn = (value?: Mode) => (value ?? Mode.ON) === Mode.ON
const toMode = (on: boolean) => (on ? Mode.ON : Mode.OFF)
```

Calibrate by cost: a trivial 2-site repeat is a `nitpick`; a both-directions encoding or 3+ sites is a `suggestion`. This is distinct from the repeated-*JSX*-block rule (the `react` skill's §R6, which maps an array); this rule is about a repeated *expression/conversion* becoming a named helper.

### §P6. The delete-or-collapse test

For every new construct in the diff, ask **"what breaks if I delete or collapse this?"** If the answer is "nothing, the behavior is identical", it is a finding, and the simplest form that produces the same observable behavior is the correct one. Apply it on your own to every changed line; missing an obvious collapse that the user then has to point out is a review defect, the same as missing a bug.

Concretely (illustrations, not an exhaustive list):

- **A `let` plus `if`-assignment that one expression replaces.**
  ```ts
  // Flag
  let itemLabel: string | undefined
  if (count !== undefined) {
    itemLabel = String(count)
  }

  // Prefer: optional chaining yields undefined for undefined
  const itemLabel = count?.toString()
  ```
- **A guard or branch for a state the types already rule out.** If `widget` is typed non-optional, `if (!widget) return` guards nothing.
- **Null handling that `?.`, `??`, or a parameter default already covers.**
- **A prop, param, or option that every caller passes with the same value**, or that the callee could read from a context it already consumes.
- **A default, wrapper, or type alias** that restates what it wraps (overlaps structure §S4; report it once, under the closer fit).

Give the concrete simpler form in the finding, not "simplify this", and scan the rest of the diff for the same shape. A named intermediate that exists for readability is not a collapse candidate (clarity §C18).

### §P7. A type is as narrow as its sink needs

The delete-or-collapse test applies to type signatures too. A return or parameter type can carry surface that no consumer uses, exactly like an unused branch.

```ts
// Flag: every consumer passes the result to a class-merging helper, which drops '' and undefined alike
getItemClassName?: (item: Item) => string | undefined

// Prefer
getItemClassName?: (item: Item) => string
```

Before flagging, open (or run) the sink and confirm it treats the empty value exactly like the default: a class-merging helper dropping `''`, a renderer skipping `null`, a serializer omitting `undefined`. If the sink distinguishes them, the wider type is doing work and stays.

### §P8. "This mirrors X" is diffed, not asserted

When the PR, or your own notes, describe a new member as following, mirroring, or matching an existing sibling, put the two signatures side by side in the evidence and compare them literally. Siblings that disagree in shape are a finding unless the difference is justified:

```ts
isItemDisabled?: (item: Item) => boolean            // existing sibling: definite return
getItemClassName?: (item: Item) => string | undefined // new: optional return, for no stated reason
```

"This mirrors X" without the comparison is the same shortcut as asserting a library's behavior from memory.

### §P9. Refactor leftovers

An incomplete refactor leaves debris the diff no longer needs:

- Markup or a block duplicated because the new version was added and the old one never removed.
- An import nothing in the file uses any more. If the target repo's linter reports unused imports, its output is the receipt; cite it.
- A prop or parameter still threaded through a component or function that no longer reads it.
- Commented-out code. Version control keeps the old version; the comment only adds noise.

### §P10. A shared prop added for one caller

A prop or option added to a shared component or helper so that one caller can get a special case makes every other caller carry it. Ask whether the caller could own the behavior (wrap or compose the shared piece), or whether the case is general enough that several callers would plausibly use it today. A shared component with many props, several of which only one caller passes, is the accumulated form of this finding.

## Sweeps

Save the diff under review to a file and run the script over it; `-` reads the diff from stdin. No other sweep is bundled for this topic.

- `added-lines.sh` (citation map): every added line as `path:line: text`, with the source line number at the head SHA. Cite every finding's line from this output or from a sweep hit, never from a position in the diff file.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/added-lines.sh" <diff-file>
  ```
