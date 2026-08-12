# Simplicity gate

Covers the standing DRY/YAGNI/KISS lens applied to every diff, reuse-over-reinvention (including the "assume it already exists" search), and two numeric-hygiene rules: safe coercion and repeated-conversion extraction.

## Gate checklist

The simplicity gate agent ticks every box against the diff. A box is FAIL if any matching construct violates the rule; the gate is FAIL if any box is FAIL. N/A a box only when the diff has no matching construct (state which).

- [ ] §P1 DRY: no logic, value, literal, or markup duplicated that should be a single source (a copied block, a re-declared constant, a re-implemented helper). (N/A: nothing duplicated in the diff)
- [ ] §P2 YAGNI: no speculative or unused code — no unused params/props, no abstraction with a single caller built for a hypothetical second one, no config option nothing passes, no dead branch. (N/A: no new abstraction, param, prop, or config option in the diff)
- [ ] §P3 KISS: no materially simpler equivalent left on the table — a lookup object beats nested conditionals, an early return beats nesting, an existing util/stdlib call beats a hand-roll. (N/A: nothing in the diff has a simpler available equivalent)
- [ ] §P4 Assume-it-exists: any new hand-rolled capability was checked against a prop/slot on the component already in use, a shared hook/util, a component variant, and data already in state/store, in that order, before being written; a component that only reuses a shared *hook* is still checked against a shared *component* that composes that same hook. (N/A: nothing hand-rolled in the diff)
- [ ] §P5 Numeric hygiene: coercions are NaN-safe and don't silently swallow a legitimate `0` (no bare `value ?? 0` on a nullable/optional numeric, no `Number(x) || 0`, no NaN-risky `Number(x)` on a possibly-empty/non-numeric value; no wrapping of an already-guaranteed `number`); a non-trivial conversion/encoding repeated at 2+ call sites is extracted to a named helper rather than re-inlined per site. (N/A: no numeric coercion and no repeated conversion in the diff)

## §P1–P3. The DRY / YAGNI / KISS standing lens

Apply this to every diff, not just the constructs called out elsewhere in this file. Evaluate every change against three questions and surface a finding whenever the answer is "no" — these are first-class smells with the same any-finding-fails weight as any other rule here, not stylistic extras to mention only if there's room.

- **DRY (§P1)** — is any logic, value, literal, or markup duplicated that should be a single source? A copied block, a re-declared constant, a re-implemented helper, a repeated JSX shape. (Repeated *conversions* have their own rule, §P5 below; repeated *sibling JSX* is covered by a separate clarity rule — don't double-flag the same instance under both.)
- **YAGNI (§P2)** — is there speculative or unused code? Concretely: unused params/props; an abstraction built for a hypothetical second caller when there is only one; a config option nothing in the diff actually passes; a dead branch. A generality the PR doesn't use is a finding even if it "might be needed later."
- **KISS (§P3)** — is there a materially simpler equivalent already available? Concretely: a lookup object beating nested conditionals; an early return beating nesting; an existing util or stdlib call beating a hand-roll. Fewer moving parts for the same behavior wins.

Surface each with evidence and let the reader judge — never withhold a finding because the complexity seemed "probably needed."

## §P4. Reuse over reinvention

Before accepting a new component, util, hook, or type, grep for it. Most target repos are large enough that most domain primitives already exist somewhere.

When you spot a candidate for duplication, run two greps before flagging: one for the symbol name, one for keywords describing the behavior. If the existing thing is close but not quite right, suggest extending it — a variant, a new prop — rather than letting the new copy stand.

### Assume the capability already exists — exhaust the search before hand-rolling

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

## §P5. Numeric hygiene

### Safe numeric coercion

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

### A non-trivial conversion repeated across call sites → one named helper

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

Calibrate by cost: a trivial 2-site repeat is a `nitpick`; a both-directions encoding or 3+ sites is a `suggestion`. This is distinct from a repeated-*JSX*-block rule (which maps an array); this rule is about a repeated *expression/conversion* becoming a named helper.
