# Naming gate

> The conventions themselves are stated canonically in the kit's `rules/naming.md`, which loads at authoring time. This file is the review side: the detection criteria and failure modes for grading a diff. Each box stays self-contained so a gate agent needs nothing but this file; when a convention changes, change `rules/naming.md` first and update the affected boxes here to match.

Identifier-naming rules for the diff under review. Covers four independent failure modes: type-shaped names on behavior-bearing values, undecoded inline boolean chains, repeated predicates that should be a shared helper, and names that are dishonest about what the code actually does.

## Gate checklist

The naming gate agent ticks every box against the diff. A box is FAIL if any matching identifier/expression violates the rule; the gate is FAIL if any box is FAIL. N/A only when the diff adds no new identifiers or boolean expressions.

- [ ] §N1 Role-not-type names: new variables/functions describe the role, not the type (no `data`/`result`/`value`/`temp`/`item`/`obj` for behavior-bearing values); function names describe the effect, not just the trigger. (N/A: no new identifiers)
- [ ] §N2 Inline boolean chains — evaluate the OPERANDS, not just the outer name: any `&&`/`||` chain with 2+ non-obvious operands (raw comparisons, enum (in)equalities, negations, `?.` field access) has EACH non-obvious operand extracted to its own named boolean. Assigning the whole chain to a named boolean does NOT satisfy this. A parenthesized sub-expression in a mixed `&&`/`||` chain (e.g. `(a || b) && c`) also gets its own name — parentheses alone don't pass. Enumerate by grep, do not eyeball. (N/A: only when the grep returns 0 hits, stated as `grepped &&/||: 0 hits`)
- [ ] §N3 Cross-call-site predicate: the same predicate repeated in 2+ places is extracted to a named helper (type guard when narrowing helps). (N/A: no repeated predicate)
- [ ] §N4 Honest names: each new name reads as a sentence that matches the actual behavior/subject — no surface-word gluing, no subject elision, no context-as-subject, no stale-after-refactor names, no familiar-shaped name hiding a different behavior or constraint. (N/A: no new names)

## §N1. Names should describe the *role*, not the *type*

Local variables and function names should let a reader know what the value *means in this domain* without reading the surrounding code.

For booleans, prefer `show…`, `is…`, `has…`, `can…`, `should…` and assemble them from underlying flags so the meaning lives in the name. Illustration:

```ts
const showAdvancedFilters = isPowerUser && Boolean(availableFilters?.length)
const canEditRecord = Boolean(isTeamAdmin ? isProjectAdmin : isOwnerOfCurrentRecord)
```

Flag names like `current`, `data`, `result`, `temp`, `item`, `value`, `flag`, `obj` in business logic — these are type-shaped, not role-shaped, and this applies to every such identifier in the diff, not only ones matching this exact list.

Also flag function names that describe the trigger (`handleX`) but hide the effect. `handleStyleChange` is fine if it just updates one field; if it actually does "revive a soft-deleted row when a new row reuses its style key," the name should say so (e.g. `reviveDeletedRowOnStyleKeyReuse`, or split into a clearly-named helper).

**Apply this just as hard to inline boolean expressions.** A `&&`/`||` chain inside an `if`, `find`, `filter`, ternary, or guard clause is where naming pays off the most — each operand usually encodes a separate domain concept, and a reader has to decode all of them in their head. Extract named booleans (or a named predicate function) when the chain has 2+ non-obvious conditions. This continues in §N2.

## §N2. Inline boolean chains — evaluate the operands, not just the outer name

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

## §N3. The same predicate repeated in 2+ places gets a named helper

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

## §N4. Names must be honest about what the thing does

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

## §N2 evidence requirement: enumerate boolean chains by grep, do not eyeball

The §N2 box is graded on whether you **listed** the chains, not on whether you noticed them. Reading a long diff and forming impressions is how a three-operand guard slips through while the reviewer still ticks the box: the miss that prompted this rule was a three-clause `if (!a || !b || a.index === b.index) return` buried in a 1,000-line diff, on a gate reported as PASS.

Chains are greppable, so find them mechanically **before** reading for meaning, over the diff's **added lines only** — over the diff you were given (e.g. `gh pr diff <num>` for a PR, `git diff <default-branch>...HEAD` for a branch), e.g.:

```bash
gh pr diff <num> | grep -nE '^\+.*(\&\&|\|\|)'
```

Adapt the pattern to the target language's operators before running (`and`/`or` chains, `a if c else b` conditional expressions, `x.(T)` / `cast()` type assertions, etc.); `0 hits` is only a valid receipt after the language-appropriate pattern was run, and the receipt states which pattern was used.

Then produce one line per hit in the gate evidence, with a verdict and the count:

```
grepped &&/||: 6 hits
- [PASS] CheckoutForm.tsx:40 — `canUseCustomFields &&` single named operand
- [FAIL] SubmissionFields.tsx:77 — 3 unnamed operands (two `!` of optional chains, one raw comparison)
- [PASS] useSubmissionForm.ts:56 — chain assigned to `sameMembership`, operands readable
...
```

A group line ("booleans look fine") is insufficient. **Silence is not a pass:** a gate that found none must print `grepped &&/||: 0 hits`, so "no receipt" can never be mistaken for "nothing there." Single-operand JSX guards (`{editMode && <X />}`) pass trivially, but they still get listed — the count is what proves the sweep ran.

When a checklist box cites a convention rather than a hard rule (e.g. what counts as an established helper name in this codebase), grep the target repo for 2–3 existing examples before citing the convention — do not assert a house style from memory.
