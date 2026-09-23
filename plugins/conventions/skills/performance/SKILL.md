---
name: performance
description: "Performance conventions for TypeScript, JavaScript and other source files: filtering and pagination in the data layer, no unbounded selects or N+1 queries, indexes shipped with new query patterns, and client-side main-thread, list and image costs. Use when writing or reviewing code that queries data, adds a list endpoint, or renders long lists or images."
user-invocable: false
paths:
  - "**/*.{ts,tsx,js,jsx,mjs,cjs,rb,py,swift,go,java,kt,php,cs,rs}"
---

# Performance

## Rules

Slow is a bug, not a tuning opportunity for later.

- Filter, sort, aggregate and paginate in the data layer. Never load rows into application code to filter them there.
- Every list endpoint is paginated with a default and a hard maximum. No unbounded select.
- Select the columns you need. `select *` in a query helper is not acceptable.
- No N+1. Join or batch: one query per request path, not one per row.
- A new query pattern ships with its index in the same change.
- Do a deliberate pass at the end of any feature that reads data, and say what you measured rather than that you looked.
- On the client: keep work off the main thread beyond rendering, virtualize long lists, and size images before they render.
