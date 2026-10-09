---
name: react
description: "React conventions for .tsx and .jsx components, hooks and API modules: component and markup structure, keys, conditional rendering, data-fetching hooks and cache updates, forms as the source of truth, state placement, memoization, render cost, layout at narrow widths, and `ref` as a prop on React 19. Use when writing or reviewing React components, hooks, queries, mutations, forms or layout CSS."
user-invocable: false
paths:
  - "**/*.{tsx,jsx}"
  - "**/hooks/**/*.{ts,js}"
  - "**/api/**/*.{ts,js}"
---

# React

## Contents

- Rules
- Review checklist
- Review detail
  - Section 1: Project structure (bulletproof-react)
  - Section 2: Components & JSX
  - Section 3: Data fetching (in `references/data-fetching.md`)
  - Section 4: Forms (in `references/forms.md`)
  - Section 5: State
  - Section 6: Render cost and layout
- Sweeps

## Rules

Placement is covered by the `structure` skill, which defers to bulletproof-react. This file is everything else: how components, data access, forms and state are built.

### Components and markup

- A component owns its own container. It never leaves a required wrapper to the caller, and never sets root `size`, `flexGrow` or self-margins that only work under one particular parent.
- Conditional element assembly is a named local component with early returns, not a `let` reassigned through `if/else` and not a multi-line ternary building markup inline.
- Three or more structurally identical sibling blocks that differ only by data become a map over an array, with stable keys.
- No index as a key for anything reorderable, and never mix indices taken from a filtered list with an unfiltered one.
- No side-effect-only component: a `useEffect` with `return null` is a hook or an HOC, not a component.
- No `renderSomething()` inline render functions, and no skipping items by returning null from a ternary inside a map. Filter first.
- Assign a hook result to a variable, then derive on the next line. Never inline a selector or subscription inside a transforming expression.
- Do not reach for `useMemo` or `useCallback` by default when the project runs React Compiler. Write the plain value or function.
- Without React Compiler, a `useMemo` or `useCallback` has to hit: empty dependencies mean a module constant, and a dependency that changes every render (an inline object, array or function) means the memo never does. Pass stable references to memoized children.
- A block of markup past about thirty lines that reads as its own unit is a named component, and a wrapper element that only repeats its parent's styling is deleted.
- On React 19 and later, `ref` is a plain prop. Do not add `forwardRef`, and never declare `ref` in the props of a component that is also wrapped in `forwardRef`.

### Data access

- Reads and writes live in separate hooks. A component contains no raw `fetch`, no `axios`, no direct `useQuery` or `useMutation` call; grep how the sibling features do it and follow that.
- The fetch lives with the actual consumer. A page does not duplicate a fetch its child already owns, especially with different params, and nothing fetches a whole list to derive one boolean.
- After a write, patch the cache first, then update surgically, and invalidate only as a last resort.
- Prefer `mutate` with callbacks over `mutateAsync` with `await` when the resolved value only drives a side effect.
- A request's method matches its effect: a read uses GET unless its input cannot fit in a query string.
- A cache patch or invalidation targets the narrowest key that shows the change.
- A write hook touches only its own resource. Another resource's writes live in that resource's hook, and the caller composes the two.
- A read hook wires up every option it accepts. Accepting an option and ignoring it is dead surface.

### Forms and state

- The form is the single source of truth. No `useState` shadowing a value the form already holds.
- A form-state hook returns form plumbing only (the methods, submit and discard, saving state). One field's fetching, watching and lookup state live in that field's component.
- Each form watch lives in the smallest component that renders from it; a child reads shared form values itself rather than taking them as props.
- A form that edits a record seeds the related record its inputs render from, not just the id.
- Check the validation library's own API before hand-rolling a check, a regex, or a coercion. Most of them already exist there.
- New state lives at the lowest common ancestor of its actual consumers, never lifted because a parent might want it later.
- Two state updates whose order matters carry a one-line comment at the call site saying why.
- A child that needs two or more props derived from one hook the parent called should call the hook itself.

Detection criteria and per-box review failure modes live in the `## Review checklist` of the `react` skill (`conventions:react`), with the detail under its `## Review detail`. These rules are the statement of the convention; that checklist is how a diff gets graded against it.

## Review checklist

The react gate agent ticks every box against the diff. A box is FAIL if any matching construct in the new code violates the rule; the gate is FAIL if any box is FAIL. Mark a box N/A only when the diff has no matching construct. The whole gate is N/A only when the diff contains no React/JSX UI code (state that).

- [ ] §R1 Bulletproof-react placement: new feature code sits under `features/<feature>/{api,components,hooks,...}` (only needed subfolders); cross-feature-consumed code sits at the shared app level. (N/A: target repo doesn't use/isn't migrating to a feature-based layout — grep for `src/features/` first — or no files added/moved)
- [ ] §R2 No cross-feature imports (`features/A` importing from `features/B`'s internals); composition happens at the app/routes level. (N/A: no feature-to-feature import in diff)
- [ ] §R3 React keys/indices correct: no index key for reorderable items, no mixed filtered/unfiltered indices, no redundant `indexOf` after a `find`. (N/A: no keyed list in diff)
- [ ] §R4 No vestigial aliases left over from a simplification. (N/A: none in diff)
- [ ] §R5 No prop drilling / too-many-props where a child could read the same hook directly (2+ props derived from one context/hook the parent fetched). (N/A: no matching prop shape)
- [ ] §R6 Repeated sibling JSX (3+ structurally identical blocks differing only by data) is mapped from an array, with a stable key. (N/A: fewer than 3 repeated blocks)
- [ ] §R7 Hook-call assignments are pure: a subscription/selector result is assigned to a variable, then derived on the next line, never inlined inside a transforming expression. (N/A: no such hook call)
- [ ] §R8 A layout component owns its own container (doesn't leave a required wrapper to the caller); no component assumes how its parent uses it (root props/margins that only work under one specific ancestor). (N/A: no such component added)
- [ ] §R9 Conditional element assembly is a named local component with early returns, not a `let`-then-`if/else` block or a multi-line/non-trivial-branch ternary building JSX inline. (N/A: no conditional element-building in diff, or only a trivial single-line ternary / `{cond && <X/>}` guard)
- [ ] §R10 No side-effect-only component (`useEffect` + `return null`) — blocker; no skip-via-ternary in map callbacks; no `renderXxx()` inline render-function pattern. (N/A: none of the three constructs in diff)
- [ ] §R11 Reads and writes live in separate hooks; no raw `fetch`/`axios`/`useMutation`/`useQuery` call inside a component — grep how sibling features do it. (N/A: no data call in diff)
- [ ] §R12 Fetch ownership re-evaluated for every read hook added/moved: the fetch lives with the actual consumer; a parent/page doesn't duplicate a fetch its child already owns (especially with different params); no full-list fetch added only to derive a boolean. (N/A: no read hook added/moved)
- [ ] §R13 Query invalidation is a last resort (cache-patch → surgical update → invalidate, in that order); `mutate` + callbacks preferred over `mutateAsync` + `await` when the resolved value only drives a side effect; mechanical sweep — run `mutate-async.sh` over the diff's added lines, give every hit a verdict, state `grepped mutateAsync: 0 hits` explicitly when none found. (N/A: no invalidation or mutation in diff)
- [ ] §R14 Form is the single source of truth (no `useState` shadowing a form-held value); hand-rolled validation checks/regex/coercions are confirmed against the validation library's own API before being kept. (N/A: no form or schema in diff)
- [ ] §R15 New component state lives at the lowest common ancestor of its actual consumers, never lifted because a parent "might" want it; order-dependent multi-step state mutations (`update` then `remove`, `setX` then `setY` where order matters) carry a rationale comment at the call site. (N/A: no state added or edited in diff)
- [ ] §R16 Every new `useMemo`/`useCallback` earns its place: empty deps with no input from component scope means a module constant (hoist it); a dependency that changes every render (an inline object, array, or function, a fresh instance) means the cache never hits (drop the memo or stabilize the dep); the finding states which. **Enumerate with the `memo-hooks.sh` sweep** (see §R16). (N/A: `memo-hooks.sh` returns 0 hits, stated as `grepped memo hooks: 0 hits`; or the project runs React Compiler, confirmed by grepping its build config)
- [ ] §R17 No wasted render work: a memo, effect, or loop whose result is unused in the current mode is guarded out; an inline object or callback passed to a memoized child, or into a dependency array, is stabilized; dependency arrays list the underlying data, not a function reference whose identity changes; a value already memoized is not recomputed elsewhere. (N/A: no hook dependency array, memoized child, or mode-dependent computation in diff)
- [ ] §R18 A JSX block past roughly 30 lines that reads as its own unit is a named component; no wrapper element that only repeats its parent's styling or adds nothing to layout. (N/A: no JSX block over 30 lines and no wrapper element added)
- [ ] §R19 A change to width, height, min/max sizing, flex/grid layout, or positioning is checked at 375, 600, 768, and 1024 px: the usable width per column or cell after padding is computed or measured at each, and the numbers appear in the finding; removing a minimum-size floor without a responsive fallback FAILS. (N/A: no CSS or layout change in diff)
- [ ] §R20 On React 19 or later, `ref` is a plain prop: no new `forwardRef`, and no props type declaring `ref` on a component also wrapped in `forwardRef` (the declaration is unreachable). **Enumerate**: grep the changed files for `forwardRef`, one verdict per hit; a `forwardRef` in an existing file the diff touches is a FAIL at nitpick weight. (N/A: the project's React version is below 19, confirmed from its manifest, or `grepped forwardRef: 0 hits`)
- [ ] §R21 A request's method matches its effect: a new request that only reads and saves nothing uses GET; a read hook whose request is POST, PUT or PATCH FAILS unless the input genuinely cannot fit in a query string, and a comment at the request says so. (N/A: no new request)
- [ ] §R22 A cache patch or invalidation targets the narrowest key that shows the change: an update to one record patches that record's own key when that is where it shows, and a broad base key is used only when lists showing the same record need it too, with a comment saying so. (N/A: no cache patch or invalidation added)
- [ ] §R23 A write hook touches only its own resource: it imports no other resource's requests or hooks. A write to another resource lives in that resource's write hook, and the caller composes the two, updating its own cached data in the call's `onSuccess`. (N/A: no write hook added or edited)
- [ ] §R24 A form-state hook returns form plumbing only (form methods, submit and discard, saving state). One that returns field data or field handlers (options, a lookup function, a pick handler) FAILS; that logic lives in the field's own component, or the form component when small. (N/A: no form added or edited)
- [ ] §R25 Each form watch (and each piece of field state) lives in the smallest component that renders from it; a child reads shared form values through the form context instead of the parent watching them and passing them down. A watch in the form or its setup hook FAILS unless that component renders from the value too. (N/A: no watch or field state added in a form)
- [ ] §R26 A form that edits an existing record seeds the related record its inputs render from (`owner_id` and `owner`), not just the id, and no picker gets a label prop hand-built from a record the form already holds. (N/A: no form editing an existing record)
- [ ] §R27 A read hook accepts the repo's standard read-hook options (extended with its own fields, not a re-declared subset) and wires every option it accepts; an accepted option the hook never reads FAILS. (N/A: no read hook added or edited)

## Review detail

Project-structure, component/JSX, data-fetching, form, and state-placement conventions for React/JSX UI code. Covers twenty-seven independent failure modes across six areas: where code lives (bulletproof-react), how components and markup are structured, how reads/writes are split and owned, how forms hold state, where new component state itself lives, and what renders cost and how layout holds up at narrow widths.

---

### Section 1 — Project structure (bulletproof-react)

Reference: https://github.com/alan2207/bulletproof-react/blob/master/docs/project-structure.md

#### §R1. Feature-based layout, shared code at the app level

```
src/
├── components/, hooks/, utils/, types/, stores/, lib/, config/   (shared, cross-feature)
└── features/<feature>/
    ├── api/         - data hooks / API contract for this feature
    ├── components/  - feature-scoped components
    ├── hooks/       - feature-scoped hooks
    ├── stores/      - feature-specific state
    ├── types/       - feature-specific types
    └── utils/       - feature-specific utils
```

Only the subfolders a feature actually needs — don't scaffold empty ones. Code consumed by 2+ features is not feature-scoped; it belongs at the shared app level (`src/hooks/`, `src/utils/`, etc.), never duplicated into each feature.

**Unidirectional flow: shared → features → app.** Shared code never imports from a feature — that inverts the dependency direction and makes "shared" a lie. `app`/route-level code may import from features and shared; features may import from shared; shared imports nothing above it.

**Applicability guard (this box's N/A condition):** enforce this only when the target repo already follows, or is actively migrating to, a feature-based structure — grep for `src/features/` first. In a legacy flat layout (`src/components/`, `src/hooks/` at the top level, no `features/`), don't demand a bulletproof migration inside an unrelated feature PR; flag only a placement that makes the existing layout *more* inconsistent than it already is (e.g. a new resource split across two different conventions in the same PR).

```
// Flag: new feature file placed at the shared app level for no reason
src/hooks/useWidgetPricing.ts       // only WidgetPanel (in features/widgets) consumes it

// Better: feature-scoped
src/features/widgets/hooks/useWidgetPricing.ts
```

#### §R2. No cross-feature imports

`features/A` importing a component, hook, or type from inside `features/B` couples two areas that should be independently deletable/replaceable. Compose at the app/routes level instead: the page/route file imports from both features and wires them together, or the shared piece moves to the app-level shared folder.

```
// Flag
import { useOtherFeatureThing } from '@/features/otherFeature/hooks/useOtherFeatureThing'

// Better: promote the shared piece, or compose one level up
import { useSharedThing } from '@/hooks/useSharedThing'
```

**Durable fix:** suggest an ESLint `import/no-restricted-paths` rule (bulletproof-react's own recommendation) restricting `features/*` to importing only from its own folder and the shared app level — this catches the violation at commit time instead of relying on review.

---

### Section 2 — Components & JSX

#### §R3. React keys and indices

Index as a React `key` for items that can reorder/insert/delete. Mixing filtered and unfiltered indices in the same component. Re-deriving an index via `arr.indexOf(...)` after already iterating with one. If items have stable IDs, use them; if the form library assigns one (e.g. a field-array id), use the form library's stable id, not the array index.

#### §R4. Vestigial aliases that survived a simplification

When a const just renames another const with no behavior change (`const handleA = handleB`), it's usually a leftover from an earlier version where the alias was going to do more. Two failure modes: a pure alias (`const handleA = handleB`), and a multi-line delegator with no transformation (`const handleA = (...args) => handleB(...args)`). Either inline at the call site, or rename the call-site prop to match what the function actually is. If a comment explains a constraint that *eliminated* extra work, the alias itself probably has none left and is just an explanation in disguise.

#### §R5. Prop drilling + too-many-props when a hook would do

Not a hard rule — sometimes prop interfaces are the right call (testability, reuse outside a provider). But often a component receives 2+ props derived entirely from a single context/hook value the parent had to fetch on its behalf, purely to hand it down.

Flag when: a child takes 2+ props all derived from one context/hook the parent called; the parent computes a value purely to pass down with no other local use; a grandparent threads a value through an intermediate component that never reads it.

Suggest: the child reads from the same hook/context the parent read from (caches/contexts dedupe). Keep the prop interface for inputs that genuinely vary per call site.

```tsx
// Flag
const allowance = ctx?.a ?? other?.b ?? 0
return <CreditsCard allowance={allowance} balance={ctx?.balance ?? 0} />

// Better
return <CreditsCard />   // reads useSomeContext() itself
```

**When NOT to flag:** pure primitives that vary per call site; a component intentionally kept context-free for reuse outside the provider; only one prop being forwarded (the indirection isn't worth removing).

#### §R6. Repeated sibling JSX that differs only by data — map an array

When **3+ sibling blocks** are structurally identical and differ only in the data they show, build an array of the varying data and `.map` it.

```tsx
// Flag: 3 near-identical blocks, only label/value differ
<Row><Label>{t('a')}</Label><Value>{a}</Value></Row>
<Row><Label>{t('b')}</Label><Value>{b}</Value></Row>
<Row><Label>{t('c')}</Label><Value>{c}</Value></Row>

// Better
const rows = [{ label: t('a'), value: a }, { label: t('b'), value: b }, { label: t('c'), value: c }]
{rows.map(({ label, value }) => <Row key={label}><Label>{label}</Label><Value>{value}</Value></Row>)}
```

**Why it's better:** one source of truth for the row shape (restyling is one edit, not N); add/remove/reorder becomes a data edit, not a copy-paste that risks a wrong-value bug; `rows.map(...)` reads as intent ("N rows of the same kind") instead of forcing the reader to diff blocks; a single template can't silently drift the way repeated blocks do.

Use a stable `key` (label or id), never the index. Threshold is **3+**; two explicit blocks are fine and not worth the indirection.

Distinct from lookup-object dispatch (see the `structure` skill, §S5) — that's branch-selection of **one** value from a fixed set of cases; this is repeated **rendered siblings**.

#### §R7. Keep hook-call assignments pure — derive on the next line

Don't bury a subscription/selector hook call inside a larger expression that also transforms its result. Assign the hook's return to a named variable first, derive on the next line.

```tsx
// Flag
const hasItems = (useWatch({ control, name: 'items' }) ?? []).length > 0

// Better
const items = useWatch({ control, name: 'items' })
const hasItems = Boolean((items ?? []).length)
```

Why: the subscription reads as one thing at a glance; the watched value becomes reusable instead of forcing a second subscription; it's directly inspectable/loggable.

#### §R8. A layout component owns its container; no component assumes its parent

**Owns-container:** a component that renders container-dependent children (grid cells, list rows) should wrap them in its own container itself, not leave the wrapper to the caller.

```tsx
// Flag: bare items; layout breaks unless the parent remembers to wrap it
const FieldGroup = () => <><Cell>...</Cell></>

// Better: the component owns its container
const FieldGroup = () => <Row>{/* Cell items */}</Row>
```

**No-parent-assumptions:** a component's root/output must be self-contained and render correctly under any parent. Flag any assumption baked in: positioning that needs a specific ancestor (a prop that only works under a specific ancestor container, e.g. a grid cell prop, `flexGrow`, `alignSelf`; `position: 'absolute'` needing a positioned ancestor); self-applied outer margins presuming sibling rhythm (spacing *between* children is the parent's `gap`/`spacing` to set); presence/placement decisions that are really the parent's call.

```tsx
// Flag: root cell-prop only works if some ancestor is the matching container
const Child = () => <GridCell size={12}>...</GridCell>

// Better: child renders self-contained content; parent decides the slot
const Child = () => <div>...</div>
// parent: <GridCell size={12}><Child /></GridCell>
```

Rule of thumb: read only the component's own return, ignoring every caller — if you can't tell it will render correctly, it's assuming its context.

This is the mirror of the owns-container rule above: a child must own its **internal** container, and must not own the **external** placement that is the parent's.

#### §R9. Conditional element assembly → a named local component

Two inline smells: a `let` placeholder reassigned across `if`/`else` branches (`let cell = null; if (…) cell = <A/>; else cell = <B/>`), or a ternary (in JSX or assigned to a `const`) with multi-line/non-trivial branches choosing between element shapes.

Extract a small **named local component** with early returns.

```tsx
// Flag
let cell = null
if (hasPrimary) cell = <Primary value={value} />
else if (showFallback) cell = <Fallback value={fallback} />
return <Cell>{cell}</Cell>

// Better
const ValueCell = ({ hasPrimary, value, showFallback, fallback }: Props) => {
  if (hasPrimary) return <Primary value={value} />
  if (showFallback) return <Fallback value={fallback} />
  return null
}
return <Cell><ValueCell hasPrimary={hasPrimary} value={value} showFallback={showFallback} fallback={fallback} /></Cell>
```

**Placement:** same file, next to sibling sub-components, while small; promote to its own file only once it grows large or picks up its own dependencies/tests — don't over-fragment for a few lines. **Do NOT flag** a short single-line ternary between two trivial values/elements, or a bare `{cond && <X />}` guard.

#### §R10. Side-effect-only components, skip-via-ternary maps, `renderXxx()`

**Side-effect-only components are a BLOCKER.** A component whose only job is `useEffect` + `return null` is a hook wearing a JSX wrapper. It misleads the reader scanning the JSX tree for output, forces the parent to mount `<X />` when `useX()`/`withX(...)` would be honest, and resists composing with existing hooks/HOCs covering the same ground.

Suggested fix order (match whatever shape the target repo already uses for the concern):
1. **HOC** — preferred for route-gating (permission checks, feature-flag gates, setup-state guards): `withSomeGuard(Page)`, composable as `withA(withB(Page))`.
2. **Hook** — for a lifecycle side-effect that doesn't gate rendering per-route (analytics page-view tracking, scroll restoration). Called from the parent.
3. **Folding into an existing hook/HOC** — only when the existing thing genuinely owns the same domain; check the existing thing's actual responsibility before suggesting consolidation (two guards that both `router.replace` are not automatically the same concern).

**Skip-via-ternary in map callbacks.** `arr.map(item => cond ? null : (<Row>...</Row>))` forces the reader to parse the ternary as wrapping the whole JSX block. Prefer a block body with a guard clause:

```tsx
// Flag
{items.map((item) => item.hidden ? null : <Row key={item.id}>...</Row>)}

// Better
{items.map((item) => {
  if (item.hidden) return null
  return <Row key={item.id}>...</Row>
})}
```

**`renderXxx()` inline render functions are an anti-pattern, not a fix.** A `const renderContent = () => (...)` called from the same component's return: re-runs on every parent render without its own reconciliation, doesn't show up in DevTools, hides a missing sub-component behind a method-shape that pretends to be cheap, obscures the JSX tree (readers scanning the return have to jump elsewhere to find the actual content), and closures over scoped variables make later extraction harder. Flag any new `renderXxx` called from its own component's return; point at §R9's named-component extraction instead. **Acceptable shapes:** a function handed to a render-prop API the library demands (`renderRow={(row) => ...}`); or a `useCallback`-wrapped handler that returns JSX for an event-driven mount (rare; usually still a missed component). Further reading: Nadia Makarevich, *React re-renders guide*, ["Antipattern: creating components in render function"](https://www.developerway.com/posts/react-re-renders-guide#%EF%B8%8F-antipattern-creating-components-in-render-function).

#### §R20. React 19: `ref` is a prop, `forwardRef` is not needed

Check the project's React version first; this box applies from React 19. There `ref` is an ordinary prop, so new components take it in their props and never use `forwardRef`:

```tsx
// Flag
export const WidgetInput = forwardRef<WidgetInputHandle, WidgetInputProps>(({ label }, ref) => { /* ... */ })

// Prefer
interface WidgetInputProps { label: string; ref?: Ref<WidgetInputHandle> }
export const WidgetInput = ({ label, ref }: WidgetInputProps) => { /* ... */ }
```

**The half-migrated case is the one to look for:** a props type that already declares `ref?: Ref<T>` while the component is still wrapped in `forwardRef`. `forwardRef` strips `ref` out of props, so the declaration is unreachable and misleading.

---

### Section 3 — Data fetching

The detail for §R11-§R13, §R21-§R23 and §R27 is in `${CLAUDE_PLUGIN_ROOT}/skills/react/references/data-fetching.md`. Read it in full before grading any of them.

---

### Section 4 — Forms

The detail for §R14 and §R24-§R26 is in `${CLAUDE_PLUGIN_ROOT}/skills/react/references/forms.md`. Read it in full before grading any of them.

---

### Section 5 — State

#### §R15. New state lives at the lowest common ancestor of its consumers

Declare new state where its actual consumers are, not one level higher "in case" a parent ends up needing it too. Lifting state speculatively re-renders everything between the new home and the real consumer, and invites prop drilling (§R5) the moment the speculation doesn't pan out.

```tsx
// Flag: lifted to the page component though only one child reads/writes it
const [isPanelOpen, setIsPanelOpen] = useState(false)
return <Page><SidePanel isOpen={isPanelOpen} onToggle={setIsPanelOpen} /></Page>

// Better: the state stays with its only consumer
const SidePanel = () => {
  const [isOpen, setIsOpen] = useState(false)
  // ...
}
```

If a second sibling consumer genuinely appears, lift then — to the nearest common ancestor of the consumers that exist today, not further.

**Order-dependent multi-step state mutations carry a rationale comment.** `update(...)` then `remove(...)`, or `setX(...)` then `setY(...)` where swapping the order changes behavior, needs a one-line comment at the call site saying why the order matters (this is the same rule as clarity's §C7, scoped here to component state specifically).

```tsx
// Flag: order matters, nothing says so
update(rowId, changes)
remove(previousRowId)

// Better
// remove must run after update: removing first would shift indices update relies on
update(rowId, changes)
remove(previousRowId)
```

---

### Section 6: Render cost and layout

#### §R16. A memo has to hit

`useMemo` and `useCallback` cost a dependency comparison on every render and buy nothing unless the cache actually hits. Walk every new one:

- **Empty dependencies and no input from component scope.** The value never changes, so it is a module constant in disguise. Hoist it above the component.
- **A dependency that changes every render.** An inline object, array, or function, or a fresh instance created in render, is a new reference each time, so the memo recomputes every render and adds overhead. Drop the memo, or stabilize the dependency first.
- **A cheap computation.** A few property reads or a short string concatenation cost less than the comparison. Say what the computation is when flagging it.

```tsx
// Flag: empty deps, nothing from component scope
const columns = useMemo(() => [{ key: 'name' }, { key: 'size' }], [])

// Prefer: a module constant
const COLUMNS = [{ key: 'name' }, { key: 'size' }]
```

Every "drop this memo" finding states the reason (empty deps, unstable dep, cheap computation), so the author can check it.

**Enumerate by grep, do not eyeball:** run the `memo-hooks.sh` sweep (see Sweeps) over the diff's added lines.

One line per hit with a verdict, and `grepped memo hooks: 0 hits` printed explicitly when none are found.

**N/A under React Compiler.** When the project runs React Compiler (grep its build config and `package.json` for the compiler plugin), the compiler owns memoization and this box is N/A; say so and cite the config line.

#### §R17. No wasted render work

- **Work for a mode that is not active.** A memo, effect, or loop that computes a value only one mode uses, while running in every mode. Guard it with an early return so it does nothing when the result is unused.
- **Memoization broken by the caller.** An inline object or callback passed to a memoized child (or into a dependency array) is a new reference every render, so the child re-renders anyway. Stabilize it, or drop the child's memo.
- **Stale or unstable dependencies.** A dependency array that lists a function reference instead of the data the function reads either goes stale or recomputes every render. List the underlying data.
- **Recomputing a memoized value.** A value computed in a memo, then computed again from the same inputs elsewhere in the component. Read the memoized one.
- **One call shape repeated inside a memo, varying one argument.** Extract a stable callback and call it, instead of building the same closure several times.

Look first, flag second: read what the computation costs and how often the component renders before calling it waste.

#### §R18. Large JSX blocks and redundant wrappers

A JSX block past roughly 30 lines that reads as its own unit (a panel, a row, a form section) is easier to read and test as a named component. Place it per §R9: same file while small, its own file once it grows.

A wrapper element that only repeats its parent's styling, or that adds no layout, semantics, or handler, is markup noise. Drop it and let the parent's box do the work.

```tsx
// Flag: the inner div repeats the parent's layout
<div className="flex gap-2">
  <div className="flex gap-2">{children}</div>
</div>

// Prefer
<div className="flex gap-2">{children}</div>
```

#### §R19. Check layout at narrow widths

A change to sizing or layout that looks right on a wide screen can collapse on a narrow one. For any diff touching width, height, min/max sizing, flex or grid layout, or positioning, check it at 375, 600, 768, and 1024 px:

- Compute (or measure in a running app) the usable width per column or cell at each width, after subtracting padding, gaps, and fixed-width siblings.
- Confirm the content still renders readably at each: text does not overflow, controls stay tappable, nothing is clipped.
- Put the numbers in the finding ("7 columns at 375 px leave 41 px per cell after padding").

The recurring failure is removing a `min-width`/`min-height` floor without a responsive fallback (a different layout, horizontal scroll, or fewer columns below a breakpoint): the floor was what kept the narrow case readable. When a browser is available, the testing plugin's `verify-ui` skill drives this check against the real screen.

## Sweeps

Save the diff under review to a file (`gh pr diff <num> > /tmp/review.diff`, or `git diff <default-branch>...HEAD > /tmp/review.diff`) and run each script over it; `-` reads the diff from stdin. Each prints one `path:line: text` hit per line, where `line` is the new-side line number, and nothing else. Give every hit its own verdict, and state each receipt with its count, `0 hits` included.

- `added-lines.sh` (citation map): every added line as `path:line: text`, with the source line number at the head SHA. Cite every finding's line from this output or from a sweep hit, never from a position in the diff file.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/added-lines.sh" <diff-file>
  ```

- `mutate-async.sh` (§R13): added lines calling `mutateAsync`. Receipt: `grepped mutateAsync: N hits`.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/skills/react/scripts/mutate-async.sh" <diff-file>
  ```

- `memo-hooks.sh` (§R16): added lines calling `useMemo` or `useCallback`. Receipt: `grepped memo hooks: N hits`.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/skills/react/scripts/memo-hooks.sh" <diff-file>
  ```
