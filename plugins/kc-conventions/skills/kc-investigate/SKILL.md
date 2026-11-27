---
name: kc-investigate
description: Use before building a probe, timing hook or fix for a production problem (slow, failing, wrong data, missing, flaky): time every hop from records that already exist, slice by input size, read the infrastructure, errors, side effects, library source, history and vendor limits, then rule each cause in or out.
---

# Investigate a production problem

A problem in production has already been recorded: traces, job timestamps, slow logs, error stacks, change logs and commit history hold most answers before anything new is built. Read them hop by hop first; build a probe only for a cause the records cannot settle. Examples and full wording: `references/detail.md`.

## Steps

1. Start the write-up at `$(git rev-parse --git-path kc-investigation)/<branch>.md` in the checkout the work happens in (nothing is committed). Copy the checklist into it.
2. Walk the boxes in order, filling each with evidence: a query or command in backticks, a `path:line`, a link or a count. A box that cannot apply says `n/a: <why>` (never for §INV1 or §INV9).
3. Fill the cause table (§INV9) last: every cause anyone has raised, `in` or `out` with the deciding boxes, or `open` with the probe that would settle it.
4. Build a probe, timing hook or fix only for an `open` cause, or one ruled in, with the table as its reason.
5. Run the check yourself before sharing: `bash "${CLAUDE_PLUGIN_ROOT}/skills/kc-investigate/scripts/check-investigation.sh" <write-up>`. `guard-investigation.sh` runs it before `gh pr create`, `gh pr comment`, `gh pr review`, `gh issue comment`, a comments API write or a tracker comment from that branch, and blocks while a box is open or has no evidence. Reading comments is never blocked.

## Investigation checklist

- [ ] §INV1 Hops: the symptom is split into the hops it passes and each is timed from an existing record (trace, job created/started times, log timestamp), with the query that read it.
- [ ] §INV2 Dimensions: timings are bucketed by input size, time window, tenant and host or version; the bucket that moves with the symptom is named with its numbers.
- [ ] §INV3 Infrastructure: the datastore's slow log, network or byte metrics, clients' health warnings and host CPU or throttling were read for the window. (N/A: names which the system has none of)
- [ ] §INV4 Failures nearby: the error tracker's stacks and the status codes on the same path in the same window.
- [ ] §INV5 Side effects: retries, duplicates and partial writes in the audit or change logs.
- [ ] §INV6 Library source: for each hook, middleware or metric relied on or added, the installed source was read for where it runs and what it measures, cited `path:line`. (N/A: nothing measured via a library hook)
- [ ] §INV7 History: the commit or pull request that introduced each suspect piece of code, from `git log` or blame.
- [ ] §INV8 Vendor limits: the documented limits and guidance of each platform on the path (payload size, timeouts, connection counts), with the link.
- [ ] §INV9 Cause table: one row per candidate cause, `in` or `out` citing the boxes that decide it, or `open` naming the probe that would settle it; a probe is built only for an `open` row.

## The write-up

```markdown
# Slow order import

- [x] §INV1 hops: request 1.1 s (`select duration from traces where name = 'orders#create'`), queue wait median 41 s (`select started_at - created_at from jobs`)
- [x] §INV2 dimensions: wait 1.2 s under 5 MB, 176 s at 15-25 MB (same query grouped by request size)
- [x] §INV3 infrastructure: queue store slow log lists 17 MB writes; workers log slow-connection warnings
- [x] §INV4 failures nearby: 12 request timeouts, stacks end in argument logging (https://errors.example/issues/ABC-1)
- [x] §INV5 side effects: 3 duplicate orders created 8 s apart after a timeout (change log query `...`)
- [x] §INV6 library source: vendor/queue/middleware.rb:42 runs before the write, so the probe timed nothing
- [x] §INV7 history: the raw-input enqueue came in with commit abc1234
- [x] §INV8 vendor limits: the queue's docs advise small arguments (https://queue.example/docs/best-practices)
- [x] §INV9 cause table:

| cause | verdict |
| --- | --- |
| slow enqueue | out: §INV1 (1 s) |
| payload size | in: §INV2, §INV3, §INV4 |
| worker capacity | open: probe the queue latency metric per worker |
```
