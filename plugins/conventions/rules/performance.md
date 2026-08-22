---
paths:
  - "**/*.{ts,tsx,js,jsx,mjs,cjs,rb,py,swift,go,java,kt,php,cs,rs}"
---

# Performance

Slow is a bug, not a tuning opportunity for later.

- Filter, sort, aggregate and paginate in the data layer. Never load rows into application code to filter them there.
- Every list endpoint is paginated with a default and a hard maximum. No unbounded select.
- Select the columns you need. `select *` in a query helper is not acceptable.
- No N+1. Join or batch: one query per request path, not one per row.
- A new query pattern ships with its index in the same change.
- Do a deliberate pass at the end of any feature that reads data, and say what you measured rather than that you looked.
- On the client: keep work off the main thread beyond rendering, virtualize long lists, and size images before they render.
