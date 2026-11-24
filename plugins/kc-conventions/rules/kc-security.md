---
paths:
  - "**/*.{ts,tsx,js,jsx,mjs,cjs,rb,py,swift,go,java,kt,php,cs,rs}"
---
<!-- Generated from skills/kc-security/SKILL.md by scripts/build-rules.sh. Edit the skill, not this file. -->

# Security

A handler that passes every happy-path test can still let the wrong caller in, or the right caller act on the wrong record. Review each entry point as the caller you did not build it for: signed out, signed in as someone else, a lower role, the same request twice, and the same request with another record's id.

- Every action reachable signed out or by a lower role checks, in the handler itself, that this caller may act on every record the action reads or writes. A hidden button, a route group or a client-side check is not a check.
- Ids the request supplies that must belong together are checked together: a payment, session or token against the record it is for; a child id against the parent id in the same URL; a return or callback target against the record that started it. Looking each up on its own proves each exists, not that they belong to each other.
- A write that a link, callback, webhook or retry can trigger is safe to repeat and cannot be pointed at another record: it keys on the target it was created for, does nothing the second time, and consumes a one-time token in the same step that uses it.
- Every lookup by an id the request supplies starts from the caller's scope (their account, tenant or ownership), never from the whole table, including the ids in a list, a bulk action and a job the request enqueues.
- A value the server must own (an amount, price, total, role, owner or tenant id, status, flag or timestamp) is computed or validated on the server from its own records; a client-sent copy is a request, not a fact. Accept only an allowlist of fields.
- Secrets and personal data stay out of responses (serialize named fields, not a whole record), logs, error messages and URLs; a token in a query string ends up in logs and referrers.
- A redirect, return or callback target taken from input is checked against an allowlist of hosts or paths (an exact match or a parsed host, never a prefix or substring test), or is not taken from input at all.
- Input never becomes code: no SQL, shell command, HTML or template built by joining strings; use parameters, argument arrays and escaping the framework provides.
- Raw request input never reaches a job's arguments, a log line, a cache or an event: pass the validated, allowlisted values or ids. Raw input carries personal data, files and fields nobody checked into stores that keep them and logs that print them.
- A change that skips or removes an authentication, authorization or request-forgery check names who can now reach the action and what they can do, and a test shows the caller who must be refused refused.

Detection criteria and per-box review failure modes live in the `## Review checklist` of the `kc-security` skill (`kc-conventions:kc-security`), with the detail under its `## Review detail`. These rules are the statement of the convention; that checklist is how a diff gets graded against it.
