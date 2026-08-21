---
name: verify-e2e
description: Drive a feature end to end like a person would, after a change that spans more than one layer. Trigger on "test this end to end", "verify the whole flow", "does this actually work", "check the integration", or before reporting complete any change that crosses client and server. Exercises the real flow against a running system, deliberately including the unhappy paths, and reports what was done and what happened.
---

# Verifying a feature end to end

Unit tests prove each layer in isolation. They pass while the client sends a field the server ignores, the write lands in the wrong column, or the retry fires twice. The only thing that catches that is running the actual flow.

This is not about writing a browser test suite. Driving the thing as a human is the point.

## Hard rules

- **Do not claim a cross-layer change works without having run it.** Green unit tests are a different claim; do not present one as the other.
- **Confirm the effect at the far end**, not just that the UI stopped spinning. If the flow writes a row, look at the row. If it enqueues a job, confirm the job ran.
- **Keep the failure.** A step that fails is the finding. Do not route around it and report the flow as working.
- **Report the steps you took and what you saw at each one.** Enough that someone can repeat it without asking you how.
- **Say what you could not exercise.** No credentials, no sandbox, no way to trigger the webhook: name it rather than leaving a silent hole.

## Workflow

### Step 1 — map the path

Write down the layers the change touches, in order, from the interaction to the durable effect: interaction, client state, request, handler, service, store, and whatever fires afterwards (job, email, webhook, cache invalidation). This list is what you are about to walk, and it tells you where to look when a step fails.

### Step 2 — get a system running

Bring up whatever the flow needs, with seed data that resembles production. Note which parts are real and which are stubbed, because a flow verified against a stubbed payment provider is verified against a stub, and the report should say so.

### Step 3 — walk the happy path

Do it as a user: click through, submit, wait. Then verify the durable effect directly at the far end. Read the row, check the queue, open the generated file, look at the email.

A flow that "returned 200" is not verified. What changed?

### Step 4 — walk the unhappy paths deliberately

These are where cross-layer changes actually break:

- interrupted midway: connection dropped, tab closed, process killed between the write and the follow-up
- submitted twice, fast: does it create two of the thing?
- stale or expired credentials
- input the client allows but the server rejects, and the reverse
- an empty state and a very large state
- retried after a failure: does the second attempt land cleanly, or duplicate?

Pick the ones the change can plausibly reach; say which you chose and which you skipped.

### Step 5 — report

Numbered, in order: what you did, what you observed, and where you confirmed the effect. Then the findings, each with the step that produced it. Then what you could not exercise and why.

## When you cannot run it

Say so plainly and stop. Offer what you *can* do instead: read the two sides of the contract against each other, name the fields that do not line up, or write the integration test that would catch it. A confident report from a flow that was never executed is worse than no report, because it ends the investigation.
