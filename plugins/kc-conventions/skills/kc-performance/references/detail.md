# Performance: examples and edge cases per box

### §PF1. Data crossing a boundary is sized for the receiver

- A payload sized by the sender grows with whatever the sender happens to hold: every linked record a form loaded, every field a request carried, every column a record gained since. Queues, caches, logs and networks then move and store all of it, and the cost shows up far from the line that caused it (a job that waits minutes to be picked up, a cache that evicts early, a log bill), and only on the large cases. Ask what the receiver reads, and send that.

```ts
// Flag: the whole form, each linked record with a full copy of its parent, goes in the body
await fetch('/api/orders', { method: 'POST', body: JSON.stringify({ ...form }) })
// Prefer: the fields the endpoint accepts
await fetch('/api/orders', { method: 'POST', body: JSON.stringify(toOrderPayload(form)) })
```

```ruby

**Checklist wording (moved from SKILL.md):** Data crossing a boundary is sized for the receiver: each hit of the `boundary-payloads.sh` sweep, and each job enqueue, cache write, log line, event, outgoing request or response the diff adds, passes ids or the named fields the receiver reads, not a whole record, a spread or deep copy of state, or raw request input; the evidence names what the receiver reads. Examples: a form that spreads its whole state, linked records and all, into a request body; a handler that queues the raw request parameters instead of the validated values; a cache entry holding a full record where the page reads two fields. **Enumerate with the `boundary-payloads.sh` sweep** (see Sweeps). (N/A: the sweep returns 0 hits and the diff adds no enqueue, cache write, log line, event, outgoing request or response, stated as `grepped boundary payloads: 0 hits`)
# Flag: the raw parameters, whatever the client sent, become the job's arguments
ImportOrderJob.perform_later(params.to_unsafe_h)
# Prefer: the validated values, or an id the job loads
ImportOrderJob.perform_later(order_contract.call(order_params).to_h)
```

- The same shape: a cache entry holding `record.__dict__` where the page reads a name and a price; an event carrying a whole model where its consumers read its id and status; a log line that prints the request body. When a hit is fine (the receiver does read every field, and the record is small and bounded), the evidence says which fields it reads and why the size stays bounded.

### §PF2

- **Checklist wording (moved from SKILL.md):** Filter, sort, aggregate and paginate in the data layer: no rows loaded into application code to filter them there; a list endpoint has a default page size and a hard maximum; no `select *`. (N/A: no query or list endpoint)
