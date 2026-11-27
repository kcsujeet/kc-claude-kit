---
name: kc-security
description: "Security conventions for request-handling code: who may call it, ids that belong together, replay, scoping, server-owned values, secrets, redirects, injection. Use when writing or reviewing a handler, route, controller, public endpoint, callback, webhook, auth or token code, or code reading request input."
user-invocable: false
paths:
  - "**/*.{ts,tsx,js,jsx,mjs,cjs,rb,py,swift,go,java,kt,php,cs,rs}"
---

# Security

## Contents

- Review checklist
- Sweeps

## Review checklist

Tick every box for each construct you add or change. Report each: PASS, FAIL (file:line) or N/A (why).

- [ ] §SEC1 Who may call it: each action the diff adds or changes that a signed-out visitor or a lower role can reach checks, in the handler, that the caller may act on every record it reads or writes; a skipped, removed or loosened authentication, authorization or request-forgery check names who can now reach the action. Example: an invoice download that checks the visitor is signed in but not that the invoice is theirs. (N/A: the diff adds or changes no handler, route, callback or middleware)
- [ ] §SEC2 Ids that must belong together are checked together: where a request supplies two or more ids (a payment and its order, a session and its record, a child and the parent in the URL, a token and the record it unlocks), the evidence names the single check that ties them, and a handler that looks each up alone FAILS. Example: a return link carrying `order_id` and `payment_id`, where the payment is accepted for whichever order the link names. (N/A: no handler reads more than one request-supplied id or token)
- [ ] §SEC3 Replay: a write that a link, callback, webhook, retry or double submit can trigger is idempotent for its target, cannot be pointed at another record, and uses a one-time token in the same step that spends it; the evidence says what happens on the second call and on a call naming another record. Example: a "paid" callback that sets the state on whichever order the link names, every time it is opened. (N/A: the diff adds or changes no write reachable from a request)
- [ ] §SEC4 Scoping: every lookup by a request-supplied id starts from the caller's scope (account, tenant, owner), including each id in a list, a bulk action and a job the request enqueues; a lookup on the whole table FAILS unless the record is public by design and the evidence says so. Example: `Order.find(params[:id])` where `current_account.orders.find(params[:id])` is meant. (N/A: no lookup by a request-supplied id)
- [ ] §SEC5 Server-owned values are not taken from the client: an amount, price, total, role, owner or tenant id, status, flag or timestamp the request carries is recomputed or validated from the server's own records, and writes accept an allowlist of fields. Example: an order total posted by the browser and charged as sent. (N/A: the request carries no such value, and no write assigns request fields to a record)
- [ ] §SEC6 Secrets and personal data stay out of responses, logs, error messages and URLs: responses name their fields, logs and errors carry no token, key or personal data, and no token travels in a query string it does not have to. Example: a serializer that returns the whole user, password digest and email included. (N/A: the diff adds or changes no response, log line, error message or URL)
- [ ] §SEC7 Redirects go only to allowed hosts: a redirect, return or callback target from input is matched against an allowlist by exact value or parsed host, never by prefix or substring. Example: `redirect_to params[:return_to]`. (N/A: the diff adds or changes no redirect and takes no target from input)
- [ ] §SEC8 Input never becomes code: no SQL, shell command, HTML or template is built by joining strings with request input; each uses parameters, argument arrays or the framework's escaping. Example: `where("name = '#{params[:name]}'")`. (N/A: no query, command, markup or template built from input)
- [ ] §SEC9 Every hit of the `request-surface.sh` sweep has its own verdict on §SEC1 to §SEC8, and the hit count equals the verdict count; a hit nobody judged FAILS. **Enumerate with the `request-surface.sh` sweep** (see Sweeps). (N/A: only when it returns 0 hits, stated as `grepped request surface: 0 hits`)
- [ ] §SEC10 Raw request input never reaches a job, log, cache or event: each hit of kc-performance's `boundary-payloads.sh` sweep whose payload is request input (the whole params, body, query or form) FAILS unless what is passed is the validated, allowlisted output or ids, and the evidence names that validation. Example: a handler that queues `params.to_unsafe_h`, so customers' personal data and uploaded files sit in the queue store and print in the job log. **Enumerate with the `boundary-payloads.sh` sweep** (see Sweeps). (N/A: no hit's payload is request input, stated with the sweep's count)

Examples and edge cases per box: references/detail.md (read when a box is unclear).

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

- `boundary-payloads.sh` (§SEC10), from kc-performance: added lines that hand a whole object or raw request input to a job, cache, log, event, outgoing request or response. Judge each hit whose payload is request input. Receipt: `grepped boundary payloads: N hits`.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/skills/kc-performance/scripts/boundary-payloads.sh" <diff-file>
  ```
