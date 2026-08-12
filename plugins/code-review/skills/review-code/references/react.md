# React gate

Project-structure, component/JSX, data-fetching, form, and state-placement conventions for React/JSX UI code. Covers fifteen independent failure modes across five areas: where code lives (bulletproof-react), how components and markup are structured, how reads/writes are split and owned, how forms hold state, and where new component state itself lives.

## Gate checklist

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
- [ ] §R13 Query invalidation is a last resort (cache-patch → surgical update → invalidate, in that order); `mutate` + callbacks preferred over `mutateAsync` + `await` when the resolved value only drives a side effect; mechanical sweep — grep the diff's added lines for `mutateAsync`, give every hit a verdict, state `grepped mutateAsync: 0 hits` explicitly when none found. (N/A: no invalidation or mutation in diff)
- [ ] §R14 Form is the single source of truth (no `useState` shadowing a form-held value); hand-rolled validation checks/regex/coercions are confirmed against the validation library's own API before being kept. (N/A: no form or schema in diff)
- [ ] §R15 New component state lives at the lowest common ancestor of its actual consumers, never lifted because a parent "might" want it; order-dependent multi-step state mutations (`update` then `remove`, `setX` then `setY` where order matters) carry a rationale comment at the call site. (N/A: no state added or edited in diff)

---

## Section 1 — Project structure (bulletproof-react)

Reference: https://github.com/alan2207/bulletproof-react/blob/master/docs/project-structure.md

### §R1. Feature-based layout, shared code at the app level

```
src/
├── components/, hooks/, utils/, types/, stores/, lib/, config/   — shared, cross-feature
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
// Flag — new feature file placed at the shared app level for no reason
src/hooks/useWidgetPricing.ts       // only WidgetPanel (in features/widgets) consumes it

// Better — feature-scoped
src/features/widgets/hooks/useWidgetPricing.ts
```

### §R2. No cross-feature imports

`features/A` importing a component, hook, or type from inside `features/B` couples two areas that should be independently deletable/replaceable. Compose at the app/routes level instead: the page/route file imports from both features and wires them together, or the shared piece moves to the app-level shared folder.

```
// Flag
import { useOtherFeatureThing } from '@/features/otherFeature/hooks/useOtherFeatureThing'

// Better — promote the shared piece, or compose one level up
import { useSharedThing } from '@/hooks/useSharedThing'
```

**Durable fix:** suggest an ESLint `import/no-restricted-paths` rule (bulletproof-react's own recommendation) restricting `features/*` to importing only from its own folder and the shared app level — this catches the violation at commit time instead of relying on review.

---

## Section 2 — Components & JSX

### §R3. React keys and indices

Index as a React `key` for items that can reorder/insert/delete. Mixing filtered and unfiltered indices in the same component. Re-deriving an index via `arr.indexOf(...)` after already iterating with one. If items have stable IDs, use them; if the form library assigns one (e.g. a field-array id), use the form library's stable id, not the array index.

### §R4. Vestigial aliases that survived a simplification

When a const just renames another const with no behavior change (`const handleA = handleB`), it's usually a leftover from an earlier version where the alias was going to do more. Two failure modes: a pure alias (`const handleA = handleB`), and a multi-line delegator with no transformation (`const handleA = (...args) => handleB(...args)`). Either inline at the call site, or rename the call-site prop to match what the function actually is. If a comment explains a constraint that *eliminated* extra work, the alias itself probably has none left and is just an explanation in disguise.

### §R5. Prop drilling + too-many-props when a hook would do

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

### §R6. Repeated sibling JSX that differs only by data — map an array

When **3+ sibling blocks** are structurally identical and differ only in the data they show, build an array of the varying data and `.map` it.

```tsx
// Flag — 3 near-identical blocks, only label/value differ
<Row><Label>{t('a')}</Label><Value>{a}</Value></Row>
<Row><Label>{t('b')}</Label><Value>{b}</Value></Row>
<Row><Label>{t('c')}</Label><Value>{c}</Value></Row>

// Better
const rows = [{ label: t('a'), value: a }, { label: t('b'), value: b }, { label: t('c'), value: c }]
{rows.map(({ label, value }) => <Row key={label}><Label>{label}</Label><Value>{value}</Value></Row>)}
```

**Why it's better:** one source of truth for the row shape (restyling is one edit, not N); add/remove/reorder becomes a data edit, not a copy-paste that risks a wrong-value bug; `rows.map(...)` reads as intent ("N rows of the same kind") instead of forcing the reader to diff blocks; a single template can't silently drift the way repeated blocks do.

Use a stable `key` (label or id), never the index. Threshold is **3+**; two explicit blocks are fine and not worth the indirection.

Distinct from lookup-object dispatch (see the structure gate) — that's branch-selection of **one** value from a fixed set of cases; this is repeated **rendered siblings**.

### §R7. Keep hook-call assignments pure — derive on the next line

Don't bury a subscription/selector hook call inside a larger expression that also transforms its result. Assign the hook's return to a named variable first, derive on the next line.

```tsx
// Flag
const hasItems = (useWatch({ control, name: 'items' }) ?? []).length > 0

// Better
const items = useWatch({ control, name: 'items' })
const hasItems = Boolean((items ?? []).length)
```

Why: the subscription reads as one thing at a glance; the watched value becomes reusable instead of forcing a second subscription; it's directly inspectable/loggable.

### §R8. A layout component owns its container; no component assumes its parent

**Owns-container:** a component that renders container-dependent children (grid cells, list rows) should wrap them in its own container itself, not leave the wrapper to the caller.

```tsx
// Flag — bare items; layout breaks unless the parent remembers to wrap it
const FieldGroup = () => <><Cell>...</Cell></>

// Better — the component owns its container
const FieldGroup = () => <Row>{/* Cell items */}</Row>
```

**No-parent-assumptions:** a component's root/output must be self-contained and render correctly under any parent. Flag any assumption baked in: positioning that needs a specific ancestor (a prop that only works under a specific ancestor container, e.g. a grid cell prop, `flexGrow`, `alignSelf`; `position: 'absolute'` needing a positioned ancestor); self-applied outer margins presuming sibling rhythm (spacing *between* children is the parent's `gap`/`spacing` to set); presence/placement decisions that are really the parent's call.

```tsx
// Flag — root cell-prop only works if some ancestor is the matching container
const Child = () => <GridCell size={12}>...</GridCell>

// Better — child renders self-contained content; parent decides the slot
const Child = () => <div>...</div>
// parent: <GridCell size={12}><Child /></GridCell>
```

Rule of thumb: read only the component's own return, ignoring every caller — if you can't tell it will render correctly, it's assuming its context.

This is the mirror of the owns-container rule above: a child must own its **internal** container, and must not own the **external** placement that is the parent's.

### §R9. Conditional element assembly → a named local component

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

### §R10. Side-effect-only components, skip-via-ternary maps, `renderXxx()`

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

---

## Section 3 — Data fetching

### §R11. Reads and writes live in separate hooks

No raw `fetch`/`axios`/`useMutation`/`useQuery` call inside a component — they belong in the project's data-hook layer. Grep how sibling features structure their read/write hooks before proposing a shape; match it. A hook that mixes a query and a mutation, or a component that inlines either, is a finding — point at the sibling pattern.

### §R12. Fetch ownership — by consumer, not convenience

When a read hook is added or moved, ask **where it belongs**, not just whether it works. The fetch should live with the component that actually *consumes* the data: single consumer → the consumer owns it; several siblings need it → lift to their nearest common parent.

Two failure modes:
- **Duplicated ownership** — a parent fetches a list a child already fetches for itself. With identical query keys the cache layer dedupes to one request, but **different params = different keys = two separate requests**, owned in two places that can drift.
- **Over-fetch for a derived flag** — pulling a full list only to compute a boolean (is-it-empty, show/hide a tab, gate a skeleton) is wasteful, and gating a whole page's skeleton on data only one section needs blocks the rest of the page.

```tsx
// Flag — parent fetches the whole list just to gate visibility, while a child
// already fetches (a filtered version of) the same data
const { data: items, isLoading } = useItems({ enabled })
if (isLoading) return <Skeleton />
// ...elsewhere: <ChildList /> independently calls useItems({ filter })

// Prefer — the consumer owns the fetch; let it render its own empty/loading state
```

Name the consumers in the review and ask whether the fetch is at the right altitude.

### §R13. Invalidation last resort; `mutate` + callbacks over `mutateAsync` + `await`

**Invalidation is a last resort.** Forcing a refetch is a network round-trip plus a loading flicker, and better tools usually exist. Order of preference: (1) the mutation returns the updated record — patch the cache directly on success; (2) a surgical cache update (add/remove/update one item in a list cache) without hitting the network; (3) only when neither is feasible, invalidate/refetch. (This is react-query framing since it's the dominant library; if the target repo uses SWR/RTK-Query or similar, map to its equivalents.) **Look first, flag second** — read what the mutation does and what the server returns before flagging; some invalidations are genuinely necessary (server-side cascading effects the client can't model).

**Prefer `mutate` + callbacks over `mutateAsync` + `await`.** Use `mutate(variables, { onSuccess, onError })` by default. Reach for `mutateAsync` + `await` only when: a subsequent statement in the same control flow genuinely depends on the resolved value and can't move into `onSuccess`; the caller's own contract requires returning a promise that resolves after the mutation completes; or multiple mutations must sequence in a way too tangled for nested `onSuccess`.

```ts
// Flag — resolved value only drives a side effect
const handleSubmit = async () => {
  const result = await someMutation.mutateAsync(variables)
  doSideEffect(result)
}

// Better
const handleSubmit = () => {
  someMutation.mutate(variables, { onSuccess: (result) => doSideEffect(result) })
}
```

Test: does the resolved value only drive a side effect (snackbar, redirect, cache patch, parent callback)? If yes, it belongs in `onSuccess` — errors flow through `onError` without a `try/catch` per call site, and pending/error state stays in sync automatically.

**Enumerate `mutateAsync` by grep, do not eyeball.** This box is graded on whether the hits were listed, not on whether they were noticed. Find them mechanically over the diff's added lines:

```bash
gh pr diff <num> | grep -nE '^\+.*mutateAsync'
```

Emit one line per hit with a verdict:

```
grepped mutateAsync: 2 hits
- [FAIL] useSubmitOrder.ts:34 — resolved value only drives a snackbar; switch to `mutate` + `onSuccess`
- [PASS] useCheckoutFlow.ts:52 — awaited because the caller's own contract returns a promise after settlement
```

**Silence is not a pass:** a sweep that finds none must print `grepped mutateAsync: 0 hits` explicitly, so "no receipt" is never mistaken for "nothing there."

---

## Section 4 — Forms

### §R14. Form is the single source of truth; validate via the library's own API

**No `useState` shadowing a form-held value.** When a form-bound input already holds a value, don't keep a parallel `useState` just to read it in a handler.

- **One-shot read** (submit handler, onClick): the library's one-shot getter (e.g. `getValues('foo')`), or the submit handler's own data argument. Note: a one-shot getter does not subscribe — it won't re-render the component when the value changes, unlike a reactive watch.
- **Reactive read** (a dependent field, a preview that must update live): the library's reactive watch equivalent (e.g. `useWatch`).

```tsx
// Flag — shadows the form value with parallel state
const [selected, setSelected] = useState<Foo>()
const handleChange = (foo?: Foo) => setSelected(foo)
const handleSubmit = methods.handleSubmit(() => selected && mutate(selected))
return <FooAutocomplete onChange={handleChange} />

// Better — read straight from the form
const handleSubmit = methods.handleSubmit((data) => data.foo && mutate(data.foo))
return <FooAutocomplete />
```

Why: two sources of truth get out of sync (a form reset, `defaultValues`, or a programmatic `setValue` all bypass the `useState`); the `onChange` that updates local state is a dead wrapper around the form's own `onChange`. **Flag whenever** a `useState<DomainRecord>` sits adjacent to a form-bound input with an `onChange` that just calls the setter — the setter, the state, and the handler are all redundant.

**Validation schemas: check the library's API before hand-rolling.** Whatever validation library the target repo uses (zod, yup, and similar), any hand-rolled `check`/`refine`/inline regex/`.length`/manual `Number(...)` comparison that re-implements something the library already ships natively is a finding, regardless of data type. Before flagging, open the library's own API docs and look for a native validator/transform covering the same rule.

- Coerce the input once in a `transform`, then validate with native rules — don't sprinkle `Number(value)` inside every check.
- Optionality/blank handling uses the library's own `optional`/`nullable`/`nullish` combinators, not a hand-written short-circuit.
- Any surviving hand-rolled check should be genuinely custom (cross-field, a domain invariant, a conditional requirement) — say so in the finding, so the reader knows it was considered, not missed.

```ts
// Flag — manual coercion repeated inside checks
check((v) => Number(v) >= 0) // and again in another check

// Better — coerce once, validate with the library's native actions
pipe(union([string(), number()]), transform((v) => (v === '' ? 0 : Number(v))), minValue(0))
```

---

## Section 5 — State

### §R15. New state lives at the lowest common ancestor of its consumers

Declare new state where its actual consumers are, not one level higher "in case" a parent ends up needing it too. Lifting state speculatively re-renders everything between the new home and the real consumer, and invites prop drilling (§R5) the moment the speculation doesn't pan out.

```tsx
// Flag — lifted to the page component though only one child reads/writes it
const [isPanelOpen, setIsPanelOpen] = useState(false)
return <Page><SidePanel isOpen={isPanelOpen} onToggle={setIsPanelOpen} /></Page>

// Better — the state stays with its only consumer
const SidePanel = () => {
  const [isOpen, setIsOpen] = useState(false)
  // ...
}
```

If a second sibling consumer genuinely appears, lift then — to the nearest common ancestor of the consumers that exist today, not further.

**Order-dependent multi-step state mutations carry a rationale comment.** `update(...)` then `remove(...)`, or `setX(...)` then `setY(...)` where swapping the order changes behavior, needs a one-line comment at the call site saying why the order matters (this is the same rule as clarity's §C7, scoped here to component state specifically).

```tsx
// Flag — order matters, nothing says so
update(rowId, changes)
remove(previousRowId)

// Better
// remove must run after update: removing first would shift indices update relies on
update(rowId, changes)
remove(previousRowId)
```
