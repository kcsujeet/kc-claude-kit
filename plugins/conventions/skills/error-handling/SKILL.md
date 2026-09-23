---
name: error-handling
description: "Error-handling conventions for TypeScript, JavaScript and other source files: no swallowed errors, typed errors with stable codes, one error envelope, actionable messages, field-level validation errors, and structured logging. Use when writing or reviewing code that throws, catches, logs, or returns an error or validation failure."
user-invocable: false
paths:
  - "**/*.{ts,tsx,js,jsx,mjs,cjs,rb,py,swift,go,java,kt,php,cs,rs}"
---

# Error handling

## Rules

Fail early, fail loudly, never swallow.

- No empty catch, and no catch that only logs. Either handle it meaningfully or let it propagate.
- Throw a typed error with a stable machine-readable code. An unexpected error surfaces as a server error and pages someone; it does not get mapped to a friendly success.
- One error envelope for the whole surface, with a code, a human message, and optional details. Do not invent a second shape per endpoint.
- A message says what failed and what to do about it. "Something went wrong" is not an error message.
- Validation failures return the field-level issues, not a single sentence the client cannot act on.
- Every error code maps to real copy and a real recovery action in the UI. No silent failure, no generic alert as the catch-all.
- Log with structured context (the ids that identify the record and the request), never a bare interpolated string.
