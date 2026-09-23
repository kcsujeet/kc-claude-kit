---
name: naming
description: "Naming conventions for identifiers and file names in TypeScript, JavaScript, Ruby, Python, Swift, Go, Java, Kotlin, PHP, C# and Rust source files: role-not-type names, verb-led function names, named boolean operands, honest names, names unambiguous at the use site, and file names unique without their path. Use when writing or reviewing code that adds or renames a variable, function, boolean, parameter, export or file, or when choosing a name."
user-invocable: false
paths:
  - "**/*.{ts,tsx,js,jsx,mjs,cjs,rb,py,swift,go,java,kt,php,cs,rs}"
---

# Naming

## Contents

- Rules
- Review checklist
- Review detail
  - §N1. Names should describe the *role*, not the *type*
  - §N2. Inline boolean chains: evaluate the operands, not just the outer name
  - §N3. The same predicate repeated in 2+ places gets a named helper
  - §N4. Names must be honest about what the thing does
  - §N5. A name has to be unambiguous where it is READ, not where it is declared
  - §N6. Functions start with a verb
  - §N7. A file name identifies the file without its path
  - §N2 evidence requirement: enumerate boolean chains by grep, do not eyeball
- Sweeps

## Rules

A name is read far more often than it is written, and a wrong one survives refactors. Pick the existing word; do not coin a new one.

- One word per concept, reused everywhere. If the codebase says `booking`, never introduce `reservation` for the same thing.
- Name the role, not the type or the shape: `activeBookings`, not `data`, `result`, `temp`, `items`, `obj`, `arr`.
- Functions read verb-noun: `createBooking`, `listBookings`, `updateBooking`. Not `handle`, `process`, `doStuff`, `save` when it means create-or-update.
- Booleans read as assertions: `isSyncing`, `hasBalance`, `canEdit`, `shouldRetry`.
- A name must read as a true sentence about what it holds. Watch for the four common lies: the subject elided (`items` in a file about invoices), the context borrowed as subject (`total` that is really `taxTotal`), the name left stale after a refactor, and a familiar shape hiding different behaviour (`useQuery` that mutates).
- A boolean chain with two or more non-obvious operands (raw comparisons, enum equality, negations, optional field access) gets **each** operand extracted to its own named boolean. Naming the whole chain does not count: `const canSubmit = a && b > 0 && c !== Locked` still leaves three unnamed conditions for the reader to decode.
- A name must be unambiguous **where it is read**, not where it is declared. Beside the declaration the surrounding lines supply the subject for free; at the use site they do not. A bare generic verb or noun that names the mechanism rather than the subject (`check`, `run`, `wrap`, `guard`, `handle`) is wrong even when it is accurate, and so is any name that collides with an unrelated declaration elsewhere. Applies to locals as much as exports; distance and collision are what matter, not module boundaries.
- A repeated predicate becomes a named helper or type guard. Twice is the threshold.
- Match the language's own casing: `snake_case` columns and plural tables in SQL, `UpperCamelCase` types with the file named after the type, `kebab-case` plural nouns in routes.
- A file name identifies the file without its path. Tabs, search results and stack traces show it bare, so `header.tsx` deep in a feature folder is `widget-list-header.tsx`, and no two files share a basename unless the framework requires it.

Detection criteria and per-box review failure modes live in the `## Review checklist` of the `naming` skill (`conventions:naming`), with the detail under its `## Review detail`. These rules are the statement of the convention; that checklist is how a diff gets graded against it.

## Review checklist

The naming gate agent ticks every box against the diff. A box is FAIL if any matching identifier/expression violates the rule; the gate is FAIL if any box is FAIL. N/A only when the diff adds no new identifiers or boolean expressions.

- [ ] §N1 Role-not-type names: new variables/functions describe the role, not the type (no `data`/`result`/`value`/`temp`/`item`/`obj` for behavior-bearing values); function names describe the effect, not just the trigger. (N/A: no new identifiers)
- [ ] §N2 Inline boolean chains — evaluate the OPERANDS, not just the outer name: any `&&`/`||` chain with 2+ non-obvious operands (raw comparisons, enum (in)equalities, negations, `?.` field access) has EACH non-obvious operand extracted to its own named boolean. Assigning the whole chain to a named boolean does NOT satisfy this. A parenthesized sub-expression in a mixed `&&`/`||` chain (e.g. `(a || b) && c`) also gets its own name — parentheses alone don't pass. Enumerate with the `and-or-chains.sh` sweep, do not eyeball. (N/A: only when `and-or-chains.sh` returns 0 hits, stated as `grepped &&/||: 0 hits`)
- [ ] §N3 Cross-call-site predicate: the same predicate repeated in 2+ places is extracted to a named helper (type guard when narrowing helps). (N/A: no repeated predicate)
- [ ] §N4 Honest names: each new name reads as a sentence that matches the actual behavior/subject — no surface-word gluing, no subject elision, no context-as-subject, no stale-after-refactor names, no familiar-shaped name hiding a different behavior or constraint. (N/A: no new names)
- [ ] §N5 Unambiguous where READ, not where declared: every new identifier (local, destructured value, parameter, closure, returned key, export) is qualified enough to read at its use site without scrolling back to the declaration. A bare generic verb/noun naming the mechanism rather than the subject (`check`, `run`, `wrap`, `guard`, `handle`, `process`, `filter`, `format`, `validate`, and any other single word of that shape) FAILS even though it is accurate, and a collision with an unrelated declaration elsewhere FAILS on its own. Enumerate with the `bare-word-declarations.sh` sweep, do not eyeball. (N/A: only when the diff adds no identifiers, stated as `grepped bare-word declarations: 0 hits`)
- [ ] §N6 Verb-led functions: every new function (declaration, arrow-function const, or object method) starts with a verb that says what calling it does: predicates `is`/`has`/`can`/`should`, value getters `get`/`to`, mutators and handlers `set`/`toggle`/`handle`. A noun-phrase name (`sameOwner`, `itemLabel`, `widgetKey`) reads like a value, not a callable, and FAILS. PascalCase components and `use*` hooks are exempt. Enumerate with the `unverbed-functions.sh` sweep, do not eyeball. (N/A: only when `unverbed-functions.sh` returns 0 hits, stated as `grepped unverbed functions: 0 hits`)
- [ ] §N7 Unique file names: every new file name identifies the file without its path, since tabs, search results, and stack traces show it bare. A basename that already exists elsewhere in the repo FAILS, and so does a generic one (`header.tsx`, `helpers.ts`) deep in a folder whose path carries the only meaning. Framework-mandated names (`index`, `page`, `layout`, `route` and equivalents) are exempt, and a test file is judged by its unit's name. Check collisions with the `file-name-collisions.sh` sweep. (N/A: no new files in diff)

## Review detail

Identifier-naming rules for the diff under review. Covers seven independent failure modes: type-shaped names on behavior-bearing values, undecoded inline boolean chains, repeated predicates that should be a shared helper, names that are dishonest about what the code actually does, names that only read well beside their declaration, noun-phrase names on functions, and file names that need their path to mean anything.

### §N1. Names should describe the *role*, not the *type*

Local variables and function names should let a reader know what the value *means in this domain* without reading the surrounding code.

For booleans, prefer `show…`, `is…`, `has…`, `can…`, `should…` and assemble them from underlying flags so the meaning lives in the name. Illustration:

```ts
const showAdvancedFilters = isPowerUser && Boolean(availableFilters?.length)
const canEditRecord = Boolean(isTeamAdmin ? isProjectAdmin : isOwnerOfCurrentRecord)
```

Flag names like `current`, `data`, `result`, `temp`, `item`, `value`, `flag`, `obj` in business logic — these are type-shaped, not role-shaped, and this applies to every such identifier in the diff, not only ones matching this exact list.

Also flag function names that describe the trigger (`handleX`) but hide the effect. `handleStyleChange` is fine if it just updates one field; if it actually does "revive a soft-deleted row when a new row reuses its style key," the name should say so (e.g. `reviveDeletedRowOnStyleKeyReuse`, or split into a clearly-named helper).

**Apply this just as hard to inline boolean expressions.** A `&&`/`||` chain inside an `if`, `find`, `filter`, ternary, or guard clause is where naming pays off the most — each operand usually encodes a separate domain concept, and a reader has to decode all of them in their head. Extract named booleans (or a named predicate function) when the chain has 2+ non-obvious conditions. This continues in §N2.

### §N2. Inline boolean chains — evaluate the operands, not just the outer name

The rule is about the **operands**, not the variable the chain is assigned to. A `&&`/`||` chain with 2+ non-obvious operands — raw comparisons (`x > 0`), enum (in)equalities (`s !== SomeEnum.FOO`), negations (`!x`), `?.` field access — needs EACH non-obvious operand extracted to its own named boolean.

**Assigning the whole chain to a named boolean does NOT satisfy this.** `const canSubmit = a && b > 0 && c !== SomeEnum.LOCKED` still FAILS because the right-hand-side operands are unnamed. "It's already a `canX`/`isX`/`hasX`" is not an exemption — that rationalization is a documented miss. Walk the right-hand side of every named boolean, not just its name.

Bad — three operands, none named:

```ts
const previouslyDeletedRow = rows.find(
  (row, i) =>
    i !== index && row?._destroy && String(row.groupId) === String(currentGroup.id)
)
```

Good — each operand named, the assembly reads in domain language:

```ts
const previouslyDeletedRow = rows.find((row, i) => {
  const isDifferentRow = i !== index
  const isMarkedForDeletion = Boolean(row?._destroy)
  const matchesCurrentGroup = String(row.groupId) === String(currentGroup.id)
  return isDifferentRow && isMarkedForDeletion && matchesCurrentGroup
})
```

The named-booleans version reads top-to-bottom in the domain language. The original requires translation. Flag any inline boolean chain where you cannot name what each operand means without rereading the surrounding code.

**Recurring failure mode: defensive `?.` + `!== undefined` chains stacked on top of a `Boolean()` guard.** When this shape appears, the first reaction shouldn't be "tighten the type check" — it should be "extract named booleans, and most of the defensiveness disappears."

Bad — three operands, two style smells, all in one inline chain:

```ts
const showBalanceCard =
  Boolean(account) &&
  Boolean(planSettings?.balance_display_enabled) &&
  account?.current_balance !== undefined
```

The `?.` on the third clause exists because `Boolean(account)` doesn't narrow `account` for the type checker; the `!== undefined` exists because nobody trusted what the API would return. Both fall out the moment names are extracted:

Good:

```ts
const hasAccount = Boolean(account)
const isBalanceDisplayEnabled = Boolean(planSettings?.balance_display_enabled)
const showBalanceCard = hasAccount && isBalanceDisplayEnabled
```

Now `Boolean()` wraps are localized to single-truthy-check predicates (where they're harmless), the always-serialized API field is trusted (where it should be), and the assembly reads as one role-named line. When a clause still genuinely needs to access a field, write `account && account.field …` inline so the type checker narrows and the code doesn't fight the type system. Avoid `account !== null` specifically — it's brittle to any other falsy value; use `Boolean(account)` for a pure truthy check, or `account && …` when narrowing matters.

**An outer named boolean does NOT exempt its right-hand side.** This is a documented review miss: a chain assigned to a `canX`/`isX`/`hasX` was passed because "it's the extracted-named-boolean good pattern," while its operands were still raw comparisons and enum checks. The rule applies to the operands of the chain, not just the name it lands in. If the RHS has 2+ non-obvious operands (a comparison like `x > 0`, an enum inequality like `s !== SomeEnum.FOO`, a negation, a `?.` access), extract each one — even though the whole thing already has a good name.

Bad — good outer name, but the RHS is an un-decoded chain of non-obvious operands:

```ts
const canSubmit = record.featureEnabled && record.count > 0 && record.status !== Status.LOCKED
```

Good — each non-obvious operand named; the assembly reads in domain language:

```ts
const hasItems = record.count > 0
const isLocked = record.status === Status.LOCKED
const canSubmit = record.featureEnabled && hasItems && !isLocked
```

The tell that this rule was skipped: a reviewer note that says a named boolean "matches the good-pattern example, so the box passes" without having read what its operands are. A chain passes only when its own operands are already named or trivially obvious — never because the assignment target has a good name. Always read the operands, on every hit, not just the ones that look complex at a glance.

**Mixed `&&`/`||` chains also need their grouping named, not just parenthesized.** Parentheses tell the reader precedence, not meaning — `(a || b) && c` still forces them to figure out what the parenthesized group *represents* before they can read the rest. Extract the grouped sub-expression to its own name so the outer expression reads as a sentence.

Bad — parentheses disambiguate precedence but the group is unnamed:

```ts
const canShow = (isAdmin || isOwner) && hasAccess
```

Good — the group gets a name, the outer expression reads as a sentence:

```ts
const hasElevatedRole = isAdmin || isOwner
const canShow = hasElevatedRole && hasAccess
```

### §N3. The same predicate repeated in 2+ places gets a named helper

When the same predicate appears in 2+ places, extract it to a named function — not just a local boolean. A local `const isX = ...` only names it for one scope; a duplicate elsewhere creates a drift risk (one site updates, the other doesn't). The same applies to JSX `&&` chains, `catch` blocks, derived selectors, and hook bodies. Use a type guard (`(x: unknown): x is T => ...`) when narrowing is useful at the call site.

Bad — the same predicate in a derived boolean and a catch block, drift-prone:

```ts
const isConflictError =
  error instanceof SomeError && error.status === 409 && error.code === 'resource_conflict'
// ...
catch (e) {
  if (e instanceof SomeError && e.status === 409 && e.code === 'resource_conflict') {
    onConflict?.()
  }
}
```

Good — single type-guard helper, used at both sites:

```ts
export const isConflictError = (error: unknown): error is SomeError =>
  error instanceof SomeError && error.status === 409 && error.code === 'resource_conflict'

const showSubmitError = isError && !isConflictError(error)
catch (e) { if (isConflictError(e)) onConflict?.() }
```

This box is independent of §N2: a chain can already have all its operands named (§N2 clean) while still repeating the whole predicate at 2+ call sites (§N3 violation), and vice versa. Check both separately.

### §N4. Names must be honest about what the thing does

A name that pattern-matches the surrounding domain words but doesn't actually describe what the function / value / field / component does is worse than a generic name — readers trust it and reason wrong.

**The test:** read the name as a sentence and predict the behavior from the name alone. If a reader would expect a different verb (or a different subject) than what the code actually does, the name is dishonest. Rename.

Applies to functions, hooks, fields, props, components, arguments — anywhere a name has to carry meaning across a file or module boundary.

**Failure modes (illustrations, not an exhaustive list — apply the sentence test to every new name, including shapes not listed here):**

- **Surface-word gluing.** Composing a name by gluing domain nouns from the URL/path/route/folder, even when one of them isn't the actual subject. Catches the eye in code review precisely because the words *feel* right.
- **Subject elision.** Second noun is a destination/action, subject is missing or assumed — `groupLogin`, `accountUpdate`, `orderDelete` all imply a subject the reader has to guess.
- **Context-as-subject confusion.** A noun like `group`, `org`, `customer` reads as the subject but is actually a *scope* under which the real action runs.
- **Type-shaped names for behavior-bearing values.** `data`, `result`, `value`, `obj`, `temp` — these tell you the type, not the role (§N1, called out again here for the same reason).
- **Stale names after refactor.** The function used to do what its name said; the behavior changed; the name didn't. Always a review opportunity when the surrounding logic moved.
- **Familiar-shaped name hiding a constraint or different behavior.** A name that looks like a conventional pattern (`add`, `getAll`, `update`, `find`, `parse`, `validate`, anything readers reach for from muscle memory) but the actual implementation does something different or adds a hidden constraint. The familiarity makes readers skip the check — that's exactly when the name needs to surface the deviation. The signal to flag: the name maps to a well-known operation, but the parameters or behavior tell a different story (`add(a, b)` that subtracts, `getAll(id)` that hits a scoped-down endpoint, `parse(json)` that also mutates a cache, `validate(x)` that throws instead of returning a result). The hidden behavior belongs in the name.

**Worked example.** Path builders that read as "invite the group / org itself" but actually return member-invite URLs:

Bad:

```ts
export const groupInvitePath = (groupId: string) => `/portal/group/${groupId}/invite`
export const orgInvitePath = (orgId: string) => `/portal/organization/${orgId}/invite`
```

Read aloud: "group invite path", "org invite path". A new reader infers *invite the group itself*. But the invite has nothing to do with the group/org as the *target*; the group is the scoping domain, the org is contextual scope, and the real subject is the *member* being invited.

Good:

```ts
export const groupMemberInvitePath = (groupId: string) => `/portal/group/${groupId}/invite`
export const orgMemberInvitePath = (orgId: string) => `/portal/organization/${orgId}/invite`
```

Now the subject (`member`) is in the name and the prefix (`group`/`org`) reads as the calling context.

**How to spot during review:** look at any new exported name and rephrase it as a sentence. If you can't say it without inventing missing words, or the inferred sentence doesn't match the body of the function, flag it. Don't accept "the URL/folder/path already says this" — the name has to stand on its own outside that context.

### §N5. A name has to be unambiguous where it is READ, not where it is declared

Every identifier is read twice: once beside its declaration, where the surrounding lines supply the subject for free, and once at its use site, where they do not. A name that only works in the first position is a review miss waiting to happen, and reviewing it in the first position is what causes the miss.

Applies to every identifier, not just exported ones: locals, destructured values, parameters, closures, returned keys, exports. Distance and collision are what matter, not module boundaries. An export is simply the extreme case, because its use site is guaranteed to be in another file.

**This is a distinct failure mode from §N1 and §N4, and that is exactly why it slips.** The name is not type-shaped, so §N1 passes. The name is not dishonest, so §N4 passes: the thing really does check / wrap / run. What it lacks is a *subject*, and the subject was free at the declaration.

Walk each box independently; failing one is a finding:

- [ ] The identifier is a single generic verb or noun naming the *mechanism* rather than the subject.
- [ ] It is read far from where it is declared: a different function, a template branch, a nested callback, another file.
- [ ] Another declaration of the same bare identifier exists elsewhere in the repo for an unrelated purpose.
- [ ] Sibling identifiers at the use site are built from the same word (`fooWrapped`, `wrappedFoo`, `wrapper`), so this one no longer stands out.

Bad — accurate, and useless where it is used:
```ts
const check = <A extends unknown[], R>(action: (...args: A) => R) => /* ... */
// ...forty lines of unrelated body...
const handleArchive = check(() => archive(id))
```

`check(...)` at the bottom says nothing about what is being checked, and a reader has to scroll back to find out which of the codebase's several `check` helpers this is. It reads perfectly well on the line above the declaration, which is where a reviewer looks.

Good — the subject travels with the name:
```ts
const checkRetentionPolicy = <A extends unknown[], R>(action: (...args: A) => R) => /* ... */

const handleArchive = checkRetentionPolicy(() => archive(id))
```

**Enumerate by grep, do not eyeball.** Genericness and collisions are both mechanical. Run the `bare-word-declarations.sh` sweep (see Sweeps) to list every new declaration over the diff's added lines, pick out each one whose name is a single bare word, then grep that name across the repo:

```bash
grep -rn "\b<name>\b" <source dirs> | grep -v <vendor dir>
```

One line per identifier in the gate evidence, with the collision count:

```
grepped bare-word declarations: 4 hits
- [PASS] useSomeResource.ts:31 `useSomeResource`: subject in the name
- [FAIL] useRetentionPolicy.ts:24 `check`: generic verb, no subject; 3 unrelated `check` declarations elsewhere
- [FAIL] SomePage.tsx:51 `guard`: local, read 9 lines away; collides with an unrelated `guard`
- [PASS] retentionPolicy.ts:12 `isRetained`: subject in the name
```

`0 hits` must be printed explicitly, so silence can never be read as a pass.

### §N6. Functions start with a verb

A function name is read at call sites, where a noun phrase looks like a value: `if (sameOwner(a, b))` reads as indexing into something, and `const label = itemLabel(item)` hides that work happens. Lead with the verb that says what the call does.

| Shape | Prefix | Illustration |
|---|---|---|
| Boolean predicate | `is`, `has`, `can`, `should` | `sameOwner` → `isSameOwner` |
| Returns a value | `get`, `to`, or a precise verb (`parse`, `format`, `build`) | `itemLabel` → `getItemLabel`, `widgetKey` → `getWidgetKey` |
| Mutates or handles | `set`, `toggle`, `handle`, `update` | `selection` → `toggleSelection` |

**Not flagged:** a function already led by a clear action verb (`detectMode`, `resolveOwner`, `renderRow`); React components (PascalCase); hooks (`use*`). A bare verb with no subject (`check`, `run`) passes this box but fails §N5; walk both.

**Enumerate by grep, do not eyeball.** Run the `unverbed-functions.sh` sweep (see Sweeps): over the diff's added lines, it lists function declarations whose name does not start with a known verb.

If the target repo has its own established verbs, the script's allowlist does not know them: dismiss those hits in writing, naming the repo verb. For a language other than JavaScript or TypeScript, adapt the declaration pattern and run it by hand. The grep over-matches: an IIFE assigned to a value (`const total = (() => { ... })()`) is a value, not a callable, and is dismissed in writing. Object methods (`label() {`, `label: () =>`) are not matched by the pattern; read them in the diff. One line per hit with a verdict, and the count:

```
grepped unverbed functions: 3 hits
- [FAIL] widget-utils.ts:12 `sameOwner`: predicate without `is`; `isSameOwner`
- [FAIL] widget-utils.ts:20 `itemLabel`: value getter without `get`; `getItemLabel`
- [PASS] widget-panel.tsx:8 `total`: IIFE assigned to a value, not a function
```

`0 hits` must be printed explicitly.

### §N7. A file name identifies the file without its path

A file's name is what shows in an editor tab, a search result, a stack trace, and a diff header, usually with the path cut off. A name that only means something with its folders attached is a lookup every time someone meets it, and a name shared with another file sends them to the wrong one.

**Flag:**
- A new file whose basename already exists elsewhere in the repo.
- A generic basename (`header.tsx`, `helpers.ts`, `types.ts`, `utils.ts`) deep in a feature folder, where only the path says what it is for. The fix carries the subject into the name: `widget-list-header.tsx`.

**Not flagged:** framework-mandated names the tooling looks up by name (`index`, `page`, `layout`, `route`, and equivalents); a test file, which carries its unit's name plus the test suffix and is judged by that unit's name.

**Check mechanically.** Run the `file-name-collisions.sh` sweep (see Sweeps) from the repo root. For each file the diff adds (including untracked files on a local branch), it counts basename matches across the repo and prints the new files whose basename another file already has.

Every printed file is a collision. A new file it does not print still gets the generic-name read. One line per new file in the evidence, stated as `checked new file names: N files, M collisions`.

### §N2 evidence requirement: enumerate boolean chains by grep, do not eyeball

The §N2 box is graded on whether you **listed** the chains, not on whether you noticed them. Reading a long diff and forming impressions is how a three-operand guard slips through while the reviewer still ticks the box: the miss that prompted this rule was a three-clause `if (!a || !b || a.index === b.index) return` buried in a 1,000-line diff, on a gate reported as PASS.

Chains are greppable, so find them mechanically **before** reading for meaning, over the diff's **added lines only** — over the diff you were given (e.g. `gh pr diff <num>` for a PR, `git diff <default-branch>...HEAD` for a branch), saved to a file and passed to the `and-or-chains.sh` sweep (see Sweeps).

The script matches `&&` and `||`. For a language with other operators (`and`/`or` chains, `a if c else b` conditional expressions, `x.(T)` / `cast()` type assertions, etc.), run the language-appropriate pattern by hand as well; `0 hits` is only a valid receipt after the language-appropriate pattern was run, and the receipt states which script or pattern was used.

A condition split one clause per line yields one hit per line, and each line on its own looks like a single operand. Before giving a verdict, reassemble the whole condition from its first line to its last and count the clauses, not the lines: a four-clause `Boolean(...)` wrapped one clause per line is four operands, the same as if it were on one line. Give the verdict once, on the condition's first line, and mark the continuation hits as part of it.

Then produce one line per hit in the gate evidence, with a verdict and the count:

```
grepped &&/||: 6 hits
- [PASS] CheckoutForm.tsx:40: `canUseCustomFields &&` single named operand
- [FAIL] SubmissionFields.tsx:77: 3 unnamed operands (two `!` of optional chains, one raw comparison)
- [PASS] useSubmissionForm.ts:56: chain assigned to `sameMembership`, operands readable
...
```

A group line ("booleans look fine") is insufficient. **Silence is not a pass:** a gate that found none must print `grepped &&/||: 0 hits`, so "no receipt" can never be mistaken for "nothing there." Single-operand JSX guards (`{editMode && <X />}`) pass trivially, but they still get listed — the count is what proves the sweep ran.

When a checklist box cites a convention rather than a hard rule (e.g. what counts as an established helper name in this codebase), grep the target repo for 2–3 existing examples before citing the convention — do not assert a house style from memory.

## Sweeps

Save the diff under review to a file (`gh pr diff <num> > /tmp/review.diff`, or `git diff <default-branch>...HEAD > /tmp/review.diff`) and run each script over it; `-` reads the diff from stdin. Each prints one `path:line: text` hit per line, where `line` is the new-side line number, and nothing else. Give every hit its own verdict, and state the receipt with its count, `0 hits` included.

- `added-lines.sh` (citation map): every added line as `path:line: text`, with the source line number at the head SHA. Cite every finding's line from this output or from a sweep hit, never from a position in the diff file.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/added-lines.sh" <diff-file>
  ```

- `and-or-chains.sh` (§N2): added lines holding `&&` or `||`. Receipt: `grepped &&/||: N hits`.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/skills/naming/scripts/and-or-chains.sh" <diff-file>
  ```

- `bare-word-declarations.sh` (§N5): added declarations whose name starts lowercase; the bare-word ones are then grepped across the repo. Receipt: `grepped bare-word declarations: N hits`.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/skills/naming/scripts/bare-word-declarations.sh" <diff-file>
  ```

- `unverbed-functions.sh` (§N6): added function declarations whose name does not start with a known verb. Receipt: `grepped unverbed functions: N hits`.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/skills/naming/scripts/unverbed-functions.sh" <diff-file>
  ```

- `file-name-collisions.sh` (§N7): new and untracked files whose basename another file in the repo already has. It reads repository state, so run it from the repo root, or pass the root as a second argument. Receipt: `checked new file names: N files, M collisions`.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/skills/naming/scripts/file-name-collisions.sh" <diff-file>
  ```
