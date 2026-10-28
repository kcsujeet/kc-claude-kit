# Clarity: ternaries, and the ternary and cast sweep

Review detail for clarity §C15, moved out of `SKILL.md` to keep it under the line cap. The box itself is in `SKILL.md` under `## Review checklist`; the sweeps are listed under its `## Sweeps`.

## §C15. Ternaries: flag when nested, long, or multi-line

A single, short, one-line ternary (`x ? a : b`) is fine and clear. Anything past that — nested, long, or wrapping onto multiple lines — should be broken down. Walk **every ternary in the diff** against this checklist:

- [ ] **Nested / chained** — `x ? a : y ? b : c`, or a ternary whose true/false branch contains another ternary. Two or more `?` on one expression → break down (named booleans, guards, sub-components, or a lookup object).
- [ ] **Long** — the whole expression, or either branch, is long (rough trip-wire: the line would exceed the formatter's print width, or a branch is more than a short value/single element). → extract each branch to a named `const`, or pull the choice into a helper / `if`-`else`.
- [ ] **Multi-line** — if the ternary spans more than one line once formatted (branches on their own lines, stacked closing parens), it's already too big for an inline ternary. → break into `if`/`else`, early returns, named-boolean guards, or extracted variables.
- [ ] **Non-trivial JSX branch** — a branch that is more than a single element with a couple of props. → use a guard render (`cond && <X />`) per state, or a sub-component.

The fix is almost always one of: named boolean predicates + separate guarded renders (preferred for JSX, see below), an extracted `const` per branch, an `if`/`else` or early return, or a lookup object when the discriminator is a finite enum.

The reasoning: each additional `?` and `:` doubles the mental load — the reader has to track which colons pair with which question marks — and a ternary that wraps across lines hides its own structure behind stacked parens.

This is especially common in JSX render: "if success, show A; else if conflict, show B; else if data, show C; else null." Written as a 3-way nested ternary it looks compact but reads as a wall.

**Bad:**
```tsx
return (
  <Dialog>
    {displaySuccess && result ? (
      <Success ... />
    ) : hasConflict ? (
      <Conflict ... />
    ) : data ? (
      <Form ... />
    ) : null}
  </Dialog>
)
```

**Good** (named boolean predicates + mutually-exclusive conditional renders):
```tsx
const showSuccessScreen = displaySuccess && Boolean(result)
const showConflictScreen = !showSuccessScreen && hasConflict
const showFormScreen = !showSuccessScreen && !showConflictScreen && Boolean(data)

return (
  <Dialog>
    {showSuccessScreen && result ? <Success ... /> : null}
    {showConflictScreen ? <Conflict ... /> : null}
    {showFormScreen && data ? <Form ... /> : null}
  </Dialog>
)
```

The named-boolean form reads top-to-bottom in priority order, makes mutual exclusion explicit at the variable level (so the rule of "only one screen at a time" is enforced by construction), and survives adding a fifth state by adding one more named boolean.

**Other acceptable fixes for the same shape:**
- **Sub-components** (`<SuccessScreen ... />`, `<FormScreen ... />`) when each branch carries enough JSX/state to deserve its own file. The cost is prop-drilling closure state; only do this when the branch is substantial or reusable.
- **Lookup-object dispatch** when the discriminator is a finite enum and conditions don't overlap. Not a fit when priority matters (e.g. success > conflict > form).

**Value / assignment ternaries count too — the checklist is not JSX-only.** A ternary assigned to a variable (or returned, or passed as an arg) is subject to every box above. What triggers a flag is the *shape* — nested, long, or multi-line — never what the branches happen to contain. The branch content is irrelevant: a spread, a method call, an object literal, a computation, a function call, anything. If the ternary spans multiple lines, or a branch is more than a short value/identifier, break it down — extract each branch to a named `const` so the choice reads on one line, or use `if`/`else`.

**Bad** (multi-line value ternary — the branch content is incidental, only the shape matters):
```ts
const next = isOn
  ? [...items, item]
  : items.filter((entry) => entry !== item)
```

**Good** (named branches, one-line choice):
```ts
const withItem = [...items, item]
const withoutItem = items.filter((entry) => entry !== item)
const next = isOn ? withItem : withoutItem
```

**Remedy limits.** A fix for a ternary must not trade it for a different defect:

- A value-or-absent prop is never rewritten as `flagA && value`. That yields `false`, not `undefined`, which a prop typed `T | undefined` rejects and a renderer may print. Assign a named const with an `if`, or keep a one-line ternary with `undefined` as the other branch. (Inside a class-merging helper, `flagA && 'some-class'` is fine, because the helper drops `false`.)
- Never propose a conditionally built partial object spread into a call (`widgetFn({ ...base, ...(flagA ? { optA, optB } : {}) })`). It moves the ternary out of sight instead of removing it, and it is a §C19 finding of its own; give each key a permanent slot set to `undefined` instead.
- For trivial branches (string formatting, key building, a cheap lookup), computing both named branches eagerly is the accepted cost of a one-line choice and is not an efficiency finding (§C18).

**Acceptable single-ternary patterns** (do NOT flag):
- One condition selecting between two values inline: `<Title>{flagA ? 'Confirm' : 'Send Request'}</Title>`.
- A ternary whose branches are single primitive values (a number, a class name, a short string) or a single short identifier, on one line.

## Enumerate ternaries and casts by grep, do not eyeball

§C15 says "walk every ternary in the diff" and §C4 says the same for `as` casts. Both are graded on whether you **listed** them, not on whether you noticed them: reading a long diff and forming impressions is how a multi-line ternary survives on a gate reported as PASS.

Find them mechanically **before** reading for meaning, over the diff's **added lines only** — over the diff you were given (e.g. `gh pr diff <num>` for a PR, `git diff <default-branch>...HEAD` for a branch), saved to a file and passed to two sweeps (see Sweeps):

- `ternaries.sh`: a `?` that is not `?.`, `??`, or an optional `?:`.
- `as-casts.sh`: type assertions, including `as string`, `as const`, `as unknown as T`.

The ternary pattern matches the `?` itself rather than dropping lines, so a line that holds both an optional property and a real ternary is still a hit, and a `?` left at the end of a line by the formatter is caught too.

The scripts match TypeScript and JavaScript syntax. For another language (`and`/`or` chains, `a if c else b` conditional expressions, `x.(T)` / `cast()` type assertions, etc.), run the language-appropriate pattern by hand as well; `0 hits` is only a valid receipt after the language-appropriate pattern was run, and the receipt states which script or pattern was used.

Both greps over-match, and that is fine — the point is that every candidate gets named and dismissed in writing rather than never being looked at. Expect to discard a `?` inside a string or a regex from the ternary grep, and import/export aliases (`import { x as y }`) and the word "as" in comments or strings from the cast grep; say so per hit. `as const` is a hit too: it is usually fine, and the verdict says so.

**Label every ternary hit single-line or MULTI-LINE.** Multi-line is itself a failure, so the receipt forces the classification instead of leaving it to a reading. A hit whose `?` has no `:` after it on the same line is `MULTI-LINE`: read the lines that follow before giving the verdict.

Emit one line per hit with its label, a verdict and the count:

```
grepped ternaries: 5 hits (1 discarded: `?` inside a regex)
- [FAIL] someLabel.ts:18: MULTI-LINE, template-literal branch; use an early return
- [PASS] useSelectionResource.ts:27: single-line, both branches trivial
...
grepped as-casts: 3 hits
- [FAIL] SubmissionFieldRow.tsx:29: unchecked narrowing of a union
- [PASS] useSelectionActions.ts:115: `as ApiQueryParams` matches useMenuCategoryActions.ts:73
```

**Silence is not a pass:** a gate that found none must print `grepped ternaries: 0 hits` / `grepped as-casts: 0 hits`, so a missing receipt can never be mistaken for a clean sweep.
