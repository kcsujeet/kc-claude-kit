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

- [ ] Tick every box for each construct you add or change. Report each: PASS, FAIL (file:line) or N/A (why).

- [ ] §R1 Bulletproof-react placement: feature code sits under `features/<feature>/{api,components,hooks}`; code used across features sits at the shared app level.
- [ ] §R2 No cross-feature imports (`features/A` importing from `features/B`'s internals); composition happens at the app/routes level. (N/A: no feature-to-feature import in diff)
- [ ] §R3 React keys/indices correct: no index key for reorderable items, no mixed filtered/unfiltered indices, no redundant `indexOf` after a `find`. (N/A: no keyed list in diff)
- [ ] §R4 No vestigial aliases left over from a simplification. (N/A: none in diff)
- [ ] §R5 No prop drilling / too-many-props where a child could read the same hook directly (2+ props derived from one context/hook the parent fetched). (N/A: no matching prop shape)
- [ ] §R6 Repeated sibling JSX (3+ structurally identical blocks differing only by data) is mapped from an array, with a stable key. (N/A: fewer than 3 repeated blocks)
- [ ] §R7 Hook-call results are assigned to a variable, then derived on the next line, never inlined in a transforming expression. (N/A: no such hook call)
- [ ] §R8 A layout component owns its container and assumes nothing about its parent (no root props or margins that only work under one ancestor). (N/A: no such component added)
- [ ] §R9 Conditional element assembly is a named local component with early returns, not a `let` then `if/else` or a multi-line ternary building JSX.
- [ ] §R10 No side-effect-only component (`useEffect` + `return null`), no skip-via-ternary in `map` callbacks, no inline `renderXxx()` functions. (N/A: none of the three)
- [ ] §R11 Reads and writes live in separate hooks; no raw `fetch`/`axios`/`useMutation`/`useQuery` call inside a component — grep how sibling features do it. (N/A: no data call in diff)
- [ ] §R12 Fetch ownership re-checked for every read hook added or moved: it lives with its real consumer, no parent duplicates a child's fetch, no full-list fetch to derive a boolean.
- [ ] §R13 Invalidation is a last resort (cache patch, then surgical update, then invalidate); prefer `mutate` + callbacks over `mutateAsync` + `await`; run `mutate-async.sh`, one verdict per hit.
- [ ] §R14 The form is the single source of truth (no `useState` shadowing a form value); hand-rolled validation is checked against the validation library's API. (N/A: no form or schema)
- [ ] §R15 New state lives at the lowest common ancestor of its real consumers, never lifted for a parent that "might" want it; order-dependent state mutations carry a rationale comment.
- [ ] §R16 Every new `useMemo`/`useCallback` earns its place: empty deps mean a hoisted constant, an every-render dependency means the cache never hits; sweep with `memo-hooks.sh`.
- [ ] §R17 No wasted render work: unused memo/effect/loop work guarded out, inline objects or callbacks to memoized children and dependency arrays stabilized, nothing recomputed after memoizing.
- [ ] §R18 A JSX block past roughly 30 lines that reads as its own unit is a named component; no wrapper element that adds nothing to layout. (N/A: no such block or wrapper)
- [ ] §R19 A width, height, sizing, flex/grid or positioning change is checked at 375, 600, 768 and 1024 px with the usable width per column shown; removing a minimum floor without a fallback FAILS.
- [ ] §R20 On React 19+, `ref` is a plain prop: no new `forwardRef`, no props type declaring `ref` on a `forwardRef` component; one verdict per `forwardRef` hit. (N/A: React below 19, or 0 hits)
- [ ] §R21 A request's method matches its effect: a read that saves nothing uses GET; a read hook on POST/PUT/PATCH FAILS unless the input cannot fit a query string, with a comment.
- [ ] §R22 A cache patch or invalidation targets the narrowest key that shows the change; a broad base key only when lists showing the record need it, with a comment. (N/A: none added)
- [ ] §R23 A write hook touches only its own resource and imports no other resource's requests or hooks; the caller composes the two writes and updates its cache in `onSuccess`.
- [ ] §R24 A form-state hook returns form plumbing only (methods, submit, discard, saving state); returning field data or handlers FAILS, that logic lives in the field's component.
- [ ] §R25 Each form watch and piece of field state lives in the smallest component that renders from it; children read shared values via the form context, not props from a watching parent.
- [ ] §R26 A form editing an existing record seeds the related record its inputs render from (`owner_id` and `owner`), not just the id; no picker label is hand-built from a record the form holds.
- [ ] §R27 A read hook accepts the repo's standard read-hook options (extended, not re-declared) and wires every option it accepts; an unread option FAILS. (N/A: no read hook added or edited)
- [ ] §R28 Query keys include each context the response depends on (tenant, user, locale); a write that adds a record or changes a filtered field refetches filtered and derived queries.
- [ ] §R29 A new or changed `min-height`/`min-width` is checked against its flex parent (`flex-shrink: 0`, or content never outgrows it); one verdict per grep hit. (N/A: `grepped min sizing: 0 hits`)
- [ ] §R30 A read sends its narrowing (status, parent, visibility, user scope) to the server like 2 cited sibling reads; no `data.filter(...)` the server could do, no second fetch for returned data.
- [ ] §R31 A form showing part of a set (one store's links) seeds only those and sends every hidden entry back unchanged; rendering entries it cannot name, or dropping them, FAILS.
- [ ] §R32 Done the way similar code does it: each new or reshaped component, hook, form, store or test names ~10 similar files per area, the pattern followed and the differences (see §R32).
- [ ] §R33 A form with Save and Discard sends nothing before Save: picked and removed files are held in form state and applied on submit; a write firing on pick, drop or remove FAILS.
- [ ] §R34 A section with an edit mode shows saved values, outside edit mode, through the read-only display 2 cited sections use; disabled inputs or a blank box for empty FAIL.
- [ ] §R35 An empty slot (image, file, avatar, list) reads as empty: muted styling and an icon naming what belongs there, like 2 cited empty slots; a content-styled placeholder FAILS.
- [ ] §R36 A field that picks a record is a picker component in its own file, shaped like 2 cited pickers; a form or field fetching records and building options itself FAILS.
- [ ] §R37 Markup shared by 2+ components is a component taking the differences as props; a hook or function returning JSX for callers to render FAILS (see §R37). (N/A: no shared markup)
- [ ] §R38 Every value a render shows or passes on comes from a subscription (watched field, selector, state, hook return); a one-off `getValues()`, `getState()` or `ref.current` read in render FAILS.

- Examples and edge cases per box: references/detail.md (read when a box is unclear).

## Sweeps

- [ ] Save the diff under review to a file (`gh pr diff <num> > /tmp/review.diff`, or `git diff <default-branch>...HEAD > /tmp/review.diff`) and run each script over it; `-` reads the diff from stdin. Each prints one `path:line: text` hit per line, where `line` is the new-side line number, and nothing else. Give every hit its own verdict, and state each receipt with its count, `0 hits` included.

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
