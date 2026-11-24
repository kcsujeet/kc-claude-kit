---
name: kc-investigate
description: Use before building a probe, timing hook or fix for a production problem (slow, failing, wrong data, missing, flaky): time every hop from records that already exist, slice by input size, read the infrastructure, errors, side effects, library source, history and vendor limits, then rule each cause in or out.
---

# Investigate a production problem

A problem in production has already been recorded: request traces, job timestamps, slow logs, error stacks, change logs and commit history hold most answers before anything new is built. A probe built for the first guessed cause measures that guess and nothing else, takes a deploy and a wait, and can be wrong itself. Read what exists first, hop by hop, and build a probe only for a cause the records cannot settle.

## Procedure

1. **Start the write-up** at `$(git rev-parse --git-path kc-investigation)/<branch>.md` in the checkout the work happens in (the folder is created by you; nothing is committed). Copy the checklist below into it and fill each box with its evidence as you go. kc-conventions' `guard-investigation.sh` runs `check-investigation.sh` on that file before a pull request is opened or a findings comment is posted (`gh pr create`, `gh pr comment`, `gh issue comment`, a comments API write, a tracker's comment tool) from that branch, and blocks while a box is open or has no evidence.
2. **Walk the boxes in order.** Each one names where its evidence comes from; evidence is a query or command in backticks, a `path:line`, a link, or a count. A box that cannot apply says `n/a: <why>` (never for §INV1 or §INV9).
3. **Fill the cause table** (§INV9) last: every cause anyone has raised, each ruled `in` or `out` with the boxes that decide it, or `open` with the probe that would settle it.
4. **Build only for an `open` cause.** A probe, a timing hook or a fix for a cause the table rules out is wasted work; one for a cause ruled in goes ahead with the table as its reason.
5. **Run the check yourself** before sharing: `bash "${CLAUDE_PLUGIN_ROOT}/skills/kc-investigate/scripts/check-investigation.sh" <write-up>`.

## Investigation checklist

- [ ] §INV1 Hops: the symptom is split into the hops it passes (request in, write, enqueue, queue wait, pick-up, work, response or delivery), and each hop is timed from a record that already exists (a trace, a job's created and started times, a log timestamp), with the query that read it. Example: a slow async create split into the request (1 s) and the wait before a worker picked the job up (minutes).
- [ ] §INV2 Dimensions: the timings are bucketed by input size, time window, tenant or account, and host or version, and the bucket that moves with the symptom is named with its numbers. Example: the median wait at 1 s under 5 MB and at minutes above 15 MB.
- [ ] §INV3 Infrastructure: the datastore's slow log, network or byte metrics, the clients' own health warnings, and CPU or throttling on the hosts involved were read for the window. Example: a queue store's slow log listing the large writes, and the workers warning that the connection to it was slow. (N/A: says which of these the system has none of)
- [ ] §INV4 Failures nearby: the error tracker's stacks and the status codes on the same path in the same window. Example: request timeouts whose stacks end in logging the job's arguments.
- [ ] §INV5 Side effects: retries, duplicates and partial writes in the audit or change logs. Example: two records created a few seconds apart from one click, a retry after a timeout.
- [ ] §INV6 Library source: for every hook, middleware or metric the investigation relies on or adds, the library's installed source was read to see where it runs and what it measures, cited by `path:line`. Example: a middleware that runs before the write it was meant to time. (N/A: nothing measured through a library hook)
- [ ] §INV7 History: the commit or pull request that introduced each suspect piece of code, from `git log` or blame.
- [ ] §INV8 Vendor limits: the documented limits and guidance of each platform on the path (payload size, timeouts, connection counts), with the link.
- [ ] §INV9 Cause table: a table with a `cause` column and a verdict column, one row per candidate cause, each `in` or `out` citing the boxes (§INV1 to §INV8) that decide it, or `open` naming the probe that would settle it. A probe is built only for an `open` row.

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

## Examples

- A slow async create where a timing probe was built for the enqueue, when existing job records showed the enqueue took a second and the time went to moving a large payload to the worker; the wait grew with request size.
- A report that "exports are missing", where the job's own log showed it stopped on one malformed row every night.
- A flaky checkout where the error tracker grouped every failure under one third-party timeout that its status page had already reported.
- Wrong totals after a deploy, where the commit history named the change to the rounding call.
