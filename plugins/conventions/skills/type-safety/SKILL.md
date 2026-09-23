---
name: type-safety
description: "Type-safety conventions for TypeScript, Swift, Kotlin, Rust, Go, C# and Java source files: no `any`, no silencing casts or non-null assertions, boundary parsing, reusing existing types, and types as narrow as their consumers. Use when writing or reviewing typed code, especially code that casts, suppresses a type error, or parses external input."
user-invocable: false
paths:
  - "**/*.{ts,tsx,swift,kt,rs,go,cs,java}"
---

# Type safety

## Rules

Type errors are not warnings, and an escape hatch is a decision to hide one.

- No `any`. If the type is genuinely unknown, use `unknown` and narrow it.
- No cast to silence an error, and no non-null assertion. Fix the type or narrow properly.
- No suppression comment without a note naming the upstream cause.
- Parse all external input at the boundary: request bodies, query params, API responses, stored JSON. Infer the type from the schema rather than hand-writing a parallel interface that can drift.
- In Swift and similar, no force unwrap, no force try, no force cast. Use `guard let`, typed throws, and a result type at boundaries.
- Reuse the existing type. A second interface with the same fields is a bug waiting for the two to diverge.
- A type is as narrow as its consumers need. A return of `T | undefined` whose every consumer treats the empty value like the default is just `T`.
- Write it typed from the start. Loose code plus a fix-up pass after the type checker complains produces worse types than thinking about them first.
