---
name: kc-react
description: "React conventions for .tsx and .jsx components, hooks and API modules: structure, keys, conditional rendering, data-fetching hooks, forms, state placement, memoization, narrow-width layout, `ref` as a prop. Use when writing or reviewing React components, hooks, queries, forms or layout CSS."
user-invocable: false
paths:
  - "**/*.{tsx,jsx}"
  - "**/hooks/**/*.{ts,js}"
  - "**/api/**/*.{ts,js}"
---

# React

## Contents

- Review checklist
- Sweeps

## Review checklist

Tick every box for each construct you add or change. Report each: PASS, FAIL (file:line) or N/A (why).

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
- [ ] §R28 Cached data follows its context and its filters: every new or changed query key includes each context its response depends on that isn't in its params (the current tenant or workspace sent in a header or read from a store, the signed-in user, the locale), through the repo's helper for context keys when one exists. A write that adds a record, or changes a field a list filters on, refetches filtered lists instead of patching them, and also refetches queries that derive from what it changed (counts, totals, badges). (N/A: no query key, cache patch or write added or changed)
- [ ] §R29 A new or changed `min-height`/`min-width` (or `minHeight`/`minWidth`) on an element was checked against its parent: when the parent is a flex container with a fixed size, the element either cannot shrink (`flex-shrink: 0`) or its content can never outgrow the minimum, and the finding names the parent and its size. **Enumerate**: grep the diff for `min-height`, `min-width`, `minHeight`, `minWidth`, one verdict per hit. (N/A: `grepped min sizing: 0 hits`)
- [ ] §R30 A read asks the server for what the screen shows: for every fetch the diff adds or changes (a list, table, picker, search, count, or a lookup of related records), its narrowing (a status, a parent, a visibility, the current user's scope) goes into the request the server answers, the way 2 cited sibling reads send theirs, and a related record the screen names comes from the response that already carries it (§R26). A response filtered in code (`data.filter(...)` where the server could have narrowed) FAILS, and so does a second fetch to look up records the first response already carries, unless a comment says why the server can't. An endpoint that merely doesn't offer the filter yet is not "can't" when the same team owns it: the fix is a server filter, shipped before the client that sends it. (N/A: no fetch added or changed)
- [ ] §R31 A form that shows part of a set keeps the rest: when the screen's context limits which entries of a set field the form shows (one store's links on a store page), the form seeds only those, and on submit it sends back every hidden entry unchanged. Rendering entries it can't name (a bare id) FAILS, and so does dropping them. (N/A: no set field limited by context)
- [ ] §R32 Done the way similar code does it: for every new or reshaped component, hook, form, store or test, the evidence names by path the similar code read for each area the change touches (about ten pieces, or all there are when fewer: data fetching and caching, forms and validation, shared state, shared components and tokens, naming and exports, tests), states the pattern it follows, and lists what the change does differently. Fewer than ten read when more exist FAILS, and so does a new library, wrapper or way of doing an area's job without evidence that the existing ways were tried and the developer agreed. (N/A: no new or reshaped component, hook, form, store or test)
- [ ] §R33 A form with Save and Discard sends nothing before Save: every file it picks or removes is held in form state and applied in the submit, the way 2 cited similar forms hold theirs. An upload, delete or other write that fires on pick, drop or remove inside such a form FAILS, since Discard can't undo it. (N/A: no form with Save and Discard added or changed)
- [ ] §R34 A section with an edit mode shows its saved values, out of edit mode, through the read-only display 2 cited similar sections use. Inputs that are only disabled until Edit FAIL when the codebase has a read-only display, and so does an empty value shown as a blank box instead of the codebase's empty marker. (N/A: no section with an edit mode added or changed)
- [ ] §R35 An empty slot (an image, a file, an avatar, a list) reads as empty: muted styling the filled state doesn't share, and an icon that names what belongs there, matching 2 cited empty slots in the codebase. A placeholder styled like content, or an icon for something else (a person icon where a logo goes), FAILS. (N/A: no empty slot added or changed)
- [ ] §R36 A field that picks a record is a picker component for that kind of record, in its own file, shaped like 2 cited existing pickers (the props they take, how they narrow, how they show an empty list). A form or field component that fetches records and builds the options itself FAILS. (N/A: no record picker added or changed)
- [ ] §R37 Markup shared by two or more components is a component taking the differences as props. A hook or function whose return value carries JSX for callers to render FAILS, unless the codebase's API for that spot takes options with node labels and 2 cited similar call sites build them inline. (N/A: no shared markup added or moved)
- [ ] §R38 Every value a render reads for what it shows or passes on comes from a subscription (a watched form field, a store selector, state, a hook's return value). A one-off read during render (`getValues()`, `getState()`, `ref.current`, a module variable that changes) FAILS: a memoizing compiler or `memo` can keep its first result, and a ref is unset on the first render; read it in an effect or event handler, or subscribe. (N/A: no render reads a form, store or ref)

Examples and edge cases per box: references/detail.md (read when a box is unclear).

## Sweeps

Save the diff under review to a file (`gh pr diff <num> > /tmp/review.diff`, or `git diff <default-branch>...HEAD > /tmp/review.diff`) and run each script over it; `-` reads the diff from stdin. Each prints one `path:line: text` hit per line, where `line` is the new-side line number, and nothing else. Give every hit its own verdict, and state each receipt with its count, `0 hits` included.

- `added-lines.sh` (citation map): every added line as `path:line: text`, with the source line number at the head SHA. Cite every finding's line from this output or from a sweep hit, never from a position in the diff file.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/added-lines.sh" <diff-file>
  ```

- `mutate-async.sh` (§R13): added lines calling `mutateAsync`. Receipt: `grepped mutateAsync: N hits`.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/skills/kc-react/scripts/mutate-async.sh" <diff-file>
  ```

- `memo-hooks.sh` (§R16): added lines calling `useMemo` or `useCallback`. Receipt: `grepped memo hooks: N hits`.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/skills/kc-react/scripts/memo-hooks.sh" <diff-file>
  ```
