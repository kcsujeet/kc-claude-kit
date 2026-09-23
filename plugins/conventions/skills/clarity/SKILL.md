---
name: clarity
description: "Readability conventions for TypeScript, JavaScript and other source files: ternary shape, guard clauses, comments, casts and type escape hatches, magic numbers, fallback chains, dense expressions and over-extraction. Use when writing or reviewing code that adds a ternary, a comment, an `as` cast, `any`, a non-null assertion, a numeric literal, a `??`/`||` fallback chain or a small helper."
user-invocable: false
paths:
  - "**/*.{ts,tsx,js,jsx,mjs,cjs,rb,py,swift,go,java,kt,php,cs,rs}"
---

# Clarity

## Contents

- Rules
- Review checklist
- Review detail
  - §C1. Dense guard clauses without comment
  - §C2. Defensive coercion that hints at unclear types
  - §C3. Field accesses that "just work": verify they're on the type
  - §C4. Redundant type assertions
  - §C5. Side effects out of render/computation closures
  - §C6. Comments: prefer self-documenting code, but write them when they earn their place
  - §C7. Two-step state mutations without ordering rationale
  - §C8. Magic spreads with overrides
  - §C9. Inline anonymous structural types in variable declarations
  - §C10. Multi-fallback `||` (or `??`) chains with 3+ operands
  - §C11. Unhappy-path complexity tangled into the happy path
  - §C12. Thin-wrapper helpers: over-extraction is its own smell
  - §C13. Dense inlined sub-expressions: extract named locals
  - §C14. Circular imports (soft)
  - §C15. Ternaries: flag when nested, long, or multi-line
  - §C16. Question magic numbers; use named constants or design tokens
  - §C17. Type escape hatches: lying casts, `any`, non-null assertions
  - §C18. Do not suggest removing a readable intermediate
- Sweeps

## Rules

Code that takes three readings costs more than code that took an extra minute to write.

- A ternary is out if it nests, runs long, spans lines, or has a non-trivial branch. That applies to value ternaries, not only ones in markup. Use an early return or a named variable.
- Prefer guard-style early returns to a return-value ternary when branching.
- Comments earn their place. Default to none: the code should say what, the comment only the non-obvious why, in one line. Comment density is itself a smell; a block of three explaining a clear function is worse than nothing.
- No defensive coercion on a value the type system already guarantees. No `as T` that only exists to silence an error.
- A magic number becomes a named constant or a design token the first time it appears with meaning.
- Keep the unhappy path out of the happy path: validate and return early rather than nesting the real work inside conditionals.
- A fallback chain of three or more operands is a lookup or a named default, not `a ?? b ?? c ?? d`.
- Resist the symmetric smell too: a wrapper that adds nothing but a name is over-extraction, not clarity.
- A named intermediate that makes a line readable stays, even when it costs an extra type-narrowing step or evaluates a trivial branch eagerly.
- Fixing a ternary must not create a new problem: `flagA && value` is not a stand-in for `value | undefined` (it yields `false`), and an options object spread in conditionally is a hidden ternary.

Detection criteria and per-box review failure modes live in the `## Review checklist` of the `clarity` skill (`conventions:clarity`), with the detail under its `## Review detail`. These rules are the statement of the convention; that checklist is how a diff gets graded against it.

## Review checklist

The clarity gate agent ticks every box against the diff. A box is FAIL if any matching construct in the new logic reads as unclear per the rule; the gate is FAIL if any box is FAIL. Mark a box N/A only when the diff has no matching construct. These are clarity prompts, so a FAIL is usually a 🟡/🟠 finding, but it still fails the box and therefore the gate.

- [ ] §C1 No dense guard clauses (3+ early returns with non-self-explanatory conditions, uncommented). (N/A: no guard-clause chain in diff)
- [ ] §C2 No defensive coercion on an already-typed value (`Number(x)` on a `number`), except genuinely defensive form/input-boundary comparisons. (N/A: no coercion added)
- [ ] §C3 Every new `record.someField` access is declared on the record's type/interface; optional-chained access to an undeclared field is a FAIL. (N/A: no new field access)
- [ ] §C4 No redundant `as T` assertion on a value the compiler already infers as `T`. **Enumerate with the `as-casts.sh` sweep, do not eyeball** — see below. (N/A: only when `as-casts.sh` returns 0 hits, stated as `grepped as-casts: 0 hits`)
- [ ] §C5 No side effects inside render/computation closures (map/filter/reduce callbacks, memoized selectors, inline JSX expressions); side effects live in named handlers called from outside the closure. (N/A: no closure with a side effect in diff)
- [ ] §C6 Comments earn their place AND are sparse: none paraphrase the next line or restate a name; none narrate the task, ticket, or review round instead of the code; the diff does not comment most blocks by default (over-commenting density is itself a FAIL); non-obvious constraints are commented. (N/A: no comments added)
- [ ] §C7 Two-step / order-dependent state mutations have an ordering rationale comment. (N/A: no ordered mutation pair in diff)
- [ ] §C8 No magic spread + override + default mixed in one literal (extract a named value). (N/A: no such literal in diff)
- [ ] §C9 No inline anonymous structural type in a variable declaration (name it at module scope). (N/A: no inline structural type in diff)
- [ ] §C10 Multi-fallback `||`/`??` chains with 3+ operands extracted to a named helper. (N/A: no such chain in diff)
- [ ] §C11 Unhappy-path complexity not tangled into the happy path. (N/A: no error branch with 3+ inline statements)
- [ ] §C12 No thin-wrapper helper whose name only restates a one-line body (over-extraction). (N/A: no new single-purpose helper in diff)
- [ ] §C13 An expression (template literal, call argument, JSX prop, or return) that inlines 2+ non-trivial sub-expressions (each a `??`/optional-chain fallback, call, ternary, or cast) extracts them to named locals first. (N/A: no such multi-part expression in diff)
- [ ] §C14 No circular imports introduced (soft). (N/A: no cross-module import change)
- [ ] §C15 Ternaries: none nested/chained (2+ `?`), long, multi-line once formatted, or with a non-trivial branch (more than a short value/identifier). Applies to value/assignment/returned/arg ternaries too, not just JSX — the branch content is irrelevant, only the shape. Walk every ternary in the diff. A proposed fix respects the remedy limits in §C15 (no `flagA && value` for a value-or-absent prop, no conditionally spread options object). **Enumerate with the `ternaries.sh` sweep, do not eyeball** — see below. (N/A: only when `ternaries.sh` returns 0 hits, stated as `grepped ternaries: 0 hits`)
- [ ] §C16 Bare numeric literals for dimensions/thresholds/timeouts are named constants with a one-line why, or a design token when the project has a token system; a magic value repeated 2+ times is also a DRY finding. (N/A: no magic literal added)
- [ ] §C17 No type escape hatches: no `as` cast (including `as unknown as T`) that asserts a type the value does not actually have in order to silence a mismatch; no `any`, explicit or through an untyped boundary; no non-null assertion (`value!`). **Enumerate with the `as-casts.sh`, `any-types.sh` and `non-null-assertions.sh` sweeps, do not eyeball**; see §C17. (N/A: only when all three sweeps return 0 hits, stated as `grepped as-casts: 0 hits`, `grepped any: 0 hits`, `grepped non-null assertions: 0 hits`)
- [ ] §C18 No finding this gate proposes suggests removing a named intermediate that makes an expression readable on the grounds that it looks redundant, costs a type-narrowing step, or eagerly evaluates a trivial branch the ternary will not take. Sibling gates that propose inlining (simplicity §P6, structure §S4) apply the same test. (N/A: no finding proposes removing a named intermediate)

## Review detail

Readability rules for the diff under review. None of these are automatically wrong — they are prompts to look harder at new logic. Covers eighteen independent failure modes: guard-clause density, defensive coercion, undeclared field access, redundant casts, tangled side effects, comment hygiene, ordered mutations, magic spreads, inline anonymous types, fallback chains, unhappy-path tangling, thin wrappers, dense sub-expressions, circular imports, ternary shape, magic numbers, type escape hatches (lying casts, `any`, non-null assertions), and review suggestions that strip readable intermediates.

### §C1. Dense guard clauses without comment

Three or more early-returns whose conditions are not self-explanatory. Each guard encodes an assumption about the caller; a future reader needs to know which one they violated.

### §C2. Defensive coercion that hints at unclear types

`Number(x)` on a field whose type says `number`. `value ?? 0` applied right after `...spread` of an object that should already include `value`. These usually mean the author was unsure about the runtime shape and papered over it instead of fixing it upstream.

**Exception — form/input contexts:** types lie about runtime at form/input boundaries. HTML inputs always emit strings, and a form value's declared type is often a union like `string | number | null`. `String(a) === String(b)` between two TS-typed `number`s is **genuinely defensive** there — one side really can arrive as `"42"` while the other is `42`, and `===` would silently return false. Do not flag `String() === String()` (or `Number() === Number()`) when at least one side comes from a form field, an input event, or an autocomplete `onChange`. Flag only when both sides are clearly internal data already typed and constructed in the same scope.

### §C3. Field accesses that "just work" — verify they're on the type

When a PR accesses `record.someField` on a domain model and the field is new (added in this PR or recently on the backend), TypeScript may silently allow it via index signatures on the base type, `any` propagation through optional chaining (`record?.someField` widens to `any` when the field isn't declared), or upstream `as`-casts. The access compiles, the runtime works, the type system catches nothing — typos and backend renames go unflagged.

**Audit:** for every new `record.<field>` access, grep the record's type/interface declaration and confirm the field is declared. If it isn't, the type needs updating in the same PR. Signals this is happening:

- The field is referenced in the new code but doesn't appear in the type's declaration file.
- Hover-typing the access in an editor shows `any`.
- The PR adds the backend column/serializer but doesn't update the TS interface.

**Flag** the access and ask for the field to be added to the interface. Illustration: a PR uses `booking?.packagesEnabled` to gate a tab, but the `Booking` type doesn't declare `packagesEnabled`. Adding `packagesEnabled?: boolean` to the interface makes a typo or rename surface as a compile error.

**Why this slips through:** optional-chained access on a non-declared field is one of TypeScript's quieter failure modes. A reviewer assumes the access is type-safe because the codebase already uses the field elsewhere, but those sites have the same hole. The type definition is the one place that protects every consumer.

### §C4. Redundant type assertions

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

### §C5. Side effects out of render/computation closures

Side effects defined inline inside render closures, map/filter/reduce callbacks, or memoized-selector bodies — especially with closed-over indices or refs — force the reader to separate "what this produces" from "what this does" while parsing a single expression. Pull the side effect into a named handler called from outside the closure so the closure stays a pure computation.

### §C6. Comments: prefer self-documenting code, but write them when they earn their place

Comments are fine — the bar is that they have to earn their place. A comment earns its place when it captures something the code itself cannot: a constraint that forced this approach, an invariant the reader needs to know, a workaround for a specific bug, behavior that would surprise a reader.

Default is self-documenting code: descriptive names, small functions, and named lookup objects/helpers do most of the work a comment would otherwise do. A comment that restates a well-named variable or paraphrases the next line is just noise.

**Sparse by default.** Over-commenting is itself a finding, independent of any single comment's quality. If a diff attaches a comment to most blocks, declarations, or config entries, flag the density — the default is *no* comment, and each one has to justify itself. A wall of individually-defensible comments still reads as noise and hides the few that matter. Prefer deleting the obvious ones over keeping a comment on everything.

**Flag comments that:**
- Restate a self-readable line: `// increment counter` above `count++`, or `// fetch the user` above `const user = await fetchUser()`.
- Paraphrase a well-named variable: `// the current row being edited` above `const editingRow = ...`.
- Describe the happy path without naming the constraint that forced this code shape.
- Run on for many lines — a comment longer than ~2 sentences usually means the function itself wants splitting or renaming.
- Appear at high density — a comment on nearly every line/block/attribute — even when each is individually harmless.
- Narrate the task, ticket, or review round rather than the code: `// added for the new checkout flow`, `// changed per review`, `// previously used X`. That history belongs in the commit message, and the comment goes stale the moment it lands.
- Are grammatically awkward — those often mark spots where the author was working out the logic while typing, and the underlying code usually needs the most attention.

**Do NOT flag comments that:**
- Name a non-obvious constraint (compliance, browser quirk, race-condition guard).
- Explain *why* a surprising-looking pattern is correct (e.g. an order-of-operations requirement).
- Document a known limitation or TODO with enough context to act on later.

If the existing comment is doing useful work but is too long, suggest a tightening rather than a deletion.

### §C7. Two-step state mutations without ordering rationale

`update(...)` then `remove(...)`, or `setX(...)` then `setY(...)` where the order matters. A reader needs to know whether reordering breaks things and why.

### §C8. Magic spreads with overrides

`{ ...source, fieldA: x, fieldB: source.fieldB ?? 0 }` patterns where some fields come from `source`, some are overridden, and some are defaulted. The mix obscures intent. Often clearer as a small helper with a name.

### §C9. Inline anonymous structural types in variable declarations

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

### §C10. Multi-fallback `||` (or `??`) chains with 3+ operands

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

### §C11. Unhappy-path complexity tangled into the happy path

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

### §C12. Thin-wrapper helpers — over-extraction is its own smell

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

### §C13. Dense inlined sub-expressions — extract named locals

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

This is the general form of §C10 (a single 3+-operand fallback chain) and the compound-boolean rule (see the `naming` skill, §N2): the fix is always to name the parts before composing.

### §C14. Circular imports (soft)

Be alert to circular imports while reading. They are not a hard blocker (TypeScript and bundlers usually tolerate them), but they signal coupling problems and occasionally cause runtime `undefined` issues at module init.

When you spot a likely cycle (file A imports from B, and B imports from A, even transitively through a third file), flag it as a soft suggestion: "this introduces a likely circular import between X and Y — consider extracting the shared piece to a common module." Do not block on it.

You will not catch every cycle by reading — that is fine. Flag the obvious ones; do not go hunting.

### §C15. Ternaries: flag when nested, long, or multi-line

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
- Never propose a conditionally built partial object spread into a call (`widgetFn({ ...base, ...(flagA ? { optA, optB } : {}) })`). It moves the ternary out of sight instead of removing it; branch at the call site or name the options object instead.
- For trivial branches (string formatting, key building, a cheap lookup), computing both named branches eagerly is the accepted cost of a one-line choice and is not an efficiency finding (§C18).

**Acceptable single-ternary patterns** (do NOT flag):
- One condition selecting between two values inline: `<Title>{flagA ? 'Confirm' : 'Send Request'}</Title>`.
- A ternary whose branches are single primitive values (a number, a class name, a short string) or a single short identifier, on one line.

#### Enumerate ternaries and casts by grep, do not eyeball

§C15 says "walk every ternary in the diff" and §C4 says the same for `as` casts. Both are graded on whether you **listed** them, not on whether you noticed them: reading a long diff and forming impressions is how a multi-line ternary survives on a gate reported as PASS.

Find them mechanically **before** reading for meaning, over the diff's **added lines only** — over the diff you were given (e.g. `gh pr diff <num>` for a PR, `git diff <default-branch>...HEAD` for a branch), saved to a file and passed to two sweeps (see Sweeps):

- `ternaries.sh`: a `?` that is not `?.`, `??`, or an optional `?:`.
- `as-casts.sh`: type assertions, including `as string`, `as const`, `as unknown as T`.

The ternary pattern matches the `?` itself rather than dropping lines, so a line that holds both an optional property and a real ternary is still a hit, and a `?` left at the end of a line by the formatter is caught too.

The scripts match TypeScript and JavaScript syntax. For another language (`and`/`or` chains, `a if c else b` conditional expressions, `x.(T)` / `cast()` type assertions, etc.), run the language-appropriate pattern by hand as well; `0 hits` is only a valid receipt after the language-appropriate pattern was run, and the receipt states which script or pattern was used.

Both greps over-match, and that is fine — the point is that every candidate gets named and dismissed in writing rather than never being looked at. Expect to discard a `?` inside a string or a regex from the ternary grep, and import/export aliases (`import { x as y }`) and the word "as" in comments or strings from the cast grep; say so per hit. `as const` is a hit too: it is usually fine, and the verdict says so.

Emit one line per hit with a verdict and the count:

```
grepped ternaries: 5 hits (1 discarded: `?` inside a regex)
- [FAIL] someLabel.ts:18: multi-line, template-literal branch; use an early return
- [PASS] useSelectionResource.ts:27: single line, both branches trivial
...
grepped as-casts: 3 hits
- [FAIL] SubmissionFieldRow.tsx:29: unchecked narrowing of a union
- [PASS] useSelectionActions.ts:115: `as ApiQueryParams` matches useMenuCategoryActions.ts:73
```

**Silence is not a pass:** a gate that found none must print `grepped ternaries: 0 hits` / `grepped as-casts: 0 hits`, so a missing receipt can never be mistaken for a clean sweep.

### §C16. Question magic numbers; use named constants or design tokens

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

### §C17. Type escape hatches: lying casts, `any`, non-null assertions

§C4 catches a cast that is merely redundant. This box catches the worse case: a cast, an `any`, or a `!` that tells the compiler something untrue so an error goes away. The error was the type system reporting a real mismatch; the escape hatch hides it until runtime.

- **A lying cast.** `const widget = response as Widget` where `response` is a different or wider shape, or the double cast `value as unknown as Widget` that exists only because the single cast was rejected. Fix the type upstream, or parse and narrow the value (a type guard, a schema parse at the boundary). A cast is legitimate only where the compiler genuinely cannot know the type and the code has checked it (a DOM query result, a parsed payload already validated).
- **`any`.** An explicit `: any`, `as any`, or `<any>`, or an untyped parameter or import that widens to `any` and carries a wrong shape through. Use `unknown` and narrow it, or name the real type.
- **Non-null assertion.** `widget!.label` or `items.at(0)!` asserts presence without checking it. Use a guard with an early return, optional chaining with a default, or narrow the type so the value cannot be absent.

**Enumerate by grep, do not eyeball.** The cast hits come from the §C4 sweep above, `as-casts.sh` (one sweep, two verdicts: redundant under §C4, lying under §C17). Add, over the diff's added lines, the `any-types.sh` sweep (`: any`, `<any>`, `as any`, `any[]`) and the `non-null-assertions.sh` sweep (a `!` after a value, not `!=`); see Sweeps.

For another language, also run patterns for its escape hatches (force unwrap, force cast, `# type: ignore`, and so on) by hand, and state which scripts and patterns were run. One line per hit with a verdict, and `grepped any: 0 hits` / `grepped non-null assertions: 0 hits` printed explicitly when true.

### §C18. Do not suggest removing a readable intermediate

A named intermediate that splits an expression into readable parts (a named branch, a named clause, a named sub-expression) is the fix for §C13 and §C15, not a defect. A review, from any gate, must not suggest inlining it because it:

- looks redundant next to the expression it names;
- costs an extra narrowing step for the type checker (the value has to be re-checked after being named);
- eagerly evaluates a branch the ternary will not take, when the branch is trivial (formatting, key building, a cheap lookup).

This does not protect a pure alias that renames one identifier to another with nothing added (`const handleClose = onClose`): that is a dead wrapper (structure §S4). The line is whether the name describes a computed value or only repeats an existing one. The clarity gate grades its own proposed fixes against this box; simplicity §P6 and structure §S4 point here so their inline suggestions pass the same test.

## Sweeps

Save the diff under review to a file (`gh pr diff <num> > /tmp/review.diff`, or `git diff <default-branch>...HEAD > /tmp/review.diff`) and run each script over it; `-` reads the diff from stdin. Each prints one `path:line: text` hit per line, where `line` is the new-side line number, and nothing else. Give every hit its own verdict, and state each receipt on its own line with its count, `0 hits` included.

- `added-lines.sh` (citation map): every added line as `path:line: text`, with the source line number at the head SHA. Cite every finding's line from this output or from a sweep hit, never from a position in the diff file.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/added-lines.sh" <diff-file>
  ```

- `ternaries.sh` (§C15): added lines holding a ternary `?`, skipping `?.`, `??` and optional `?:`. Receipt: `grepped ternaries: N hits`.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/skills/clarity/scripts/ternaries.sh" <diff-file>
  ```

- `as-casts.sh` (§C4, §C17): added lines holding an `as` type assertion, lowercase types and `as const` included. Receipt: `grepped as-casts: N hits`.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/skills/clarity/scripts/as-casts.sh" <diff-file>
  ```

- `any-types.sh` (§C17): added lines holding `: any`, `<any>`, `as any` or `any[]`. Receipt: `grepped any: N hits`.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/skills/clarity/scripts/any-types.sh" <diff-file>
  ```

- `non-null-assertions.sh` (§C17): added lines holding a non-null assertion, skipping `!=`, `!==` and negation. Receipt: `grepped non-null assertions: N hits`.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/skills/clarity/scripts/non-null-assertions.sh" <diff-file>
  ```
