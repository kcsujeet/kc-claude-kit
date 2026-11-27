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

- [ ] Tick every box for each construct you add or change. Report each: PASS, FAIL (file:line) or N/A (why).

- [ ] §SEC1 Each action a signed-out visitor or lower role can reach checks in the handler that the caller may act on every record it touches; a loosened auth or CSRF check names who can now reach it.
- [ ] §SEC2 Ids that must belong together (a payment and its order, a child and its URL parent, a token and its record) are tied by one check; a handler looking each up alone FAILS.
- [ ] §SEC3 A write a link, callback, webhook, retry or double submit can trigger is idempotent, cannot be aimed at another record and spends one-time tokens in that step; say what a second call does.
- [ ] §SEC4 Every lookup by a request-supplied id (including each id in a list, bulk action or job) starts from the caller's scope: `current_account.orders.find(params[:id])`, not `Order.find`.
- [ ] §SEC5 Server-owned values (amount, total, role, owner or tenant id, status, timestamp) are recomputed or validated server-side, never taken from the client; writes take a field allowlist.
- [ ] §SEC6 Secrets and personal data stay out of responses, logs, errors and URLs: responses name their fields (no whole-user serializer), no token or key in logs or query strings.
- [ ] §SEC7 A redirect, return or callback target taken from input is matched against an allowlist by exact value or parsed host, never prefix or substring (`redirect_to params[:return_to]`).
- [ ] §SEC8 Input never becomes code: no SQL, shell, HTML or template built by joining strings with request input; use parameters, argument arrays or escaping (`where("name = '#{params[:name]}'")`).
- [ ] §SEC9 Every hit of the `request-surface.sh` sweep has a verdict on §SEC1 to §SEC8 and the counts equal; an unjudged hit FAILS. (N/A: 0 hits, stated as `grepped request surface: 0 hits`)
- [ ] §SEC10 Raw request input (whole params, body, form) never reaches a job, log, cache or event: only the validated, allowlisted output or ids, named in the evidence; `boundary-payloads.sh` swept.

- Examples and edge cases per box: references/detail.md (read when a box is unclear).

## Sweeps

- [ ] Save the diff under review to a file and run the scripts over it; `-` reads the diff from stdin. Each prints one `path:line: text` hit per line, where `line` is the new-side line number, and nothing else. Give every hit its own verdict, and state each receipt with its count, `0 hits` included.

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
