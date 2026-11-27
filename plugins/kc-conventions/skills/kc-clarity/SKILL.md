---
name: kc-clarity
description: "Readability conventions for source files: ternaries, guard clauses, comments, casts, `any`, non-null assertions, magic numbers, `??`/`||` fallback chains, dense expressions, over-extraction. Use when writing or reviewing code that adds any of these or a small helper."
user-invocable: false
paths:
  - "**/*.{ts,tsx,js,jsx,mjs,cjs,rb,py,swift,go,java,kt,php,cs,rs}"
---

# Clarity

## Contents

- Review checklist
- Sweeps

## Review checklist

Tick every box for each construct you add or change. Report each: PASS, FAIL (file:line) or N/A (why).

- [ ] §C1 No dense guard clauses (3+ early returns with non-self-explanatory conditions, uncommented). (N/A: no guard-clause chain in diff)
- [ ] §C2 No defensive coercion on an already-typed value (`Number(x)` on a `number`), except genuinely defensive form/input-boundary comparisons. (N/A: no coercion added)
- [ ] §C3 Every new `record.someField` access is declared on the record's type/interface; optional-chained access to an undeclared field is a FAIL. (N/A: no new field access)
- [ ] §C4 No redundant `as T` assertion on a value the compiler already infers as `T`. **Enumerate with the `as-casts.sh` sweep, do not eyeball**; the evidence format is in §C15's detail file. (N/A: only when `as-casts.sh` returns 0 hits, stated as `grepped as-casts: 0 hits`)
- [ ] §C5 No side effects inside render/computation closures (map/filter/reduce callbacks, memoized selectors, inline JSX expressions); side effects live in named handlers called from outside the closure. (N/A: no closure with a side effect in diff)
- [ ] §C6 Comments earn their place AND are sparse: none paraphrase the next line or restate a name; none narrate the task, ticket, or review round instead of the code; the diff does not comment most blocks by default (over-commenting density is itself a FAIL); non-obvious constraints are commented. (N/A: no comments added)
- [ ] §C7 Two-step / order-dependent state mutations have an ordering rationale comment. (N/A: no ordered mutation pair in diff)
- [ ] §C8 No magic spread + override + default mixed in one literal (extract a named value). (N/A: no such literal in diff)
- [ ] §C9 No inline anonymous structural type in a variable declaration (name it at module scope). (N/A: no inline structural type in diff)
- [ ] §C10 Multi-fallback `||`/`??` chains with 3+ operands extracted to a named helper. (N/A: no such chain in diff)
- [ ] §C11 Unhappy-path complexity not tangled into the happy path. (N/A: no error branch with 3+ inline statements)
- [ ] §C12 No thin-wrapper helper whose name only restates a one-line body (over-extraction); a second caller does not rescue a plain one-expression helper (simplicity §P11). (N/A: no new single-purpose helper in diff)
- [ ] §C13 An expression (template literal, call argument, JSX prop, assignment, or return) that inlines 2+ non-trivial sub-expressions (each a `??`/optional-chain fallback, call, ternary, or cast), a call chain of 3+ links, or calls nested 3+ deep extracts them to named locals first. **Enumerate with the `dense-expressions.sh` sweep, do not eyeball**: one verdict per hit, and `verify-gate-blocks.sh` fails the round when the receipt's count is not the script's or a hit has no `path:line` verdict. (N/A: only when `dense-expressions.sh` returns 0 hits, stated as `grepped dense expressions: 0 hits`)
- [ ] §C14 No circular imports introduced (soft). A cycle through a module that does work at definition time is correctness §B6, which fails. (N/A: no cross-module import change)
- [ ] §C15 Ternaries: none nested/chained (2+ `?`), long, multi-line once formatted, or with a non-trivial branch (more than a short value/identifier). Applies to value/assignment/returned/arg ternaries too, not just JSX — the branch content is irrelevant, only the shape. Walk every ternary in the diff. A proposed fix respects the remedy limits in §C15 (no `flagA && value` for a value-or-absent prop, no conditionally spread options object). **Enumerate with the `ternaries.sh` sweep, do not eyeball**, labelling every hit single-line or MULTI-LINE; see §C15. (N/A: only when `ternaries.sh` returns 0 hits, stated as `grepped ternaries: 0 hits`)
- [ ] §C16 Bare numeric literals for dimensions/thresholds/timeouts are named constants with a one-line why, or a design token when the project has a token system; a magic value repeated 2+ times is also a DRY finding. **Enumerate with the `numeric-literals.sh` sweep**, one verdict per hit. (N/A: only when `numeric-literals.sh` returns 0 hits, stated as `grepped numeric literals: 0 hits`)
- [ ] §C17 No type escape hatches: no `as` cast (including `as unknown as T`) that asserts a type the value does not actually have in order to silence a mismatch; no `any`, explicit or through an untyped boundary; no non-null assertion (`value!`). **Enumerate with the `as-casts.sh`, `any-types.sh` and `non-null-assertions.sh` sweeps, do not eyeball**; see §C17. (N/A: only when all three sweeps return 0 hits, stated as `grepped as-casts: 0 hits`, `grepped any: 0 hits`, `grepped non-null assertions: 0 hits`)
- [ ] §C18 No finding this gate proposes suggests removing a named intermediate that makes an expression readable on the grounds that it looks redundant, costs a type-narrowing step, or eagerly evaluates a trivial branch the ternary will not take. Sibling gates that propose inlining (simplicity §P6, structure §S4) apply the same test. (N/A: no finding proposes removing a named intermediate)
- [ ] §C19 No conditional spread, of any size and whatever its comment: no `...(flagA ? { key } : {})` or `...(flagA && { key })` inline, and no object built conditionally (`const extra = flagA && { key }`) and spread later into an object or as component props. The fix gives the key or prop a permanent slot set to `undefined` when absent, and the finding confirms the consumer drops `undefined`. **Enumerate with the `conditional-spreads.sh` sweep.** (N/A: only when `conditional-spreads.sh` returns 0 hits, stated as `grepped conditional spreads: 0 hits`)
- [ ] §C20 Comments about other code are true: every added or edited comment that states another unit's behaviour (a caller, a reader, a response's contents) was checked against that unit, with the unit named in the evidence; a claim the code does not bear out FAILS. **Enumerate** such comments. (N/A: no such comment added or edited)

Examples and edge cases per box: references/detail.md (read when a box is unclear).

## Sweeps

Save the diff under review to a file (`gh pr diff <num> > /tmp/review.diff`, or `git diff <default-branch>...HEAD > /tmp/review.diff`) and run each script over it; `-` reads the diff from stdin. Each prints one `path:line: text` hit per line, where `line` is the new-side line number, and nothing else. Give every hit its own verdict, and state each receipt on its own line with its count, `0 hits` included.

- `added-lines.sh` (citation map): every added line as `path:line: text`, with the source line number at the head SHA. Cite every finding's line from this output or from a sweep hit, never from a position in the diff file.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/added-lines.sh" <diff-file>
  ```

- `ternaries.sh` (§C15): added lines holding a ternary `?`, skipping `?.`, `??` and optional `?:`. Receipt: `grepped ternaries: N hits`.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/skills/kc-clarity/scripts/ternaries.sh" <diff-file>
  ```

- `as-casts.sh` (§C4, §C17): added lines holding an `as` type assertion, lowercase types and `as const` included. Receipt: `grepped as-casts: N hits`.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/skills/kc-clarity/scripts/as-casts.sh" <diff-file>
  ```

- `any-types.sh` (§C17): added lines holding `: any`, `<any>`, `as any` or `any[]`. Receipt: `grepped any: N hits`.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/skills/kc-clarity/scripts/any-types.sh" <diff-file>
  ```

- `conditional-spreads.sh` (§C19): added lines holding `...(`, an object built with `= ... && {`, or a ternary whose other branch is `{}`. Receipt: `grepped conditional spreads: N hits`.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/skills/kc-clarity/scripts/conditional-spreads.sh" <diff-file>
  ```

- `non-null-assertions.sh` (§C17): added lines holding a non-null assertion, skipping `!=`, `!==` and negation. Receipt: `grepped non-null assertions: N hits`.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/skills/kc-clarity/scripts/non-null-assertions.sh" <diff-file>
  ```

- `dense-expressions.sh` (§C13): added lines in non-test code files holding a call chain of 3+ links (2+ of them calls), calls nested 3+ deep, or 3+ non-trivial parts (call, `??`/`||` fallback, ternary, cast) in 70+ characters. Receipt: `grepped dense expressions: N hits`; `verify-gate-blocks.sh` checks N against the script's own count and that each hit is named `path:line`.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/skills/kc-clarity/scripts/dense-expressions.sh" <diff-file>
  ```

- `numeric-literals.sh` (§C16): added code lines holding a bare number other than 0 or 1, skipping comments, a declaration that names its number, and an exact expected value in an assertion. Test files are included, since a delay or a date offset in a test is as magic as one in code. Receipt: `grepped numeric literals: N hits`.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/skills/kc-clarity/scripts/numeric-literals.sh" <diff-file>
  ```
