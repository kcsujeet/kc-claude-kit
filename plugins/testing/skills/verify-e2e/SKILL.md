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
- **Spot checks are not QA.** Running the one path you just built is a smoke test. Walk every state the flow can be in, every time. When there is a design, its states are the test plan: build the state matrix the `verify-ui` skill describes and walk each state end to end.
- **Run it in what users get, not in your test setup.** A test harness, fixture page or storybook loads small, clean data under near-default settings. The shipped app (its demo, its staging build, the configuration a consumer actually runs) combines every option, dense data, scroll containers and real defaults, and a bug that needs that combination passes every harness test. A feature is verified only once it has run there.
- **"It loads with no errors" is not "it works".** A smoke check that never clicks, drags, types or saves proves only that the page renders. Exercise the interaction the change is about.
- **A probe counts only after it has been shown it can both fail and pass.** Run it first where the behaviour is known to work. A target scrolled out of its container, covered by a sticky header, or a drag that ends outside the drop area all read as "nothing happened", and none of them is a bug. Confirm the target is under the pointer (`document.elementFromPoint`) before trusting the result.

Example: a library shipped a release whose headline feature was resizing items by dragging an edge. It had passed 19 harness specs, two QA rounds, a regression check against the previous version and a smoke test of an example app. On release day the feature did nothing in the project's own public demo. Every check had run in the harness on small fixtures, or had only loaded the page; none had dragged an edge in the demo. The owner found it by hand in minutes, and the fix shipped as a patch release.

## Workflow

### Step 1 — map the path

Write down the layers the change touches, in order, from the interaction to the durable effect: interaction, client state, request, handler, service, store, and whatever fires afterwards (job, email, webhook, cache invalidation). This list is what you are about to walk, and it tells you where to look when a step fails.

### Step 2 — get a system running

Bring up the system users actually run (the app, its demo or a staging build, with its default configuration), not only the test harness, and with seed data that resembles production. Note which parts are real and which are stubbed, because a flow verified against a stubbed payment provider is verified against a stub, and the report should say so.

### Step 2b — list the states

Every setting or condition that changes the flow is a state to walk: each switch in both positions, each option that changes what is offered, each role, no data / one / many. Take them from the design when there is one, otherwise from the code. Walk the happy path and the unhappy paths in each state the change can reach.

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

## Gate checklist

Do not report a flow verified until every box is ticked:

- [ ] The path from interaction to durable effect is written down, layer by layer.
- [ ] Every state that changes the flow is listed (from the design when there is one), and the flow was walked in each state the change can reach.
- [ ] The durable effect was confirmed at the far end in each state, not inferred from the UI.
- [ ] The unhappy paths chosen and skipped are named.
- [ ] The report lists each step, each finding with its state and step, and what could not be exercised.
