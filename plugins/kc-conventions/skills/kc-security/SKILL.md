---
name: kc-security
description: "Security conventions for request-handling code: who may call it, ids that belong together, replay, scoping, server-owned values, secrets, redirects, injection. Use when writing or reviewing a handler, route, controller, public endpoint, callback, webhook, auth or token code, or code reading request input."
user-invocable: false
paths:
  - "**/*.{ts,tsx,js,jsx,mjs,cjs,rb,py,swift,go,java,kt,php,cs,rs}"
---

# Security

## Contents

- Rules
- Review checklist
- Review detail
  - §SEC1. Who may call it
  - §SEC2. Ids that must belong together are checked together
  - §SEC3. A write a link, callback or retry can trigger cannot be repeated or re-pointed
  - §SEC4. Every lookup starts from the caller's scope
  - §SEC5. Values the server owns are never taken from the client
  - §SEC6. Secrets and personal data stay out of responses, logs and URLs
  - §SEC7. Redirects go only to allowed hosts
  - §SEC8. Input never becomes code
  - §SEC9. Every request-surface hit has a verdict
- Sweeps

## Rules

A handler that passes every happy-path test can still let the wrong caller in, or the right caller act on the wrong record. Review each entry point as the caller you did not build it for: signed out, signed in as someone else, a lower role, the same request twice, and the same request with another record's id.

- Every action reachable signed out or by a lower role checks, in the handler itself, that this caller may act on every record the action reads or writes. A hidden button, a route group or a client-side check is not a check.
- Ids the request supplies that must belong together are checked together: a payment, session or token against the record it is for; a child id against the parent id in the same URL; a return or callback target against the record that started it. Looking each up on its own proves each exists, not that they belong to each other.
- A write that a link, callback, webhook or retry can trigger is safe to repeat and cannot be pointed at another record: it keys on the target it was created for, does nothing the second time, and consumes a one-time token in the same step that uses it.
- Every lookup by an id the request supplies starts from the caller's scope (their account, tenant or ownership), never from the whole table, including the ids in a list, a bulk action and a job the request enqueues.
- A value the server must own (an amount, price, total, role, owner or tenant id, status, flag or timestamp) is computed or validated on the server from its own records; a client-sent copy is a request, not a fact. Accept only an allowlist of fields.
- Secrets and personal data stay out of responses (serialize named fields, not a whole record), logs, error messages and URLs; a token in a query string ends up in logs and referrers.
- A redirect, return or callback target taken from input is checked against an allowlist of hosts or paths (an exact match or a parsed host, never a prefix or substring test), or is not taken from input at all.
- Input never becomes code: no SQL, shell command, HTML or template built by joining strings; use parameters, argument arrays and escaping the framework provides.
- A change that skips or removes an authentication, authorization or request-forgery check names who can now reach the action and what they can do, and a test shows the caller who must be refused refused.

Detection criteria and per-box review failure modes live in the `## Review checklist` of the `kc-security` skill (`kc-conventions:kc-security`), with the detail under its `## Review detail`. These rules are the statement of the convention; that checklist is how a diff gets graded against it.

## Review checklist

The security gate agent ticks every box against the diff. A box is FAIL if any matching construct violates it; the gate is FAIL if any box is FAIL. Each box states its own N/A condition. The whole gate is N/A only when the diff adds or changes no handler, route, callback, middleware or code that reads request input, and the agent states that explicitly.

- [ ] §SEC1 Who may call it: each action the diff adds or changes that a signed-out visitor or a lower role can reach checks, in the handler, that the caller may act on every record it reads or writes; a skipped, removed or loosened authentication, authorization or request-forgery check names who can now reach the action. Example: an invoice download that checks the visitor is signed in but not that the invoice is theirs. (N/A: the diff adds or changes no handler, route, callback or middleware)
- [ ] §SEC2 Ids that must belong together are checked together: where a request supplies two or more ids (a payment and its order, a session and its record, a child and the parent in the URL, a token and the record it unlocks), the evidence names the single check that ties them, and a handler that looks each up alone FAILS. Example: a return link carrying `order_id` and `payment_id`, where the payment is accepted for whichever order the link names. (N/A: no handler reads more than one request-supplied id or token)
- [ ] §SEC3 Replay: a write that a link, callback, webhook, retry or double submit can trigger is idempotent for its target, cannot be pointed at another record, and uses a one-time token in the same step that spends it; the evidence says what happens on the second call and on a call naming another record. Example: a "paid" callback that sets the state on whichever order the link names, every time it is opened. (N/A: the diff adds or changes no write reachable from a request)
- [ ] §SEC4 Scoping: every lookup by a request-supplied id starts from the caller's scope (account, tenant, owner), including each id in a list, a bulk action and a job the request enqueues; a lookup on the whole table FAILS unless the record is public by design and the evidence says so. Example: `Order.find(params[:id])` where `current_account.orders.find(params[:id])` is meant. (N/A: no lookup by a request-supplied id)
- [ ] §SEC5 Server-owned values are not taken from the client: an amount, price, total, role, owner or tenant id, status, flag or timestamp the request carries is recomputed or validated from the server's own records, and writes accept an allowlist of fields. Example: an order total posted by the browser and charged as sent. (N/A: the request carries no such value, and no write assigns request fields to a record)
- [ ] §SEC6 Secrets and personal data stay out of responses, logs, error messages and URLs: responses name their fields, logs and errors carry no token, key or personal data, and no token travels in a query string it does not have to. Example: a serializer that returns the whole user, password digest and email included. (N/A: the diff adds or changes no response, log line, error message or URL)
- [ ] §SEC7 Redirects go only to allowed hosts: a redirect, return or callback target from input is matched against an allowlist by exact value or parsed host, never by prefix or substring. Example: `redirect_to params[:return_to]`. (N/A: the diff adds or changes no redirect and takes no target from input)
- [ ] §SEC8 Input never becomes code: no SQL, shell command, HTML or template is built by joining strings with request input; each uses parameters, argument arrays or the framework's escaping. Example: `where("name = '#{params[:name]}'")`. (N/A: no query, command, markup or template built from input)
- [ ] §SEC9 Every hit of the `request-surface.sh` sweep has its own verdict on §SEC1 to §SEC8, and the hit count equals the verdict count; a hit nobody judged FAILS. **Enumerate with the `request-surface.sh` sweep** (see Sweeps). (N/A: only when it returns 0 hits, stated as `grepped request surface: 0 hits`)

## Review detail

### §SEC1. Who may call it

Authentication says who the caller is; authorization says what they may do to this record. A public or lower-role entry point (a signed-out page, a callback, a guest link, an admin-only action reachable by route) has to settle the second question itself, because nothing upstream of the handler can: the UI hides the control, but the URL still answers.

**Flag:**
- A handler that checks the caller is signed in, then reads or writes a record by id without checking it is theirs.
- A `skip_before_action :authenticate` (or the framework's equivalent) with no replacement check on the action it frees.
- A role check on the menu or route group only, with the handler callable directly.

```ruby
# Flag: any signed-in user can download any invoice
def show = send_data Invoice.find(params[:id]).pdf
# Prefer: the policy decides, in the handler
def show = send_data authorize(Invoice.find(params[:id])).pdf
```

**Do not flag:** an action that is public by design and reads only public data; the evidence names the data.

### §SEC2. Ids that must belong together are checked together

A request that carries two ids asserts a relationship between them. Each lookup succeeding proves only that each record exists. Find the one statement in the code that says the second record belongs to the first, and if there is none, the relationship is whatever the caller wants it to be.

```ruby
# Flag: a real payment is attached to whichever order the link names
order   = Order.find(params[:order_id])
payment = Payment.find(params[:payment_id])
order.update!(payment: payment, paid: true)

# Prefer: start from the one, derive the other
order   = current_account.orders.find(params[:order_id])
payment = order.payments.find(params[:payment_id])
```

The same shape: a child id with a different parent in the URL (`/orders/1/items/9` where item 9 belongs to order 2), a token for one record accepted on another, a session or checkout id compared with nothing the server stored when it started.

### §SEC3. A write a link, callback or retry can trigger cannot be repeated or re-pointed

Links get opened twice, callbacks are retried, users double-click and attackers replay. For every write such a trigger reaches, answer three questions and write the answers in the evidence: what happens the second time; what happens when the same credential or token names another record; what spends a one-time token, and is that in the same transaction as the write it unlocks.

- Key the write on the target the credential was issued for (store the order id with the payment session when it is created, compare on return), not on an id in the URL.
- Make the second call a no-op or the same result (a unique constraint, a state check inside the transaction, an idempotency key), not a second row or a second email.
- Consume a one-time token with an atomic update (`UPDATE ... WHERE used_at IS NULL`), not a read then a write.

### §SEC4. Every lookup starts from the caller's scope

`Model.find(id)` on the whole table trusts the id. Start from the scope the caller owns (`current_account.orders`, a query with the tenant id in its `where`), so a foreign id is "not found". Check the less obvious readers too: each id in an `ids[]` array, the record a background job loads from an id the request enqueued, a nested include or a count that crosses tenants.

**Do not flag:** a lookup of a record that is public by design (a published page by slug); the evidence says why it is public.

### §SEC5. Values the server owns are never taken from the client

Anything the client could have chosen to be different is a request. The server decides what a thing costs, who owns it, what role a user has and what state a record is in.

```ts
// Flag: charges whatever total the browser posted
await charge(order, body.total)
// Prefer: the server's own number
await charge(order, computeTotal(order.items))
```

Mass assignment is the same mistake in bulk: `update(params)` lets the caller set `role`, `owner_id` or `status`. Accept a named list of fields, and set the owned ones from the server's records.

### §SEC6. Secrets and personal data stay out of responses, logs and URLs

Serialize named fields, never a whole record: the next column added to the table is exposed the day it is added. Keep tokens, keys, passwords and personal data out of log lines and error messages, and out of query strings, which land in access logs, browser history and `Referer` headers; put them in a header or body. A filter list for logs is checked for each new sensitive field the diff adds.

### §SEC7. Redirects go only to allowed hosts

```ruby
# Flag: an open redirect (and a prefix test is no better: "https://shop.example.evil.com")
redirect_to params[:return_to]
return_to.start_with?("https://shop.example")
# Prefer: a relative path only, or a parsed host in an allowlist
redirect_to(allowed_return_path?(params[:return_to]) ? params[:return_to] : root_path)
```

Parse the URL and compare its host, or accept only relative paths that start with a single `/` (not `//`). The same applies to callback and webhook targets the caller names.

### §SEC8. Input never becomes code

A string built from input and handed to an interpreter (a SQL engine, a shell, a browser, a template engine) is a program the caller wrote. Use bound parameters, argument arrays, the framework's escaping, and for raw markup an allowlist sanitizer. A column or sort name taken from input is matched against a fixed list.

### §SEC9. Every request-surface hit has a verdict

The sweep lists every added line that reads request input, declares a route or handler, or skips an authentication filter. Walk each hit and say which of §SEC1 to §SEC8 it touches and why it passes, or fail the box that it breaks. A hit that is only a declaration (a route line, a `class ...Controller`) is judged with the handler it points to. State `grepped request surface: N hits` and give N verdicts; the sweep misses input read through a variable it was assigned to earlier, so read the handlers whole, not just their hits.

## Sweeps

Save the diff under review to a file and run the scripts over it; `-` reads the diff from stdin. Each prints one `path:line: text` hit per line, where `line` is the new-side line number, and nothing else. Give every hit its own verdict, and state each receipt with its count, `0 hits` included.

- `added-lines.sh` (citation map): every added line as `path:line: text`, with the source line number at the head SHA. Cite every finding's line from this output or from a sweep hit, never from a position in the diff file.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/added-lines.sh" <diff-file>
  ```

- `request-surface.sh` (§SEC9): added lines in non-test source files that read request input (params, query, body, headers, cookies, session, route ids), declare a route or handler, or skip an authentication or request-forgery filter. Receipt: `grepped request surface: N hits`.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/skills/kc-security/scripts/request-surface.sh" <diff-file>
  ```
