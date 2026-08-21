# Clarity gate

> The conventions themselves are stated canonically in the kit's `rules/clarity.md`, which loads at authoring time. This file is the review side: the detection criteria and failure modes for grading a diff. Each box stays self-contained so a gate agent needs nothing but this file; when a convention changes, change `rules/clarity.md` first and update the affected boxes here to match.

Readability rules for the diff under review. None of these are automatically wrong — they are prompts to look harder at new logic. Covers sixteen independent failure modes: guard-clause density, defensive coercion, undeclared field access, redundant casts, tangled side effects, comment hygiene, ordered mutations, magic spreads, inline anonymous types, fallback chains, unhappy-path tangling, thin wrappers, dense sub-expressions, circular imports, ternary shape, and magic numbers.

## Gate checklist

The clarity gate agent ticks every box against the diff. A box is FAIL if any matching construct in the new logic reads as unclear per the rule; the gate is FAIL if any box is FAIL. Mark a box N/A only when the diff has no matching construct. These are clarity prompts, so a FAIL is usually a 🟡/🟠 finding, but it still fails the box and therefore the gate.

- [ ] §C1 No dense guard clauses (3+ early returns with non-self-explanatory conditions, uncommented). (N/A: no guard-clause chain in diff)
- [ ] §C2 No defensive coercion on an already-typed value (`Number(x)` on a `number`), except genuinely defensive form/input-boundary comparisons. (N/A: no coercion added)
- [ ] §C3 Every new `record.someField` access is declared on the record's type/interface; optional-chained access to an undeclared field is a FAIL. (N/A: no new field access)
- [ ] §C4 No redundant `as T` assertion on a value the compiler already infers as `T`. **Enumerate by grep, do not eyeball** — see below. (N/A: only when the grep returns 0 hits, stated as `grepped as-casts: 0 hits`)
- [ ] §C5 No side effects inside render/computation closures (map/filter/reduce callbacks, memoized selectors, inline JSX expressions); side effects live in named handlers called from outside the closure. (N/A: no closure with a side effect in diff)
- [ ] §C6 Comments earn their place AND are sparse: none paraphrase the next line or restate a name; the diff does not comment most blocks by default (over-commenting density is itself a FAIL); non-obvious constraints are commented. (N/A: no comments added)
- [ ] §C7 Two-step / order-dependent state mutations have an ordering rationale comment. (N/A: no ordered mutation pair in diff)
- [ ] §C8 No magic spread + override + default mixed in one literal (extract a named value). (N/A: no such literal in diff)
- [ ] §C9 No inline anonymous structural type in a variable declaration (name it at module scope). (N/A: no inline structural type in diff)
- [ ] §C10 Multi-fallback `||`/`??` chains with 3+ operands extracted to a named helper. (N/A: no such chain in diff)
- [ ] §C11 Unhappy-path complexity not tangled into the happy path. (N/A: no error branch with 3+ inline statements)
- [ ] §C12 No thin-wrapper helper whose name only restates a one-line body (over-extraction). (N/A: no new single-purpose helper in diff)
- [ ] §C13 An expression (template literal, call argument, JSX prop, or return) that inlines 2+ non-trivial sub-expressions (each a `??`/optional-chain fallback, call, ternary, or cast) extracts them to named locals first. (N/A: no such multi-part expression in diff)
- [ ] §C14 No circular imports introduced (soft). (N/A: no cross-module import change)
- [ ] §C15 Ternaries: none nested/chained (2+ `?`), long, multi-line once formatted, or with a non-trivial branch (more than a short value/identifier). Applies to value/assignment/returned/arg ternaries too, not just JSX — the branch content is irrelevant, only the shape. Walk every ternary in the diff. **Enumerate by grep, do not eyeball** — see below. (N/A: only when the grep returns 0 hits, stated as `grepped ternaries: 0 hits`)
- [ ] §C16 Bare numeric literals for dimensions/thresholds/timeouts are named constants with a one-line why, or a design token when the project has a token system; a magic value repeated 2+ times is also a DRY finding. (N/A: no magic literal added)

## §C1. Dense guard clauses without comment

Three or more early-returns whose conditions are not self-explanatory. Each guard encodes an assumption about the caller; a future reader needs to know which one they violated.

## §C2. Defensive coercion that hints at unclear types

`Number(x)` on a field whose type says `number`. `value ?? 0` applied right after `...spread` of an object that should already include `value`. These usually mean the author was unsure about the runtime shape and papered over it instead of fixing it upstream.

**Exception — form/input contexts:** types lie about runtime at form/input boundaries. HTML inputs always emit strings, and a form value's declared type is often a union like `string | number | null`. `String(a) === String(b)` between two TS-typed `number`s is **genuinely defensive** there — one side really can arrive as `"42"` while the other is `42`, and `===` would silently return false. Do not flag `String() === String()` (or `Number() === Number()`) when at least one side comes from a form field, an input event, or an autocomplete `onChange`. Flag only when both sides are clearly internal data already typed and constructed in the same scope.

## §C3. Field accesses that "just work" — verify they're on the type

When a PR accesses `record.someField` on a domain model and the field is new (added in this PR or recently on the backend), TypeScript may silently allow it via index signatures on the base type, `any` propagation through optional chaining (`record?.someField` widens to `any` when the field isn't declared), or upstream `as`-casts. The access compiles, the runtime works, the type system catches nothing — typos and backend renames go unflagged.

**Audit:** for every new `record.<field>` access, grep the record's type/interface declaration and confirm the field is declared. If it isn't, the type needs updating in the same PR. Signals this is happening:

- The field is referenced in the new code but doesn't appear in the type's declaration file.
- Hover-typing the access in an editor shows `any`.
- The PR adds the backend column/serializer but doesn't update the TS interface.

**Flag** the access and ask for the field to be added to the interface. Illustration: a PR uses `booking?.packagesEnabled` to gate a tab, but the `Booking` type doesn't declare `packagesEnabled`. Adding `packagesEnabled?: boolean` to the interface makes a typo or rename surface as a compile error.

**Why this slips through:** optional-chained access on a non-declared field is one of TypeScript's quieter failure modes. A reviewer assumes the access is type-safe because the codebase already uses the field elsewhere, but those sites have the same hole. The type definition is the one place that protects every consumer.

## §C4. Redundant type assertions

An `as T` assertion on an expression the compiler already infers as `T` is noise, and worse, it silently masks a later type drift: if the expression's inferred type changes (a helper's return type narrows, a `??` fallback changes), the cast keeps asserting `T` and the mismatch never surfaces. Drop the assertion and let inference stand; keep one only where the compiler genuinely can't infer the type (a `JSON.parse` result, a DOM `querySelector`, an `unknown` boundary).

**Bad** — the expression is already `T`, so the cast adds nothing:

```ts
const value = (maybeThing() ?? fallbackThing()) as Thing
```

**Good** — inference already gives `Thing`:

```ts
const value = maybeThing() ?? fallbackThing()
```

Walk every new `as T` in the diff: if the un-cast expression already types as `T`, the cast is redundant.

## §C5. Side effects out of render/computation closures

Side effects defined inline inside render closures, map/filter/reduce callbacks, or memoized-selector bodies — especially with closed-over indices or refs — force the reader to separate "what this produces" from "what this does" while parsing a single expression. Pull the side effect into a named handler called from outside the closure so the closure stays a pure computation.

## §C6. Comments: prefer self-documenting code, but write them when they earn their place

Comments are fine — the bar is that they have to earn their place. A comment earns its place when it captures something the code itself cannot: a constraint that forced this approach, an invariant the reader needs to know, a workaround for a specific bug, behavior that would surprise a reader.

Default is self-documenting code: descriptive names, small functions, and named lookup objects/helpers do most of the work a comment would otherwise do. A comment that restates a well-named variable or paraphrases the next line is just noise.

**Sparse by default.** Over-commenting is itself a finding, independent of any single comment's quality. If a diff attaches a comment to most blocks, declarations, or config entries, flag the density — the default is *no* comment, and each one has to justify itself. A wall of individually-defensible comments still reads as noise and hides the few that matter. Prefer deleting the obvious ones over keeping a comment on everything.

**Flag comments that:**
- Restate a self-readable line: `// increment counter` above `count++`, or `// fetch the user` above `const user = await fetchUser()`.
- Paraphrase a well-named variable: `// the current row being edited` above `const editingRow = ...`.
- Describe the happy path without naming the constraint that forced this code shape.
- Run on for many lines — a comment longer than ~2 sentences usually means the function itself wants splitting or renaming.
- Appear at high density — a comment on nearly every line/block/attribute — even when each is individually harmless.
- Are grammatically awkward — those often mark spots where the author was working out the logic while typing, and the underlying code usually needs the most attention.

**Do NOT flag comments that:**
- Name a non-obvious constraint (compliance, browser quirk, race-condition guard).
- Explain *why* a surprising-looking pattern is correct (e.g. an order-of-operations requirement).
- Document a known limitation or TODO with enough context to act on later.

If the existing comment is doing useful work but is too long, suggest a tightening rather than a deletion.

## §C7. Two-step state mutations without ordering rationale

`update(...)` then `remove(...)`, or `setX(...)` then `setY(...)` where the order matters. A reader needs to know whether reordering breaks things and why.

## §C8. Magic spreads with overrides

`{ ...source, fieldA: x, fieldB: source.fieldB ?? 0 }` patterns where some fields come from `source`, some are overridden, and some are defaulted. The mix obscures intent. Often clearer as a small helper with a name.

## §C9. Inline anonymous structural types in variable declarations

`let x: { foo?: string; bar?: Array<{ ... }> } & { baz?: string } = {}` is a structural type definition stuffed into a declaration site. The reader has to parse the shape, the intersection, and the initializer at once. Two failure modes:

- The type is doing real work (multiple fields, optional/required mix, intersections) — extract a named `type` at module scope.
- The type is a fragment glued together with `&` for no reason a reader can guess — usually means two shapes are being conflated and would be clearer split into two named types or a discriminated union.

**Bad:**
```ts
let errorBody: { errors?: Array<{ code?: string; detail?: string; title?: string }> } & {
  message?: string
} = {}
```

**Good:**
```ts
type ErrorEntry = { code?: string; detail?: string; title?: string }
type ErrorBody = { errors?: ErrorEntry[]; message?: string }

const body: ErrorBody = {}
```

The named-type version reads in two passes — shape, then usage — instead of one dense pass. The fragment is also reusable across the file.

## §C10. Multi-fallback `||` (or `??`) chains with 3+ operands

`a || b || c || 'default'` reads as "first truthy wins" but readers have to mentally evaluate each operand. Three operands is the threshold; four is always too many. Two failure modes:

- The chain is selecting a value from differently-shaped sources (`firstError?.detail || firstError?.title || body.message || 'fallback'`) — extract to a named function whose name describes the selection.
- The chain mixes `||` and `??` — each has different semantics around falsy vs nullish, and the mix is almost always a bug-magnet. Pick one and document why.

**Bad:**
```ts
const message = firstError?.detail || firstError?.title || body.message || 'Request failed'
```

**Good:**
```ts
const extractErrorMessage = (body: ErrorBody): string => {
  const firstError = body.errors?.[0]
  return firstError?.detail || firstError?.title || body.message || 'Request failed'
}
```

Even keeping the same `||` chain, wrapping it in a named function turns the *thing it does* into the visible name and pushes the implementation detail off the main flow.

## §C11. Unhappy-path complexity tangled into the happy path

When a function's `if (!ok)` branch contains 3+ statements (parse, extract, build, throw) inline with the success path, the body splits its attention. Tighten the unhappy-path work — name what's worth naming, inline what isn't — so the main function reads as a linear story.

**Bad** — fetch + parse error body + extract message + extract code + throw, all in one function body, with an inline anonymous type and a 4-way `||` chain right next to the throw:
```ts
export const request = async (...) => {
  const response = await fetch(...)

  if (!response.ok) {
    let errorBody: { errors?: Array<{ code?: string; detail?: string; title?: string }> } & {
      message?: string
    } = {}
    try { errorBody = await response.json() } catch { /* ... */ }
    const firstError = errorBody.errors?.[0]
    const message = firstError?.detail || firstError?.title || errorBody.message || '...'
    throw new SomeError(message, response.status, firstError?.code, errorBody)
  }

  return (await response.json()) as T
}
```

**Good** — named type at module scope, multi-fallback chain extracted to a named helper, JSON-parse-with-fallback inlined as a one-liner (don't wrap it in a thin helper — see §C12):
```ts
type ErrorBody = { errors?: ErrorEntry[]; message?: string }

const extractErrorMessage = (body: ErrorBody): string => {
  const firstError = body.errors?.[0]
  return firstError?.detail || firstError?.title || body.message || 'Request failed'
}

export const request = async (...) => {
  const response = await fetch(...)

  if (!response.ok) {
    const body: ErrorBody = await response.json().catch(() => ({}))
    const message = extractErrorMessage(body)
    const code = body.errors?.[0]?.code
    throw new SomeError(message, response.status, code, body)
  }

  return (await response.json()) as T
}
```

The named-fallback helper earns its keep (4-way precedence is real logic); the JSON-parse fallback is one expression so it stays inline. The main function reads as a linear story without leaning on thin wrappers.

## §C12. Thin-wrapper helpers — over-extraction is its own smell

§C11 says to extract complexity from a tangled function. The symmetric mistake is extracting *non-complexity*: a helper whose body is so simple the name only restates it. These add indirection (a jump-to-definition) without adding information.

A helper earns its keep when **at least one** of these holds:
- The body has multiple meaningful steps the name summarizes (e.g. `extractErrorMessage` wraps a 4-way fallback chain — the name names the *selection*, the body shows the precedence).
- It's called from 2+ places (eliminates real duplication).
- The body is genuinely subtle and the name encodes a non-obvious invariant.

A helper does NOT earn its keep when:
- The body is one expression with a try/catch fallback — inline as `await x.json().catch(() => defaultValue)`.
- The name is a verb-paraphrase of the body's only statement (`parseBody` wrapping `response.json()`, `getFirstError` wrapping `arr[0]`).
- It's used once and the body is < 3 short lines.

**Bad** (over-correction from a §C11 review):
```ts
const parseErrorBody = async (response: Response): Promise<ErrorBody> => {
  try {
    return await response.json()
  } catch {
    return {}
  }
}

// later...
const body = await parseErrorBody(response)
```

**Good** — inline the try/catch, which is shorter and reads directly:
```ts
const body: ErrorBody = await response.json().catch(() => ({}))
```

When walking §C11 (extract unhappy-path complexity), check each extraction against this rule. The fix for tangled logic is sometimes naming the chain (§C10), sometimes splitting into helpers (§C11), and sometimes just rewriting the original block more tightly. Don't extract reflexively.

## §C13. Dense inlined sub-expressions — extract named locals

When one expression (a template literal, function argument, JSX prop, or `return`) inlines two or more *non-trivial* sub-expressions — each a `??`/optional-chain fallback, a call, a ternary, or a cast — the line does several things at once and reads poorly. Name each sub-expression on its own line first, then compose. A bare identifier or a single property access is trivial and stays inline; the rule triggers on the *second* non-trivial part crammed into the same expression.

**Bad** — two fallbacks inlined into a template + call argument:

```ts
return `${flagA ?? fallbackA()} ${format({ value: predicateB() ?? defaultB(), mode: MODE })}`
```

**Good** — each part named, so the composing expression reads as a sentence:

```ts
const labelA = flagA ?? fallbackA()
const valueB = predicateB() ?? defaultB()

return `${labelA} ${format({ value: valueB, mode: MODE })}`
```

This is the general form of §C10 (a single 3+-operand fallback chain) and the compound-boolean rule (see naming): the fix is always to name the parts before composing.

## §C14. Circular imports (soft)

Be alert to circular imports while reading. They are not a hard blocker (TypeScript and bundlers usually tolerate them), but they signal coupling problems and occasionally cause runtime `undefined` issues at module init.

When you spot a likely cycle (file A imports from B, and B imports from A, even transitively through a third file), flag it as a soft suggestion: "this introduces a likely circular import between X and Y — consider extracting the shared piece to a common module." Do not block on it.

You will not catch every cycle by reading — that is fine. Flag the obvious ones; do not go hunting.

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

**Acceptable single-ternary patterns** (do NOT flag):
- One condition selecting between two values inline: `<Title>{flagA ? 'Confirm' : 'Send Request'}</Title>`.
- A ternary whose branches are single primitive values (a number, a class name, a short string) or a single short identifier, on one line.

### Enumerate ternaries and casts by grep, do not eyeball

§C15 says "walk every ternary in the diff" and §C4 says the same for `as` casts. Both are graded on whether you **listed** them, not on whether you noticed them: reading a long diff and forming impressions is how a multi-line ternary survives on a gate reported as PASS.

Find them mechanically **before** reading for meaning, over the diff's **added lines only** — over the diff you were given (e.g. `gh pr diff <num>` for a PR, `git diff <default-branch>...HEAD` for a branch), e.g.:

```bash
gh pr diff <num> | grep -nE '^\+.*\?' | grep -v '^\+.*\w\?:'   # ternaries, minus optional-property syntax
gh pr diff <num> | grep -nE '^\+.*\bas [A-Z]'                  # type assertions
```

Adapt the pattern to the target language's operators before running (`and`/`or` chains, `a if c else b` conditional expressions, `x.(T)` / `cast()` type assertions, etc.); `0 hits` is only a valid receipt after the language-appropriate pattern was run, and the receipt states which pattern was used.

Both greps over-match, and that is fine — the point is that every candidate gets named and dismissed in writing rather than never being looked at. Expect to discard optional properties (`field?: CustomField`), optional chaining, and `??` from the ternary grep; say so per hit.

Emit one line per hit with a verdict and the count:

```
grepped ternaries: 10 hits (6 discarded: optional-property syntax / `??`)
- [FAIL] someLabel.ts:18 — multi-line, template-literal branch; use an early return
- [PASS] useSelectionResource.ts:27 — single line, both branches trivial
...
grepped as-casts: 3 hits
- [FAIL] SubmissionFieldRow.tsx:29 — unchecked narrowing of a union
- [PASS] useSelectionActions.ts:115 — `as ApiQueryParams` matches useMenuCategoryActions.ts:73
```

**Silence is not a pass:** a gate that found none must print `grepped ternaries: 0 hits` / `grepped as-casts: 0 hits`, so a missing receipt can never be mistaken for a clean sweep.

## §C16. Question magic numbers; use named constants or design tokens

A bare numeric literal for a dimension, threshold, or timeout is a finding — ask why that number; resolve with a named constant (+ one-line *why*) or a design token when the project has a token system for the value's domain.

**Bad** — an unexplained literal repeated across call sites:
```ts
setTimeout(() => retry(), 3000)
// ...elsewhere
setTimeout(() => pollStatus(), 3000)
```

**Good** — named once, with the reasoning attached:
```ts
const RETRY_DELAY_MS = 3000 // matches the backend's exponential-backoff floor

setTimeout(() => retry(), RETRY_DELAY_MS)
setTimeout(() => pollStatus(), RETRY_DELAY_MS)
```

The same intent expressed as different magic numbers (one call site waits `3000`, another waits `2500` for what's meant to be the same delay) is the tell that a shared constant is missing. A magic value repeated 2+ times is also a DRY finding independent of the naming issue.
