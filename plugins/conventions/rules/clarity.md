---
paths:
  - "**/*.{ts,tsx,js,jsx,mjs,cjs,rb,py,swift,go,java,kt,php,cs,rs}"
---
<!-- Generated from skills/clarity/SKILL.md by scripts/build-rules.sh. Edit the skill, not this file. -->

# Clarity

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
