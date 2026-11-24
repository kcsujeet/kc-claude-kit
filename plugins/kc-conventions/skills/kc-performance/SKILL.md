---
name: kc-performance
description: "Performance conventions for source files: filtering and pagination in the data layer, no unbounded selects or N+1 queries, indexes with new queries, client list and image costs. Use when writing or reviewing code that queries data, adds a list endpoint, or renders long lists or images."
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
- Data that crosses a boundary (a job's arguments, a cache entry, a log line, an event, an outgoing request or a response) carries what the receiver reads: ids or named fields, never a whole record, a spread or deep copy of client state, or raw request input. Its size grows with the input, so a call that is quick on a small case stalls on a large one.

Detection criteria live in the `## Review checklist` below, with the detail under `## Review detail`; the correctness gate grades a diff against it.

## Review checklist

The correctness gate ticks these boxes too. A box is FAIL if any matching construct violates it, and states its own N/A condition.

- [ ] §PF1 Data crossing a boundary is sized for the receiver: each hit of the `boundary-payloads.sh` sweep, and each job enqueue, cache write, log line, event, outgoing request or response the diff adds, passes ids or the named fields the receiver reads, not a whole record, a spread or deep copy of state, or raw request input; the evidence names what the receiver reads. Examples: a form that spreads its whole state, linked records and all, into a request body; a handler that queues the raw request parameters instead of the validated values; a cache entry holding a full record where the page reads two fields. **Enumerate with the `boundary-payloads.sh` sweep** (see Sweeps). (N/A: the sweep returns 0 hits and the diff adds no enqueue, cache write, log line, event, outgoing request or response, stated as `grepped boundary payloads: 0 hits`)

## Review detail

### §PF1. Data crossing a boundary is sized for the receiver

A payload sized by the sender grows with whatever the sender happens to hold: every linked record a form loaded, every field a request carried, every column a record gained since. Queues, caches, logs and networks then move and store all of it, and the cost shows up far from the line that caused it (a job that waits minutes to be picked up, a cache that evicts early, a log bill), and only on the large cases. Ask what the receiver reads, and send that.

```ts
// Flag: the whole form, each linked record with a full copy of its parent, goes in the body
await fetch('/api/orders', { method: 'POST', body: JSON.stringify({ ...form }) })
// Prefer: the fields the endpoint accepts
await fetch('/api/orders', { method: 'POST', body: JSON.stringify(toOrderPayload(form)) })
```

```ruby
# Flag: the raw parameters, whatever the client sent, become the job's arguments
ImportOrderJob.perform_later(params.to_unsafe_h)
# Prefer: the validated values, or an id the job loads
ImportOrderJob.perform_later(order_contract.call(order_params).to_h)
```

The same shape: a cache entry holding `record.__dict__` where the page reads a name and a price; an event carrying a whole model where its consumers read its id and status; a log line that prints the request body. When a hit is fine (the receiver does read every field, and the record is small and bounded), the evidence says which fields it reads and why the size stays bounded.

## Sweeps

Save the diff under review to a file and run the script over it; `-` reads the diff from stdin. It prints one `path:line: text` hit per line. Give every hit its own verdict, and state the receipt with its count, `0 hits` included.

- `boundary-payloads.sh` (§PF1, and security §SEC10 for hits whose payload is request input): added lines in non-test source files that hand a whole object, a spread or deep copy, or raw request input to a job enqueue, cache or store write, log line, event publish, outgoing request or response. A payload built on an earlier line and passed by name is not seen, so read each sink the diff adds whole. Receipt: `grepped boundary payloads: N hits`.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/skills/kc-performance/scripts/boundary-payloads.sh" <diff-file>
  ```
