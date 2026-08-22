---
paths:
  - "**/*.{ts,tsx,js,jsx,mjs,cjs,rb,py,swift,go,java,kt,php,cs,rs}"
---

# Naming

A name is read far more often than it is written, and a wrong one survives refactors. Pick the existing word; do not coin a new one.

- One word per concept, reused everywhere. If the codebase says `booking`, never introduce `reservation` for the same thing.
- Name the role, not the type or the shape: `activeBookings`, not `data`, `result`, `temp`, `items`, `obj`, `arr`.
- Functions read verb-noun: `createBooking`, `listBookings`, `updateBooking`. Not `handle`, `process`, `doStuff`, `save` when it means create-or-update.
- Booleans read as assertions: `isSyncing`, `hasBalance`, `canEdit`, `shouldRetry`.
- A name must read as a true sentence about what it holds. Watch for the four common lies: the subject elided (`items` in a file about invoices), the context borrowed as subject (`total` that is really `taxTotal`), the name left stale after a refactor, and a familiar shape hiding different behaviour (`useQuery` that mutates).
- A boolean chain with two or more non-obvious operands (raw comparisons, enum equality, negations, optional field access) gets **each** operand extracted to its own named boolean. Naming the whole chain does not count: `const canSubmit = a && b > 0 && c !== Locked` still leaves three unnamed conditions for the reader to decode.
- A repeated predicate becomes a named helper or type guard. Twice is the threshold.
- Match the language's own casing: `snake_case` columns and plural tables in SQL, `UpperCamelCase` types with the file named after the type, `kebab-case` plural nouns in routes.

Detection criteria and per-box review failure modes live in the code-review plugin's `references/naming.md`. This file is the statement of the convention; that file is how a diff gets graded against it.
