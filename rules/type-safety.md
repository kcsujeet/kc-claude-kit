---
paths:
  - "**/*.{ts,tsx,swift,kt,rs,go,cs,java}"
---

# Type safety

Type errors are not warnings, and an escape hatch is a decision to hide one.

- No `any`. If the type is genuinely unknown, use `unknown` and narrow it.
- No cast to silence an error, and no non-null assertion. Fix the type or narrow properly.
- No suppression comment without a note naming the upstream cause.
- Parse all external input at the boundary: request bodies, query params, API responses, stored JSON. Infer the type from the schema rather than hand-writing a parallel interface that can drift.
- In Swift and similar, no force unwrap, no force try, no force cast. Use `guard let`, typed throws, and a result type at boundaries.
- Reuse the existing type. A second interface with the same fields is a bug waiting for the two to diverge.
- Write it typed from the start. Loose code plus a fix-up pass after the type checker complains produces worse types than thinking about them first.
