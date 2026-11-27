---
name: kc-performance
description: "Performance conventions for source files: filtering and pagination in the data layer, no unbounded selects or N+1 queries, indexes with new queries, client list and image costs. Use when writing or reviewing code that queries data, adds a list endpoint, or renders long lists or images."
user-invocable: false
paths:
  - "**/*.{ts,tsx,js,jsx,mjs,cjs,rb,py,swift,go,java,kt,php,cs,rs}"
---

# Performance

## Review checklist

Tick every box for each construct you add or change. Report each: PASS, FAIL (file:line) or N/A (why).

- [ ] §PF1 Data crossing a boundary is sized for the receiver: each hit of the `boundary-payloads.sh` sweep, and each job enqueue, cache write, log line, event, outgoing request or response the diff adds, passes ids or the named fields the receiver reads, not a whole record, a spread or deep copy of state, or raw request input; the evidence names what the receiver reads. Examples: a form that spreads its whole state, linked records and all, into a request body; a handler that queues the raw request parameters instead of the validated values; a cache entry holding a full record where the page reads two fields. **Enumerate with the `boundary-payloads.sh` sweep** (see Sweeps). (N/A: the sweep returns 0 hits and the diff adds no enqueue, cache write, log line, event, outgoing request or response, stated as `grepped boundary payloads: 0 hits`)
- [ ] §PF2 Filter, sort, aggregate and paginate in the data layer: no rows loaded into application code to filter them there; a list endpoint has a default page size and a hard maximum; no `select *`. (N/A: no query or list endpoint)
- [ ] §PF3 No N+1: one query per request path, joined or batched, not one per row. (N/A: no per-row reads)
- [ ] §PF4 A new query pattern ships with its index in the same change. (N/A: no new query)
- [ ] §PF5 A feature that reads data got a deliberate pass at the end, stating what was measured, not that it was looked at. (N/A: no data read)
- [ ] §PF6 Client work stays cheap: nothing heavy off the render path on the main thread, long lists virtualized, images sized before they render. (N/A: no list or image added)

Examples and edge cases per box: references/detail.md (read when a box is unclear).

## Sweeps

Save the diff under review to a file and run the script over it; `-` reads the diff from stdin. It prints one `path:line: text` hit per line. Give every hit its own verdict, and state the receipt with its count, `0 hits` included.

- `boundary-payloads.sh` (§PF1, and security §SEC10 for hits whose payload is request input): added lines in non-test source files that hand a whole object, a spread or deep copy, or raw request input to a job enqueue, cache or store write, log line, event publish, outgoing request or response. A payload built on an earlier line and passed by name is not seen, so read each sink the diff adds whole. Receipt: `grepped boundary payloads: N hits`.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/skills/kc-performance/scripts/boundary-payloads.sh" <diff-file>
  ```
