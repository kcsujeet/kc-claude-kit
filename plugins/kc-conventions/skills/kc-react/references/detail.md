# React: examples and edge cases per box

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

The detail for §R20, §R35, §R36 and §R37 is in `${CLAUDE_PLUGIN_ROOT}/skills/kc-react/references/components.md`. Read it in full before grading either.

---

### Section 3 — Data fetching

The detail for §R11-§R13, §R21-§R23, §R27, §R28 and §R30 is in `${CLAUDE_PLUGIN_ROOT}/skills/kc-react/references/data-fetching.md`. Read it in full before grading any of them.

---

### Section 4 — Forms

The detail for §R14, §R24-§R26, §R31, §R33, §R34 and §R38 is in `${CLAUDE_PLUGIN_ROOT}/skills/kc-react/references/forms.md`. Read it in full before grading any of them.

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

A change to sizing or layout that looks right on a wide screen can collapse on a narrow one. For any diff touching width, height, min/max sizing, flex or grid layout, or positioning, check it at 375, 600, 768, 1024 and 1920 px (a wide desktop shows what a viewport-relative unit or an unbounded width does when the screen is bigger than the design):

- Measure in the running app, never estimate, the usable width per column or cell at each width, after subtracting padding, gaps, and fixed-width siblings. A box that says a layout holds "by calculation" or "estimated" FAILS (`verify-gate-blocks.sh` rejects it): cite the screenshot path or the measured value.
- Confirm the content still renders readably at each: text does not overflow, controls stay tappable, nothing is clipped.
- Put the numbers in the finding ("7 columns at 375 px leave 41 px per cell after padding").

The recurring failure is removing a `min-width`/`min-height` floor without a responsive fallback (a different layout, horizontal scroll, or fewer columns below a breakpoint): the floor was what kept the narrow case readable. When a browser is available, the kc-verify plugin's `kc-ui` skill drives this check against the real screen.

#### §R29. A minimum size on a flex item

A flex item's default minimum is `auto`: it never shrinks below its content. Setting `min-height: 100vh` (or any explicit minimum) replaces that default. Inside a flex parent with a fixed size, such as a `body` that is a column flex container at `height: 100%` and scrolls itself, the item now shrinks to exactly the minimum, and anything taller runs past its background onto the parent's. It looks right with short content and breaks only when content outgrows the screen.

```tsx
// Bad: under a fixed-height flex column, the page stops at one screen and a long list overflows it
<Stack sx={{ bgcolor: 'background.paper', minHeight: '100vh' }}>

// Good: at least one screen tall, under any parent, and it grows with its content
<Stack sx={{ bgcolor: 'background.paper', minHeight: '100vh', flexShrink: 0 }}>
```

`flex-grow: 1` also fills the screen, but only under a flex parent, which is the parent assumption the components rule forbids. Check the case with content longer than the container (§R19 checks the narrow one).

### Section 7: Doing it the way similar code does

#### §R32. Do it the way similar code does

Similar code means code that does the same kind of job, wherever it lives. Folder layouts differ between apps and between features of one app, so search by what the code does (`useQuery(`, `useMutation(`, `useForm(`, `create(` for a store, `render(` in tests), not by which folder it sits in.

Read about ten pieces, not two or three. Two or three can be the odd ones out; ten show what the app does by default and which files are the exceptions. Per area:

| Area | What to match |
|---|---|
| Data | the resource or client layer, how a record and a list are read (one hook each, named for the resource), how filters and related data go into the request, cache keys, how writes update the cache |
| Forms | the form and schema libraries, field components, how defaults are seeded and errors shown |
| State | where shared state lives (a store, context, the URL), and what stays local |
| Components and styling | the shared component library and its variants, design tokens, layout primitives |
| Names and exports | how hooks, components and files are named, named or default exports |
| Tests | how components are rendered, how requests are mocked, shared fixtures, what is asserted |

Write in the evidence what you read and what differs. A difference is a finding unless the change already says why.

A new library, wrapper or way of doing any of these is the last resort. Try each existing way first and show why it does not fit; then ask the developer before building it. A shape only one file uses is not a pattern to copy either.

Typical misses this catches: a data hook named for the one screen that uses it, where every other is named for its resource; a small hook created to format one value that every other component formats inline; a test that builds its own mock data where the others use shared fixtures; a cache key or constant named differently from the rest of its family.
