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

- [ ] Tick every box for each construct you add or change. Report each: PASS, FAIL (file:line) or N/A (why).

- [ ] §C1 No dense guard clauses (3+ early returns with non-self-explanatory conditions, uncommented). (N/A: no guard-clause chain in diff)
- [ ] §C2 No defensive coercion on an already-typed value (`Number(x)` on a `number`), except genuinely defensive form/input-boundary comparisons. (N/A: no coercion added)
- [ ] §C3 Every new `record.someField` access is declared on the record's type/interface; optional-chained access to an undeclared field is a FAIL. (N/A: no new field access)
- [ ] §C4 No redundant `as T` on a value the compiler already infers as `T`; enumerate with the `as-casts.sh` sweep. (N/A: sweep 0 hits)
- [ ] §C5 No side effects inside render/computation closures (`map` callbacks, memoized selectors, inline JSX); they live in named handlers called from outside. (N/A: no such closure)
- [ ] §C6 Comments earn their place and are sparse: none paraphrase the next line, narrate the task or review round, or blanket most blocks; non-obvious constraints are commented.
- [ ] §C7 Two-step / order-dependent state mutations have an ordering rationale comment. (N/A: no ordered mutation pair in diff)
- [ ] §C8 No magic spread + override + default mixed in one literal (extract a named value). (N/A: no such literal in diff)
- [ ] §C9 No inline anonymous structural type in a variable declaration (name it at module scope). (N/A: no inline structural type in diff)
- [ ] §C10 Multi-fallback `||`/`??` chains with 3+ operands extracted to a named helper. (N/A: no such chain in diff)
- [ ] §C11 Unhappy-path complexity not tangled into the happy path. (N/A: no error branch with 3+ inline statements)
- [ ] §C12 No thin-wrapper helper whose name restates a one-line body, even with a second caller (`simplicity` §P11). (N/A: no new single-purpose helper)
- [ ] §C13 An expression with 2+ non-trivial sub-expressions, a 3+ link call chain or 3+ deep nesting extracts named locals first; one verdict per `dense-expressions.sh` hit. (N/A: sweep 0 hits)
- [ ] §C14 No circular imports introduced (soft). A cycle through a module that does work at definition time is correctness §B6, which fails. (N/A: no cross-module import change)
- [ ] §C15 No nested, long, multi-line or non-trivial-branch ternary, in any position (value, argument, JSX); one verdict per `ternaries.sh` hit, fixes within §C15's remedy limits. (N/A: sweep 0 hits)
- [ ] §C16 Bare numeric literals for dimensions, thresholds and timeouts are named constants with a one-line why (or a design token); a value repeated 2+ times is a DRY finding.
- [ ] §C17 No type escape hatch: no `as` (incl. `as unknown as T`) silencing a mismatch, no `any`, no `value!`; enumerate with `as-casts.sh`, `any-types.sh`, `non-null-assertions.sh`.
- [ ] §C18 No finding proposes removing a named intermediate that makes an expression readable because it looks redundant (`simplicity` §P6 and `structure` §S4 apply the same test).
- [ ] §C19 No conditional spread, inline or built first (`...(flagA ? { key } : {})`, `const extra = flagA && { key }`); give the key a permanent slot set to `undefined`.
- [ ] §C20 A comment stating another unit's behaviour (a caller, a reader, a response) was checked against that unit, named in the evidence; enumerate such comments. (N/A: none added or edited)

- Examples and edge cases per box: references/detail.md (read when a box is unclear).

## Sweeps

- [ ] Save the diff under review to a file (`gh pr diff <num> > /tmp/review.diff`, or `git diff <default-branch>...HEAD > /tmp/review.diff`) and run each script over it; `-` reads the diff from stdin. Each prints one `path:line: text` hit per line, where `line` is the new-side line number, and nothing else. Give every hit its own verdict, and state each receipt on its own line with its count, `0 hits` included.

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
