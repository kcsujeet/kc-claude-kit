# Structure gate

Code-placement and API-shape rules for the diff under review. Covers nine independent failure modes: mixed responsibilities inside one unit, wrong-layer co-location, leftover single-file folders and re-export barrels, dead wrappers, branch-selection that should be a lookup, misplaced helpers, missing JSDoc on exported APIs, default exports on new files, and literal unions standing in for serialized enums.

## Gate checklist

The structure gate agent ticks every box below against the diff. A box is FAIL if any matching construct in the diff violates the rule; the gate is FAIL if any box is FAIL. Mark a box N/A only when the diff has no matching construct (state which).

- [ ] §S1 Separation of concerns: each unit (function, hook, component, module) has one observable responsibility; no data-reading unit also bundles a selector, formatter, or mutation; no util silently performs a side effect. (N/A: no multi-responsibility unit added)
- [ ] §S2 Co-location/promotion: single-consumer code stays next to its consumer; multi-consumer code sits at the consumers' nearest common ancestor judged by scope/coupling, not raw count; view-local helpers are promoted only when a real external consumer appears (YAGNI-gated), not on speculation; inherently-shared-layer code is placed in its shared layer from day one regardless of current consumer count. (N/A: no files moved/added)
- [ ] §S3 Single-file folders are flattened; no `export { default } from './X'` re-export barrels. (N/A: no folders/barrels touched)
- [ ] §S4 No dead wrappers: single-item array wrap-then-spread, no-op async passthroughs, argument destructure-and-reconstruct passthroughs, single-use const aliases, verbatim object-spread, a producer value the consumer independently re-derives, promise-wrapping-a-promise, manual await-then-callback when the callee already accepts a callback. (N/A: none added)
- [ ] §S5 Lookup objects over `switch`/nested `if`: branch-selecting-a-value uses a named map, not a switch or if/else-if chain; differing per-branch computation is handled with a thunk map, not treated as an exemption; a trailing default/else becomes the map's fallback; more than one level of `if` nesting is flattened; the branch key, if derived from multiple booleans, is built from named single-level intermediates, never a chained ternary; a fix for one violation here doesn't introduce another (e.g. replacing the map with an if-early-return helper). (N/A: no branch-selection of one value)
- [ ] §S6 Helpers placed by consumer count: a helper with exactly one consumer is not pulled into its own subfolder; a helper with two or more consumers is not left stranded in one consumer's local folder. (N/A: no helper added)
- [ ] §S7 JSDoc on every new exported function, hook, component, and props/type interface, unless the name is fully self-explanatory; no JSDoc that merely restates the name. (N/A: no new exported API, or target repo doesn't use doc comments — confirm by grep before marking N/A)
- [ ] §S8 New files use named exports (`export const Foo`), inline on the declaration, not `export default` and not a trailing `export { Foo }` block; sibling default-exported files are not an exemption; framework-mandated default exports (route/page/layout files and equivalents) are exempt. (N/A: no new module)
- [ ] §S9 Fixed-value discriminators that get serialized/compared at runtime (status, mode, kind, origin, vendor type, etc.) are TypeScript string enums, not string-literal unions; placement matches wherever the target repo already keeps sibling enums. (N/A: no new status/mode/kind field)

## §S1. Separation of concerns

Each unit of code should have one observable responsibility. A reader looking at the name and signature should be able to predict what it does *and what it doesn't do*. Bundling unrelated concerns hides side effects, couples consumers to things they don't need, and makes the unit harder to test or replace.

**The rule of thumb:** if a reader can't tell from the import or call site what categories of work the unit performs (network? state? rendering? pure computation?), the split is wrong.

Common manifestations to flag:

- **A data-reading unit that also bundles formatters or selectors.** A hook or function whose job is "fetch/read X" should return the read result (`{ data, isLoading, error, refetch }` or equivalent) and nothing else. Selectors, formatters, lookups, or any pure transformation over the read shape belong in a plain utility, not folded into the read unit's return. Otherwise every consumer of the formatter drags in the read mechanism too, and the formatter can't be used outside that context.
- **A utility function that quietly performs side effects.** A `formatX`/`parseX` that secretly writes to a store, fires a network call, or invalidates a cache. Util-shaped names imply pure transformations; side effects should be visible at the call site.
- **A component bundling fetch + derivation + render.** Split the read into its own unit, push derived values into a plain helper (or a memoized selector at the call site), and let the component render.
- **A read unit bundling a mutation, or a mutation unit bundling a query.** Flag as a §S1 violation regardless of which framework-specific data layer owns the split.
- **A single helper that does parsing + validation + business logic.** Split into separately testable units.

**Flag shape:** when a read unit returns `{ data, isLoading, ...somethingElse }`, name what `somethingElse` is and ask whether it belongs at the call site (consumer-derived) or in a plain helper (pure transformation). If it's neither, a concern was missed.

The convention is not "everything must be pure" — state, effects, and async work all have legitimate homes. The convention is that those homes are obvious from the type and name of the unit, not hidden inside it.

**The directory path is part of the contract.** A file under a hooks/read-unit location advertises that it exports that kind of unit; a file under a utils/helpers location advertises pure functions; a file under components advertises components. When a helper is correctly extracted out of a hook (good) but the new file still lands in the hooks location (bad), the path still lies — every importer resolves it from a path that promises a hook. Two checks must both pass:

1. The read unit is lean (returns only its data-shape fields, no helper).
2. The extracted helper lives where its shape implies, not where it happened to be extracted from.

If (1) is satisfied but the extraction landed in the wrong location anyway, the split is incomplete — flag it as a mechanical move (relocate + update import paths at each call site), not a design problem.

**Where exactly does the extracted helper go?** Don't guess a layout; grep the target repo. Check whether a `utils/`-equivalent folder already exists at the relevant scope (app-level, feature-level, or co-located), and follow whatever grouping convention is already visible for helpers of that kind — the same resource/domain naming the read units already use. Don't invent a new top-level grouping word (e.g. calling something a "feature" when the surrounding code doesn't use that shape) just to house one file.

## §S2. Code placement and co-location

New code should follow the target repo's existing layout — grep for where similar units already live before proposing a location; don't impose a structure the repo hasn't adopted. Old code under a legacy layout should not be flagged just for being there if it's an established, still-in-use pattern for that area — migrations happen gradually, one area at a time.

**Co-location rule: promote to the consumers' nearest common ancestor — judged by consumer *scope*, not raw count.**

- **Exactly one consumer** → keep the helper in the same location as its consumer, no separate subfolder. The clearest example is a paired hook-and-view: a hook that only ever backs one component lives side by side with it.
- **Multiple consumers** → move it to the **nearest folder that contains all of them**, and no higher. The destination is decided by *coupling and realistic reuse* — how tightly the helper belongs to one set of consumers and whether anything else could plausibly consume it — not by a raw count:
  - Tightly coupled to one consumer subtree, used only by those consumers, with no realistic external consumer → co-locate at the subtree's shared root, even across sibling subfolders. This is the primary signal on its own. A dependency that only exists inside that subtree (e.g. the helper reads a context/provider mounted only within those consumers) *reinforces* the call but isn't required — sole-use plus tight coupling is enough.
  - Genuinely cross-boundary, or plausibly reusable standalone → promote. If the helper is consumed by the shared data/resource layer, or by consumers in another feature/domain, move it to that feature's shared subfolder or the app-global shared location.
- **For a view-bound helper, promotion is YAGNI-gated — pull it out when a real external consumer appears, not before.** Don't relocate a presentation/formatting helper to a shared location on the *speculation* that something might reuse it. Ask "is anything outside this subtree consuming it *today*?" — if no, it stays co-located regardless of consumer count.
- **Role overrides YAGNI for inherently-shared-layer code.** A unit whose *role* is the shared data/resource layer belongs in the shared location from day one, even with a single current consumer. Its home is dictated by architecture, not by counting consumers — it is by definition the reusable seam other code composes against, so co-locating it next to today's one caller and waiting is wrong. YAGNI gates *view-local* helpers; it does not demote data-layer code out of its layer.

**Worked example (promotion within a feature).** A hook `useRequestPriceSummary`, defined inside one subview's folder, is consumed by two sibling components in that same subview — no promotion needed, it stays. Once a third consumer appears in an unrelated subview of the same feature, promote it to the feature's own shared hooks location — not all the way to the app-global shared location. This is promotion to the nearest sensible shared root, not a jump to the top.

**Counter-example (do not over-promote).** A `useSomeFormatters` presentation hook co-located with one view's components — consumed by several components in that view plus one sibling read-only view — correctly stays put even at five or six consumers: it is tightly coupled to those view components, used only by them, with no realistic chance of being consumed elsewhere. (It may also read a context that only exists within that view subtree — a reinforcing signal, but the coupling alone justifies staying even without it.) Moving it to the app-global shared location, where the resource/actions data-layer hooks live, would falsely imply it's a cross-cutting data hook. It moves only if and when some other feature actually needs it.

**Audit trigger on restructures.** When a PR moves a folder (reshuffle, rename, etc.), every file inside it inherits the new placement. Re-evaluate each one against this rule even if it didn't move *within* the parent — the parent move IS a placement change. Don't give a file a pass just because "it was already there"; a pre-existing violation propagated through a rename becomes the current PR's violation.

**Cross-feature imports** (one feature importing directly from another feature's internals) are a placement smell in any codebase organized by feature — compose at a shared layer instead.

## §S3. Flatten single-file folders; no re-export barrels

**Single-file folders: flatten.** A folder containing exactly one file (no sub-components, no co-located hook, no helpers, no styles, no test) is dead structure — drop the folder, leave the file at the parent level. The folder earns its place the moment a second file appears alongside.

**No `export { default } from './X'` re-export barrels.** A single-item `index.ts` that exists only to shorten an import path adds no value: it perpetuates the default-export anti-pattern (§S8) and the importer can resolve the actual file directly with one extra path segment. Either flatten the folder or have the importer reach the file directly. This is distinct from a real barrel that groups several already-declared named exports with intent — that earns its place; a barrel whose sole content is one re-exported default does not.

## §S4. No dead wrappers

If a wrapper adds no semantic value over the thing it wraps, drop it and use the wrapped value directly. Wrappers earn their place by adding a transformation, a type narrowing, a side effect, a default, or documentation that the wrapped thing cannot provide on its own. If you cannot name what the wrapper adds, it is dead.

This rule is **absolute** and applies to functions, variables, arrays, objects, hooks, components — anything. Distinct shapes of the same mistake recur across a single PR; catch all of them independently, don't stop at the first.

**Dead wrapper shapes to flag:**

- **Single-item array wrapping a const, only ever spread back out:**
  ```ts
  // Bad
  export const FOO_KEY = [BASE_KEY]
  // …
  key: [...FOO_KEY, id]

  // Good
  key: [BASE_KEY, id]
  ```
  Same for any `const FOO_BASE = [X]` followed by `[...FOO_BASE, y]`. Inline it.

- **Async function that only awaits and returns nothing useful:**
  ```ts
  // Bad
  return { refetch: async () => { await refetch() } }

  // Good
  return { refetch }
  ```
  If `refetch` already returns a promise, update the return-type annotation instead of wrapping.

- **Function that destructures-and-reconstructs the arguments it receives:**
  ```ts
  // Bad
  return {
    callback: (args, { onDone }: CallbackOptions = {}) => callback(args, { onDone })
  }

  // Good
  return { callback }
  ```
  Calling-convention preservation is not a transformation. If the options type only re-declares fields already on the wrapped function's own options type, drop it and expose the wrapped function directly.

- **Const alias used exactly once at the same scope:**
  ```ts
  // Bad
  const handleClose = onClose
  return <Dialog onClose={handleClose}>

  // Good
  return <Dialog onClose={onClose}>
  ```
  The alias adds a hop without renaming or transforming.

- **Object spread that reproduces the source verbatim:**
  ```ts
  // Bad — the surrounding utility already defaults to identity transforms
  transformResponse: (res: T) => ({ ...res })
  ```
  Drop the option entirely.

- **A value the consumer already independently derives from the same input** (producer = any function, util, hook, provider, component — anything handing a value to a caller): if the producer returns a value computed purely from data the consumer also has, and the consumer separately computes the same thing, that's two derivations, not one source.
  ```ts
  // Bad — producer returns it, consumer recomputes it from the same input
  // producer:  const ready = Boolean(a && b && c)   // …and returns `ready`
  // consumer:  const ready = Boolean(a && b && c)   // already has a, b, c

  // Good — one place owns the derivation; the other reads it (or keeps its own)
  ```
  Distrust the "single source of truth" justification here — a value the consumer can and does recreate is the opposite of a single source. Fix in either direction (drop it from the producer's output, or delete the consumer's copy and read the returned one), never keep both. Diff the two derivations; if they reduce to the same expression over the same inputs, one must go.

- **Promise that wraps another promise** — `Promise.resolve(await x)` is just `x` (or `await x`).

- **Manual await-then-callback when the callee already accepts a callback:**
  ```ts
  // Bad
  const result = await runAsync(input)
  onSuccess?.(result)
  return result

  // Good
  return runAsync(input, { onSuccess })
  ```
  (Library-flavored example: a mutation hook that already accepts an `onSuccess` option in its call signature — awaiting the async variant and manually invoking the callback afterward is the same dead wrapper.)

**Legitimate wrappers (do NOT flag):**

- The wrapper adapts an argument shape the wrapped function does not natively support — e.g. `(opts) => fn(undefined, opts)` when the wrapped function normally expects a first positional argument. Real adaptation.
- The wrapper adds a transformation step — `(data) => fn(transformRequest(data))`.
- The wrapper adds a non-trivial default — `(opts = computedDefaults) => fn(opts)`. (`= {}` purely to allow destructuring is not a default.)
- The wrapper narrows a type the wrapped function cannot.
- The wrapper introduces a docstring or named identity at a re-export boundary that consumers depend on.

**How to spot one fast during review:** if the wrapper body is structurally identical to the call you'd write inline at the call site, the wrapper is dead. Apply the test: "what does this wrapper do that the wrapped thing does not?" If the answer is "nothing," delete.

## §S5. Lookup objects over switch/nested if

More than one level of `if` nesting in a single function is a smell. Prefer:
- Early-return guard clauses (`if (!x) return`)
- Extracting the inner branch to a named function
- A **named key/value lookup object** when the branch is selecting a value/component/config from a fixed set of cases

Avoid `switch` statements when the branches select a value — object lookups are clearer at a glance, exhaustive when typed properly, and trivial to extend. Name lookup objects `xxxMap`, `xxxConfig`, or `xxxLabels`, defined as `const` outside the component/function when the values are static.

Pattern (placeholder domain — one map per kind of selected value):

```ts
const someProviderFormMap = {
  [ProviderKind.A]: FormA,
  [ProviderKind.B]: FormB,
  [ProviderKind.C]: null
}
const FormComponent = someProviderFormMap[providerKind]
if (!FormComponent) return null
```

Note: pure styling values (e.g. picking a padding token) are not the right place for this pattern — inline them or use the design system's own scale. The lookup-object pattern is for selecting *behavior*: components, JSX, configs, permissions.

Two levels of `if` nesting is sometimes fine; three or more nearly always wants flattening.

**Checklist — walk it on every `switch` and every `if`/`else-if` chain in the diff. Not passing all boxes means the code failed review:**

- [ ] Does the branch just **select one value** (a component, JSX, config object, boolean, string, number) by a discriminator? If yes, it's a key/value lookup, not branching.
- [ ] **Differing per-branch interpolation or computed args is NOT an exemption.** Use a map of thunks (`Record<K, () => V>`), or compute the shared values once and use a map of objects. "Each branch builds its value a bit differently" is the rule's normal case, not a reason to keep the branching.
- [ ] A `default` / trailing `else` that returns a value → keep it as the map's fallback (`map[key] ?? fallback`), not a branch.
- [ ] More than one level of `if` nesting → flatten (guard clause, extracted function, or lookup).
- [ ] The branch genuinely does **divergent work** (side effects, early returns, several statements that aren't "produce one value") → branching is fine; say so in the finding so the reader knows it was considered, not missed.

**Deriving the lookup key from multiple booleans:** the lookup map is correct even when the key has to come from 2+ booleans, but the *key derivation itself* must not be a chained ternary. Break the chain into named single-level intermediates so each `?:` reads as one decision.

Bad — chained ternary collapses three branches into the key:
```ts
const mode = flagA ? 'a' : flagB ? 'b' : 'c'
const value = valueByMode[mode]
```

Good — each ternary is single-level via a named intermediate:
```ts
const innerMode = flagB ? 'b' : 'c'
const mode = flagA ? 'a' : innerMode
const value = valueByMode[mode]
```

**Fixing one violation must not introduce another.** When a reviewer flags the chained ternary, the wrong fixes are:
- Replacing the map with a helper function that has `if`-early-returns (abandons the lookup-object rule).
- Collapsing the map into an object-returning ternary chain (still a chained ternary, plus now also no map).
- Restructuring to ternary-of-objects so the parallel ternaries disappear (still chained, just at a different layer).

The map is the right shape. Only fix the key derivation: extract the inner branch to a named variable so no single line has more than one `?:`. Apply this principle generally — when correcting one violation, keep checking that the new shape doesn't trip a different rule.

## §S6. Code placement, general

Match the conventions already established in the directory the PR is touching:

- Side-effect calls (state updates, removals, setters) defined inside render JSX or inline map/filter callbacks usually want to live in a handler defined above the return, or inside the relevant hook.
- Helpers used in only one consumer live next to it; helpers used across consumers belong in a shared location matching the target repo's existing shared-code layout.

## §S7. JSDoc on exported APIs

Exported APIs carry doc comments so a consumer reading at the call site can hover and see what the thing does, what its parameters mean, and what it returns, without opening the source. Internal helpers used in only one file generally don't need it. Before flagging density on this box, grep the target repo to confirm it actually uses doc comments as a convention — don't impose the rule on a repo that doesn't.

**Where doc comments are expected:**
- Exported utility functions in shared helper locations.
- Exported custom hooks, whether shared or feature-scoped.
- Exported components, especially shared ones used across features.
- Exported types and props interfaces, particularly when the type name doesn't fully describe the shape.

**Standard tags:** parameter descriptions with type, return description, a component/type marker where the language convention supports one. Keep descriptions concise — one or two lines beats a paragraph.

**What to flag:**
- A new exported function, hook, or component with no doc comment at all.
- A new exported props/type interface where the field names aren't self-explanatory and there's no per-field description.
- A doc comment that just restates the function name (`/** Get the user. */` above `getUser()`) — the restates-the-name flag applies everywhere, regardless of what kind of unit it's on. Either deepen it or drop it.

**What NOT to flag:**
- Internal helpers (not exported, used in one file).
- Trivially-named exports where the name fully describes the behavior (`isProduction`, `EMPTY_ARRAY`).
- Existing files that already lack doc comments, if the PR isn't adding new exports there — retroactive additions are out of scope for a feature PR.

## §S8. Named exports for new modules

New files should use `export const Foo = …` / `export function foo` over `export default`. Existing `export default` declarations are fine — don't churn old code just for style. Framework-mandated default exports (route/page/layout files and any similar convention where the framework specifically reads `default`) are exempt; flag those as the only allowed defaults.

**Why named over default:**

1. **Refactor safety.** Renaming a named export forces every import site to update (a type error at each call site). Default imports invent a local name at every call site, so renaming the source doesn't propagate — different files end up with different local names pointing at the same value.
2. **Find-references in IDEs.** "Find all usages" works cleanly on a named export across the whole repo; on a default export, the search has to match arbitrary local names callers invented, which it can't.
3. **Auto-import.** Editors surface named exports cleanly with their canonical name; default exports either don't auto-suggest or suggest whatever name the editor inferred from the filename, which decays as files get renamed.
4. **Explicit API surface.** `export { Foo, fooHelper }` reads as a deliberate public contract. A default plus a stray named export muddles which is "the" thing in the file.
5. **Tree-shaking.** Named exports compose better with bundler dead-code elimination, which matters most for shared packages consumed by multiple apps.

**What to flag:**
- A new component / hook / util that exports `default` instead of a named const.
- A new app-level hook using `export default` because its siblings in the same folder are all default-export. Sibling defaults are exactly the "looks like conformance" trap this rule overrides — "the existing hooks here are default" is not a valid reason to keep the new one default. Flag it at the same weight as a new component.
- A default export in a file that already has named exports of related helpers (mixed signal — make all named).

**What NOT to flag:**
- Framework route files (page/layout/loading/error/not-found equivalents) that require `export default` by convention.
- Existing default exports on files not being substantively edited in this PR.
- Existing default-plus-named mixed files in a legacy area the PR isn't touching.

**One-line counter-example:**

Bad — new component file:
```ts
const Foo = (props: FooProps) => <div />
export default Foo
```

Good:
```ts
export const Foo = (props: FooProps) => <div />
```

The diff is one line, and from then on `Foo` is `Foo` everywhere.

**§S8.1 — inline `export const`, not a trailing `export { Foo }` block.** Even when the export is already named, prefer attaching `export` to the declaration over declaring `const Foo = …` then re-exporting it at the bottom of the file with `export { Foo }`. Both are named exports; the inline form keeps the export adjacent to the declaration instead of a redundant statement the reader has to scroll to find. A trailing `export { … }` block earns its place only when re-exporting from elsewhere or intentionally grouping several already-declared names together.

```ts
// Flag — declaration and export split across the file
const Foo = (props: FooProps) => <div />
// ...
export { Foo }

// Better — export on the declaration
export const Foo = (props: FooProps) => <div />
```

This is a nitpick-severity consistency item, not an §S8 failure (the export is already named). Flag it when a new file uses the trailing form, especially when several new sibling files all do.

## §S9. Fixed-value discriminators: string enums, not literal unions

When a field has a closed set of string values that gets compared and assigned at runtime (status, mode, kind, requirement, origin, vendor type, etc.), declare it as a string enum. This rule applies anywhere in the codebase the discriminator gets declared — shared model types, app-local types, feature-scoped types, or inline next to a component. The wire-format-vs-UI distinction governs whether something is a discriminator; the file location does not change the rule.

Placement: grep the target repo for sibling enums and match wherever it already keeps shared/serialized model types. A discriminator that mirrors a backend model/endpoint (its wire-value keys, statuses, etc.) belongs with the other model enums **even when it currently has a single consumer** — co-locating it in a hook file or a generic constants file is drift. "Only consumed here" is not an exemption for a wire-format type. As elsewhere, "following the same pattern as the adjacent file" only holds if that file follows the convention — if the adjacent file is itself the one-off that co-locates its enum, matching it just propagates the drift.

Bad:
```ts
export type SomeStatus = 'pending' | 'active' | 'archived'
```

Good:
```ts
export enum SomeStatus {
  PENDING = 'pending',
  ACTIVE = 'active',
  ARCHIVED = 'archived'
}
```

Naming:
- Enum identifier: PascalCase, named after the field's role (`SomeStatus`, `SomeKind`, `SomeRequirement`).
- Member keys: SCREAMING_SNAKE_CASE.
- String values: lowercase snake_case matching the backend serialization exactly (the wire format doesn't change when the frontend switches from union to enum).

Reasons:
1. **Codebase convention.** If every fixed-value discriminator in the shared model types is already an enum, a new literal-union type is inconsistent with the surrounding shape.
2. **Single source of truth.** Comparisons and assignments use `SomeStatus.PENDING` instead of `'pending'` repeated across files. Renaming a value is one edit at the enum instead of N find-replaces with the risk of touching an unrelated string.
3. **Typo-safety at call sites.** `'pendin'` (typo) typechecks fine against a bare `string` and only fails once widened to the union — and even then the error points at the call site, not the declaration. `SomeStatus.PENDIN` is a compile error at the typo itself, with autocomplete suggesting the right member.
4. **Discoverability.** Jump-to-definition on `SomeStatus.ACTIVE` lands on the enum declaration, which lists every legal value in one place. A union scattered across `=== 'active'` checks has no central documentation surface.
5. **Self-documenting at call sites.** `status === SomeStatus.ARCHIVED` reads as a domain check; `status === 'archived'` reads as a stringly-typed comparison and invites re-deriving the legal set from the comparison sites.

**The test for "is this a discriminator":** would the backend ever return this value? / does this represent a domain state? Yes → enum. No → it's genuinely local UI state and a literal union is fine.

**What to flag (anywhere in the diff):**
- A new `export type Foo = 'a' | 'b' | 'c'` (or in-file `type Foo = ...`) where the values look like serialized backend states (snake_case strings, statuses, modes, kinds, vendor types). Fix: convert to an enum at the declaration site.
- An inline literal union on a component prop or function parameter when the same value set already exists on a serialized model. Fix: type the prop against the existing enum instead of duplicating the union.
- Comparisons or defaults that still use raw string literals (`status === 'pending'`, `default = 'pay_later'`) when an enum already exists for that field. Fix: `Status.PENDING` / `Status.PAY_LATER`.
- A backend-model/endpoint enum declared inside a hook file or a generic constants file. Fix: move it next to the other model enums for that model, following the target repo's existing placement — single consumer is not an exemption.

**What NOT to flag:**
- One-off literal unions where the value space is genuinely local UI state (variant strings like `'minimal' | 'full'`, a UI-library prop union, drawer sizes). Apply the backend-value test above.
- Pre-existing literal unions the PR doesn't substantively edit. Adding a member to an existing union is acceptable; introducing a brand-new union for a serialized value is not.
