---
paths:
  - "**/*.{ts,tsx,js,jsx,mjs,cjs,rb,py,swift,go,java,kt,php,cs,rs}"
---
<!-- Generated from skills/kc-performance/SKILL.md by scripts/build-rules.sh. Edit the skill, not this file. -->

# Performance

Slow is a bug, not a tuning opportunity for later.

- Filter, sort, aggregate and paginate in the data layer. Never load rows into application code to filter them there.
- Every list endpoint is paginated with a default and a hard maximum. No unbounded select.
- Select the columns you need. `select *` in a query helper is not acceptable.
- No N+1. Join or batch: one query per request path, not one per row.
- A new query pattern ships with its index in the same change.
- Do a deliberate pass at the end of any feature that reads data, and say what you measured rather than that you looked.
- On the client: keep work off the main thread beyond rendering, virtualize long lists, and size images before they render.
- Data that crosses a boundary (a job's arguments, a cache entry, a log line, an event, an outgoing request or a response) carries what the receiver reads: ids or named fields, never a whole record, a spread or deep copy of client state, or raw request input. Its size grows with the input, so a call that is quick on a small case stalls on a large one.

Detection criteria live in the `## Review checklist` below, with the detail under `## Review detail`; the correctness gate grades a diff against it.
