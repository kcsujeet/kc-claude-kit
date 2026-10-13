---
name: structure
description: "Code placement and module-shape conventions for TypeScript, JavaScript and other source files: one responsibility per unit, co-location and promotion, flattened single-file folders, no barrels, no dead wrappers, lookup objects over switch and nested if, named exports, JSDoc on exports, string enums for serialized discriminators, breaking changes, misplaced modules, public exports, what a module exports, one component per file, and routes-only `app/` folders. Use when writing or reviewing code that adds, moves or exports a file, function, hook or type, or that branches on a discriminator."
user-invocable: false
paths:
  - "**/*.{ts,tsx,js,jsx,mjs,cjs,rb,py,swift,go,java,kt,php,cs,rs}"
---

# Structure

## Contents

- Rules
- Review checklist
- Review detail
  - §S1. Separation of concerns
  - §S2. Code placement and co-location
  - §S3. Flatten single-file folders; no re-export barrels
  - §S4. No dead wrappers
  - §S5. Lookup objects over switch/nested if
  - §S6. Code placement, general
  - §S7, §S8, §S10, §S12, §S13. Exports and public API (in `references/exports.md`)
  - §S9. Fixed-value discriminators: string enums, not literal unions
  - §S11. Misplaced-modules sweep
  - §S14. New code acts on its home's subject
  - §S15. One exported component per file
  - §S16. `app/` holds routes only
- Sweeps

## Rules

Where code lives is part of its contract. A path promises something about what is inside it.

- One observable responsibility per unit. A directory name is a promise: `hooks/` contains hooks, `utils/` contains pure functions.
- Co-locate with the single consumer. Promote at the second consumer: within a feature, to the nearest common ancestor; across features, to the shared app level, never sideways into another feature.
- Flatten a folder that holds one file. `Foo/Foo.tsx` with no siblings is just `Foo.tsx`.
- No barrel re-export files. Import the module path directly, which also keeps tree shaking working. A barrel for a single component is fine.
- Named exports on new files, declared inline (`export const foo = ...`), not collected in a trailing export block.
- Delete dead wrappers in every shape: async-await passthrough, destructure-and-reconstruct, single-use alias, identity transform, a Promise wrapped around a Promise, a hook returning another hook's values unchanged, a wrapper whose only addition is an `onSuccess` every caller could pass itself.
- A module exports the thing it is named for plus its own surface (its props, argument and return types). An unrelated export, such as a domain enum in a hook file, moves to where its consumers are; a type only this module uses stays.
- New code acts on its home's subject. A method added to the order module creates, reads or changes orders; one that only prices a cart belongs with the cart.
- One exported component per file. Its hooks and helpers move to their own files, and a subcomponent with one consumer stays private in that consumer's file.
- A lookup object beats a `switch` or an `if` chain that maps a key to a value. Use thunks when the branches need per-branch work.
- Exported APIs carry a short doc comment saying what they are for, not restating the signature.
- Do not widen a package's public exports so a sibling package can reach an internal. Move the shared piece to a shared layer both consume.
- A discriminator the backend serializes is a string enum, not a literal union: if the backend can return it, it needs a name in the code.

### React and TypeScript codebases

**Bulletproof-react is the canonical source for placement**: https://github.com/alan2207/bulletproof-react/blob/master/docs/project-structure.md

Where anything above appears to disagree with it, that document wins and this file is the one to correct.

- Feature code lives under `features/<feature>/{api,components,hooks,stores,types,utils}`, including only the subfolders that feature actually needs.
- Shared code lives at the app level: `components/`, `hooks/`, `utils/`, `types/`, `stores/`, `lib/`, `config/`.
- No cross-feature imports. Two features that need the same thing compose at the app level, or the shared thing moves up.
- Dependencies flow one way: shared can be used anywhere, features import only from shared, the app imports from both.
- `app/` is the routing layer: route files, their tests and route-level actions, plus the app's own entry, provider and router. Components, hooks and utils go to the shared folders or a feature, never beside a route.
- Its guidance on barrel files matches the rule above: barrels were once recommended per feature and no longer are, because they break tree shaking. Import files directly.

Apply this to a repo that already uses a feature-based layout or is migrating to one. In a legacy flat layout, do not demand a migration as a side effect of unrelated work; just avoid making the existing structure more inconsistent than it already is.

Detection criteria and per-box review failure modes live in the `## Review checklist` of the `structure` skill (`conventions:structure`) and of the `react` skill, with the detail under each one's `## Review detail`. These rules are the statement of the convention; those checklists are how a diff gets graded against it.

## Review checklist

The structure gate agent ticks every box below against the diff. A box is FAIL if any matching construct in the diff violates the rule; the gate is FAIL if any box is FAIL. Mark a box N/A only when the diff has no matching construct (state which).

- [ ] §S1 Separation of concerns: each unit (function, hook, component, module) has one observable responsibility; no data-reading unit also bundles a selector, formatter, or mutation; no util silently performs a side effect. (N/A: no multi-responsibility unit added)
- [ ] §S2 Co-location/promotion: single-consumer code stays next to its consumer; multi-consumer code sits at the consumers' nearest common ancestor judged by scope/coupling, not raw count; view-local helpers are promoted only when a real external consumer appears (YAGNI-gated), not on speculation; inherently-shared-layer code is placed in its shared layer from day one regardless of current consumer count. (N/A: no files moved/added)
- [ ] §S3 Single-file folders are flattened; no `export { default } from './X'` re-export barrels. (N/A: no folders/barrels touched)
- [ ] §S4 No dead wrappers: single-item array wrap-then-spread, no-op async passthroughs, argument destructure-and-reconstruct passthroughs, single-use const aliases, verbatim object-spread, a producer value the consumer independently re-derives, promise-wrapping-a-promise, manual await-then-callback when the callee already accepts a callback, a hook or function returning an inner call's values unchanged (**enumerate**: for every changed hook, list the keys it returns and the keys it takes from inner hook calls; a key in both lists, untouched, is a passthrough), a wrapper whose only addition is an `onSuccess` or similar callback every caller could pass itself. (N/A: none added)
- [ ] §S5 Lookup objects over `switch`/nested `if`: branch-selecting-a-value uses a named map, not a switch or if/else-if chain; differing per-branch computation is handled with a thunk map, not treated as an exemption; a trailing default/else becomes the map's fallback; more than one level of `if` nesting is flattened; the branch key, if derived from multiple booleans, is built from named single-level intermediates, never a chained ternary; a fix for one violation here doesn't introduce another (e.g. replacing the map with an if-early-return helper); map entries are plain values unless a value closes over a per-call argument or must be lazy, and the map is typed so its fallback is justified; every `switch`, `else if`, and value IIFE in the added lines (`switch-else-if-iife.sh`), and every nested `if` the indentation scan reports (`nested-ifs.sh`), is enumerated with a verdict. (N/A: only when both sweeps return 0 hits, stated as `grepped switch/else-if/IIFE: 0 hits` and `nested-if scan: 0 hits`)
- [ ] §S6 Helpers placed by consumer count: a helper with exactly one consumer is not pulled into its own subfolder; a helper with two or more consumers is not left stranded in one consumer's local folder. (N/A: no helper added)
- [ ] §S7 JSDoc on every new exported function, hook, component, and props/type interface, unless the name is fully self-explanatory; no JSDoc that merely restates the name. (N/A: no new exported API, or target repo doesn't use doc comments — confirm by grep before marking N/A)
- [ ] §S8 New files use named exports (`export const Foo`), inline on the declaration, not `export default` and not a trailing `export { Foo }` block; sibling default-exported files are not an exemption; framework-mandated default exports (route/page/layout files and equivalents) are exempt; a new `export` on a constant/helper that nothing outside the file references is itself a finding — grep to confirm nothing imports it. (N/A: no new module)
- [ ] §S9 Fixed-value discriminators that get serialized/compared at runtime (status, mode, kind, origin, vendor type, etc.) are TypeScript string enums, not string-literal unions; placement matches wherever the target repo already keeps sibling enums. (N/A: no new status/mode/kind field)
- [ ] §S10 Breaking changes are named: a removed or renamed export, a changed prop or parameter shape on a shared component or exported function, and a field removed from (or made required on) an exported type are each identified as breaking, every importer is grepped and cited, and the finding stands even when the PR description says the change is not breaking. (N/A: no exported symbol, shared component signature, or exported type changed)
- [ ] §S11 No context, hook, or pure helper in a components folder: the misplaced-modules sweep (`misplaced-modules.sh`) ran over every changed AND untracked file, and each hit (a `createContext(` module, a hook file, a non-component module under a components folder) has a verdict naming its type-correct destination. (N/A: only when the sweep returns 0 hits, stated as `misplaced-modules sweep: 0 hits`)
- [ ] §S12 No package's public exports are widened only so a sibling package can reuse an internal: when a new export on a package's public entry point exists for another package in the same repo to import an implementation detail, the shared piece moves to a shared package or layer instead. (N/A: no new public-entry export consumed by another package in the repo)
- [ ] §S13 A module exports what it is named for: for every changed module (hooks, components, utils, constants, types, api modules), every export gets a verdict of `own-surface` (the named thing plus its props, argument and return types, or a one-off local constant) or `misplaced` (a domain enum or wire value in a hook file, a pure helper in a types file, a domain type in a utils file). Only `misplaced` is a finding, and it names the destination by §S2. A locally used type or constant flagged only for living in the file is itself a FAIL, so each verdict states the scope test's answer. **Enumerate**: list every export per changed module. (N/A: no export added or changed)
- [ ] §S14 New code belongs where it is put: for every new member (a method on a module, a hook, a type, a constant, a file), the name of its home and the members already there were read, and the new code acts on that same subject. Code that only borrows the home's inputs or helpers without acting on its subject FAILS, and the finding names where it belongs. Matching a backend route that is itself misplaced is not a pass; flag both. (N/A: no new member added)
- [ ] §S15 One exported component per file: no new or changed component file exports more than one component (**enumerate**: count the exported components in every changed component file, one verdict per file with its count). Its other exports (hooks, helpers, shared style constants) move out to their own files, placed by §S2 and §S11, a subcomponent with one consumer stays private in that consumer's file, and no new file only wraps one value or element. (N/A: no changed file exports a component)
- [ ] §S16 `app/` holds routes only: every new file under the routing layer (`app/`, or the repo's equivalent) is a route file the framework reads by name, a test for one, a route-level action, or the app's own entry, provider or router; a component, hook, util or constant there FAILS, even beside existing ones, since precedent is not an exemption. **Enumerate**: list every new file under it with a verdict. (N/A: no new file under the routing layer)

## Review detail

Code-placement and API-shape rules for the diff under review. Covers sixteen independent failure modes: mixed responsibilities inside one unit, wrong-layer co-location, leftover single-file folders and re-export barrels, dead wrappers, branch-selection that should be a lookup, misplaced helpers, missing JSDoc on exported APIs, default exports on new files, literal unions standing in for serialized enums, unflagged breaking changes to a public API, modules sitting in a folder that promises a different kind of module, public exports widened only to share an internal, exports unrelated to their module, new code placed in a home whose subject it does not act on, files exporting several components, and non-route files in the routing layer.

### §S1. Separation of concerns

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

### §S2. Code placement and co-location

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

**Cross-feature imports** (one feature importing directly from another feature's internals) are a placement smell in any codebase organized by feature — compose at a shared layer instead (boxed in the `react` skill, §R2, for React/TS diffs; for non-React code organized by feature folders, raise it under §S2 with the same compose-at-the-top fix).

### §S3. Flatten single-file folders; no re-export barrels

**Single-file folders: flatten.** A folder containing exactly one file (no sub-components, no co-located hook, no helpers, no styles, no test) is dead structure — drop the folder, leave the file at the parent level. The folder earns its place the moment a second file appears alongside.

**No `export { default } from './X'` re-export barrels.** A single-item `index.ts` that exists only to shorten an import path adds no value: it perpetuates the default-export anti-pattern (§S8) and the importer can resolve the actual file directly with one extra path segment. Either flatten the folder or have the importer reach the file directly. This is distinct from a real barrel that groups several already-declared named exports with intent — that earns its place; a barrel whose sole content is one re-exported default does not.

### §S4. No dead wrappers

If a wrapper adds no semantic value over the thing it wraps, drop it and use the wrapped value directly. Wrappers earn their place by adding a transformation, a type narrowing, a side effect, a default, or documentation that the wrapped thing cannot provide on its own. A side effect every caller could attach itself (an `onSuccess` callback) does not count. If you cannot name what the wrapper adds, it is dead.

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

- **A hook or function that returns an inner call's values unchanged:**
  ```ts
  // Bad: three keys come straight from useWidgetQuery and are returned untouched
  const { widget, isLoading, refetch } = useWidgetQuery(widgetId)
  return { widget, isLoading, refetch, total: getWidgetTotal(widget) }

  // Good: the consumer calls useWidgetQuery itself, or the hook spreads it
  const widgetQuery = useWidgetQuery(widgetId)
  return { ...widgetQuery, total: getWidgetTotal(widgetQuery.widget) }
  ```
  Re-listing the keys by hand is what lets the surface drift: a key stops being read and nothing says so. The same goes for a value read from a context or settings hook and returned unchanged; the consumer can call that hook too. Enumerate it: per changed hook, the keys returned against the keys taken from inner calls.

- **A wrapper whose only addition is a callback every caller could pass:**
  ```ts
  // Bad: each method is `updateWidgetMutation.mutate(widget, { onSuccess: refreshList })`
  const { updateWidget } = useWidgetListActions()

  // Good: the call site passes the callback
  updateWidgetMutation.mutate(widget, { onSuccess: refreshList })
  ```
  The callback is a side effect, but attaching one is something every caller can already do, so a wrapper that exists only for it is dead.

**Legitimate wrappers (do NOT flag):**

- The wrapper adapts an argument shape the wrapped function does not natively support — e.g. `(opts) => fn(undefined, opts)` when the wrapped function normally expects a first positional argument. Real adaptation.
- The wrapper adds a transformation step — `(data) => fn(transformRequest(data))`.
- The wrapper adds a non-trivial default — `(opts = computedDefaults) => fn(opts)`. (`= {}` purely to allow destructuring is not a default.)
- The wrapper narrows a type the wrapped function cannot.
- The wrapper introduces a docstring or named identity at a re-export boundary that consumers depend on.
- A named intermediate that describes a computed value for readability (a named branch or clause); see clarity §C18. Only an alias that renames one existing identifier with nothing added is dead.

**How to spot one fast during review:** if the wrapper body is structurally identical to the call you'd write inline at the call site, the wrapper is dead. Apply the test: "what does this wrapper do that the wrapped thing does not?" If the answer is "nothing," delete.

### §S5. Lookup objects over switch/nested if

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

An `if` directly inside another `if` can stay; a third level (an `if` inside that) gets flattened.

**Checklist — walk it on every `switch` and every `if`/`else-if` chain in the diff. Not passing all boxes means the code failed review:**

- [ ] Does the branch just **select one value** (a component, JSX, config object, boolean, string, number) by a discriminator? If yes, it's a key/value lookup, not branching.
- [ ] **Differing per-branch interpolation or computed args is NOT an exemption.** Use a map of thunks (`Record<K, () => V>`), or compute the shared values once and use a map of objects. "Each branch builds its value a bit differently" is the rule's normal case, not a reason to keep the branching.
- [ ] A `default` / trailing `else` that returns a value → keep it as the map's fallback (`map[key] ?? fallback`), not a branch.
- [ ] More than one level of `if` nesting → flatten (guard clause, extracted function, or lookup).
- [ ] The branch genuinely does **divergent work** (side effects, early returns, several statements that aren't "produce one value") → branching is fine; say so in the finding so the reader knows it was considered, not missed.

**Map entries are plain values by default.** Strings, numbers, config objects, and JSX elements (an element is a cheap descriptor, not a render) go straight into the map. Wrap an entry in `() =>` only when the value closes over a per-call argument, or must be lazy because building it is expensive or has side effects; an unneeded thunk is itself a dead wrapper (§S4). Type the map as `Partial<Record<Key, Value>>` when not every key has an entry, so the `?? fallback` at the lookup is justified by the type rather than defensive.

```ts
// Flag: thunks around values that need no argument and are cheap
const titleByView: Record<View, () => string> = { [View.LIST]: () => 'Widgets', [View.GRID]: () => 'Gallery' }

// Prefer: plain values, with the fallback typed in
const titleByView: Partial<Record<View, string>> = { [View.LIST]: 'Widgets', [View.GRID]: 'Gallery' }
const title = titleByView[view] ?? DEFAULT_TITLE
```

**Enumerate chains and nesting by grep, do not eyeball.** Run the `switch-else-if-iife.sh` sweep (see Sweeps): over the diff's added lines, it lists every `switch`, every `else if`, and every IIFE assigned to a value (an IIFE that picks one value from a discriminant is a `switch` in disguise).

Nesting is not visible in added lines alone, so the `nested-ifs.sh` sweep scans the changed files themselves, as checked out in the repo root, with an indentation-aware pass: it reports an `if` opened while an `if` or `else` block at a lower indent is still open, and treats `else if` at the same indent as a sibling, not nesting. It prints only the nested `if` lines the diff adds.


The scan is indentation-based, so it is a candidate generator: open each hit, confirm it is a real nesting in a changed region, and give it a verdict against the nesting rule above. It also under-matches (a nested `if` on the same line as its parent, code not indented by the formatter), so still read each changed function's control flow. For another language (`elif`, `case`/`when`, `match`), adapt both patterns and run them by hand, and state which scripts and patterns were run. Print `grepped switch/else-if/IIFE: N hits` and `nested-if scan: N hits`, with `0 hits` stated explicitly.

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

### §S6. Code placement, general

Match the conventions already established in the directory the PR is touching:

- Side-effect calls (state updates, removals, setters) defined inside render JSX or inline map/filter callbacks usually want to live in a handler defined above the return, or inside the relevant hook.
- Helpers used in only one consumer live next to it; helpers used across consumers belong in a shared location matching the target repo's existing shared-code layout.

### §S7, §S8, §S10, §S12, §S13. Exports and public API

The detail for these five boxes (doc comments on exports, named and unnecessary exports, breaking changes, public exports widened for a sibling package, and what a module exports) is in `${CLAUDE_PLUGIN_ROOT}/skills/structure/references/exports.md`. Read it in full before grading any of them.

### §S9. Fixed-value discriminators: string enums, not literal unions

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

### §S11. Misplaced-modules sweep

§S1 says the directory is part of the contract. This box enforces it mechanically for the most common miss: a context, hook, or pure helper created inside a components folder because that is where the author was working. Run it over every changed file AND every untracked file, since a newly created misplaced file is the usual case and is not in `git diff` until it is added: the `misplaced-modules.sh` sweep (see Sweeps) does both when run from the repo root. It reports a `createContext(` call under a components folder (belongs with contexts or stores), a hook file there (belongs with hooks), and a non-component `.ts`/`.js` module there (likely a util, type, or context).

If the target repo's layout uses other folder names or extensions (grep where its contexts, hooks, and utils already live), adapt the checks and run them by hand as well. Every hit is a candidate: open the file, confirm what it exports, and name the destination the repo already uses for that kind of module. Print `misplaced-modules sweep: N hits`, with `0 hits` stated explicitly.

### §S14. New code acts on its home's subject

A home (a module, a resource, a folder, a file) is named for one subject, and its members act on it. Before accepting a new member, read the home's name and the members already there, and confirm the new code acts on that same thing. Code that only borrows the home's inputs or helpers belongs elsewhere: a `previewTotals` method added to the order module that creates no order and only prices a cart belongs with the cart. Following the backend's route is not a pass: if the route is misplaced too, flag both.

### §S15. One exported component per file

A component file that exports several components (or exports cells, hooks and style constants so another component can reuse them) is the usual result of a refactor, not of a new file. Split it by kind, the way the repo already places each kind:

- each exported component gets its own file, named after it; the files can share a folder named after the parent component (`widget-table/widget-table.tsx`, `widget-table/widget-table-head.tsx`), imported by path with no barrel (§S3);
- hooks and helpers move out of the component file into their own files, placed by §S2 and §S11;
- a subcomponent with a single consumer stays private in that consumer's file;
- no thin file: a component that only wraps one value or element is inlined where it is used.

### §S16. `app/` holds routes only

In a bulletproof-react layout, `app/` is the routing layer: route files the framework reads by name (`page`, `layout`, `route` and equivalents), their tests, route-level actions, and the app's entry, provider and router. Routes compose pieces from the shared folders and `features/`. A component or hook placed beside a page is not reachable by URL, so nothing breaks, but the route folder quietly becomes a feature folder nothing else can reuse from:

```
app/widgets/
  page.tsx                 // fine: the route
  page.test.tsx            // fine: the route's test
  widget-cards.tsx         // FAIL: a component; belongs in features/widgets/components/
  use-widget-summary.ts    // FAIL: a hook; belongs in features/widgets/hooks/
```

A new file added beside legacy helpers that already sit there still fails: moving the old ones is out of scope, but the new one starts outside `app/`.

## Sweeps

Save the diff under review to a file (`gh pr diff <num> > /tmp/review.diff`, or `git diff <default-branch>...HEAD > /tmp/review.diff`) and run each script over it; `-` reads the diff from stdin. Each prints one `path:line: text` hit per line, where `line` is the new-side line number, and nothing else. Give every hit its own verdict, and state each receipt with its count, `0 hits` included.

- `added-lines.sh` (citation map): every added line as `path:line: text`, with the source line number at the head SHA. Cite every finding's line from this output or from a sweep hit, never from a position in the diff file.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/added-lines.sh" <diff-file>
  ```

- `switch-else-if-iife.sh` (§S5): added lines holding a `switch`, an `else if`, or an IIFE assigned to a value. Receipt: `grepped switch/else-if/IIFE: N hits`.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/skills/structure/scripts/switch-else-if-iife.sh" <diff-file>
  ```

- `nested-ifs.sh` (§S5): nested `if` statements on added lines, found by an indentation scan of each changed file. It reads the files, so run it from the repo root with the diff's new side checked out, or pass the root as a second argument. Receipt: `nested-if scan: N hits`.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/skills/structure/scripts/nested-ifs.sh" <diff-file>
  ```

- `misplaced-modules.sh` (§S11): a context, hook, or non-component module under a components folder, over every changed and untracked file. It reads the files and `git ls-files`, so run it from the repo root, or pass the root as a second argument. A file-level hit is reported at line 1 with its reason in place of the line text. Receipt: `misplaced-modules sweep: N hits`.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/skills/structure/scripts/misplaced-modules.sh" <diff-file>
  ```
