# Security: examples and edge cases per box

### §SEC1. Who may call it

- Authentication says who the caller is; authorization says what they may do to this record. A public or lower-role entry point (a signed-out page, a callback, a guest link, an admin-only action reachable by route) has to settle the second question itself, because nothing upstream of the handler can: the UI hides the control, but the URL still answers.

- **Flag:**
- A handler that checks the caller is signed in, then reads or writes a record by id without checking it is theirs.
- A `skip_before_action :authenticate` (or the framework's equivalent) with no replacement check on the action it frees.
- A role check on the menu or route group only, with the handler callable directly.

```ruby

**Checklist wording (moved from SKILL.md):** Who may call it: each action the diff adds or changes that a signed-out visitor or a lower role can reach checks, in the handler, that the caller may act on every record it reads or writes; a skipped, removed or loosened authentication, authorization or request-forgery check names who can now reach the action. Example: an invoice download that checks the visitor is signed in but not that the invoice is theirs. (N/A: the diff adds or changes no handler, route, callback or middleware)
# Flag: any signed-in user can download any invoice
def show = send_data Invoice.find(params[:id]).pdf
# Prefer: the policy decides, in the handler
def show = send_data authorize(Invoice.find(params[:id])).pdf
```

- **Do not flag:** an action that is public by design and reads only public data; the evidence names the data.

### §SEC2. Ids that must belong together are checked together

- A request that carries two ids asserts a relationship between them. Each lookup succeeding proves only that each record exists. Find the one statement in the code that says the second record belongs to the first, and if there is none, the relationship is whatever the caller wants it to be.

```ruby

**Checklist wording (moved from SKILL.md):** Ids that must belong together are checked together: where a request supplies two or more ids (a payment and its order, a session and its record, a child and the parent in the URL, a token and the record it unlocks), the evidence names the single check that ties them, and a handler that looks each up alone FAILS. Example: a return link carrying `order_id` and `payment_id`, where the payment is accepted for whichever order the link names. (N/A: no handler reads more than one request-supplied id or token)
# Flag: a real payment is attached to whichever order the link names
order   = Order.find(params[:order_id])
payment = Payment.find(params[:payment_id])
order.update!(payment: payment, paid: true)

# Prefer: start from the one, derive the other
order   = current_account.orders.find(params[:order_id])
payment = order.payments.find(params[:payment_id])
```

- The same shape: a child id with a different parent in the URL (`/orders/1/items/9` where item 9 belongs to order 2), a token for one record accepted on another, a session or checkout id compared with nothing the server stored when it started.

### §SEC3. A write a link, callback or retry can trigger cannot be repeated or re-pointed

- Links get opened twice, callbacks are retried, users double-click and attackers replay. For every write such a trigger reaches, answer three questions and write the answers in the evidence: what happens the second time; what happens when the same credential or token names another record; what spends a one-time token, and is that in the same transaction as the write it unlocks.

- Key the write on the target the credential was issued for (store the order id with the payment session when it is created, compare on return), not on an id in the URL.
- Make the second call a no-op or the same result (a unique constraint, a state check inside the transaction, an idempotency key), not a second row or a second email.
- Consume a one-time token with an atomic update (`UPDATE ... WHERE used_at IS NULL`), not a read then a write.

- **Checklist wording (moved from SKILL.md):** Replay: a write that a link, callback, webhook, retry or double submit can trigger is idempotent for its target, cannot be pointed at another record, and uses a one-time token in the same step that spends it; the evidence says what happens on the second call and on a call naming another record. Example: a "paid" callback that sets the state on whichever order the link names, every time it is opened. (N/A: the diff adds or changes no write reachable from a request)

### §SEC4. Every lookup starts from the caller's scope

- `Model.find(id)` on the whole table trusts the id. Start from the scope the caller owns (`current_account.orders`, a query with the tenant id in its `where`), so a foreign id is "not found". Check the less obvious readers too: each id in an `ids[]` array, the record a background job loads from an id the request enqueued, a nested include or a count that crosses tenants.

- **Do not flag:** a lookup of a record that is public by design (a published page by slug); the evidence says why it is public.

- **Checklist wording (moved from SKILL.md):** Scoping: every lookup by a request-supplied id starts from the caller's scope (account, tenant, owner), including each id in a list, a bulk action and a job the request enqueues; a lookup on the whole table FAILS unless the record is public by design and the evidence says so. Example: `Order.find(params[:id])` where `current_account.orders.find(params[:id])` is meant. (N/A: no lookup by a request-supplied id)

### §SEC5. Values the server owns are never taken from the client

- Anything the client could have chosen to be different is a request. The server decides what a thing costs, who owns it, what role a user has and what state a record is in.

```ts
// Flag: charges whatever total the browser posted
await charge(order, body.total)
// Prefer: the server's own number
await charge(order, computeTotal(order.items))
```

- Mass assignment is the same mistake in bulk: `update(params)` lets the caller set `role`, `owner_id` or `status`. Accept a named list of fields, and set the owned ones from the server's records.

- **Checklist wording (moved from SKILL.md):** Server-owned values are not taken from the client: an amount, price, total, role, owner or tenant id, status, flag or timestamp the request carries is recomputed or validated from the server's own records, and writes accept an allowlist of fields. Example: an order total posted by the browser and charged as sent. (N/A: the request carries no such value, and no write assigns request fields to a record)

### §SEC6. Secrets and personal data stay out of responses, logs and URLs

- Serialize named fields, never a whole record: the next column added to the table is exposed the day it is added. Keep tokens, keys, passwords and personal data out of log lines and error messages, and out of query strings, which land in access logs, browser history and `Referer` headers; put them in a header or body. A filter list for logs is checked for each new sensitive field the diff adds.

- **Checklist wording (moved from SKILL.md):** Secrets and personal data stay out of responses, logs, error messages and URLs: responses name their fields, logs and errors carry no token, key or personal data, and no token travels in a query string it does not have to. Example: a serializer that returns the whole user, password digest and email included. (N/A: the diff adds or changes no response, log line, error message or URL)

### §SEC7. Redirects go only to allowed hosts

```ruby

**Checklist wording (moved from SKILL.md):** Redirects go only to allowed hosts: a redirect, return or callback target from input is matched against an allowlist by exact value or parsed host, never by prefix or substring. Example: `redirect_to params[:return_to]`. (N/A: the diff adds or changes no redirect and takes no target from input)
# Flag: an open redirect (and a prefix test is no better: "https://shop.example.evil.com")
redirect_to params[:return_to]
return_to.start_with?("https://shop.example")
# Prefer: a relative path only, or a parsed host in an allowlist
return_to = params[:return_to]
return redirect_to(root_path) unless allowed_return_path?(return_to)
redirect_to return_to
```

- Parse the URL and compare its host, or accept only relative paths that start with a single `/` (not `//`). The same applies to callback and webhook targets the caller names.

### §SEC8. Input never becomes code

- A string built from input and handed to an interpreter (a SQL engine, a shell, a browser, a template engine) is a program the caller wrote. Use bound parameters, argument arrays, the framework's escaping, and for raw markup an allowlist sanitizer. A column or sort name taken from input is matched against a fixed list.

- **Checklist wording (moved from SKILL.md):** Input never becomes code: no SQL, shell command, HTML or template is built by joining strings with request input; each uses parameters, argument arrays or the framework's escaping. Example: `where("name = '#{params[:name]}'")`. (N/A: no query, command, markup or template built from input)

### §SEC9. Every request-surface hit has a verdict

- The sweep lists every added line that reads request input, declares a route or handler, or skips an authentication filter. Walk each hit and say which of §SEC1 to §SEC8 it touches and why it passes, or fail the box that it breaks. A hit that is only a declaration (a route line, a `class ...Controller`) is judged with the handler it points to. State `grepped request surface: N hits` and give N verdicts; the sweep misses input read through a variable it was assigned to earlier, so read the handlers whole, not just their hits.

- **Checklist wording (moved from SKILL.md):** Every hit of the `request-surface.sh` sweep has its own verdict on §SEC1 to §SEC8, and the hit count equals the verdict count; a hit nobody judged FAILS. **Enumerate with the `request-surface.sh` sweep** (see Sweeps). (N/A: only when it returns 0 hits, stated as `grepped request surface: 0 hits`)

### §SEC10. Raw request input never reaches jobs, logs, caches or events

- A validated value has had its fields named and its types checked; raw input holds whatever the caller sent, personal data, base64 files and fields the code never reads included. Handed to a queue, cache, event or log line it is stored and printed where no response filter applies, and every consumer has to trust it again. Pass the contract's or allowlist's output, or ids the receiver loads within the caller's scope (§SEC4).

```ruby

**Checklist wording (moved from SKILL.md):** Raw request input never reaches a job, log, cache or event: each hit of kc-performance's `boundary-payloads.sh` sweep whose payload is request input (the whole params, body, query or form) FAILS unless what is passed is the validated, allowlisted output or ids, and the evidence names that validation. Example: a handler that queues `params.to_unsafe_h`, so customers' personal data and uploaded files sit in the queue store and print in the job log. **Enumerate with the `boundary-payloads.sh` sweep** (see Sweeps). (N/A: no hit's payload is request input, stated with the sweep's count)
# Flag: the raw parameters are stored in the queue and printed in the job log
ImportOrderJob.perform_later(params.to_unsafe_h)
# Prefer: the validated output
ImportOrderJob.perform_later(order_contract.call(order_params).to_h)
```
