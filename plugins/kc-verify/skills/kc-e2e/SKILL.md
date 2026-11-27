---
name: kc-e2e
description: "Drive a feature end to end like a person, unhappy paths included, after a change spanning more than one layer. Trigger on \"test this end to end\", \"verify the whole flow\", \"does this actually work\", \"check the integration\", or before reporting complete a client-and-server change."
---

# Verifying a feature end to end

Unit tests prove each layer alone. They pass while the client sends a field the server ignores, the write lands in the wrong column or the retry fires twice. Only running the flow catches that. This is not a browser test suite; driving it as a person is the point. Full wording and the example: `references/detail.md`.

## Steps

1. Map the path: the layers the change touches, from the interaction to the durable effect (interaction, client state, request, handler, service, store, and what fires afterwards: job, email, webhook, cache invalidation).
2. Bring up the system users actually run (the app, its demo or a staging build, default configuration, production-like seed data) with one tested command run as written (`kc-verify:kc-ui` Step 2); name the command in the report. Note which parts are real and which stubbed.
3. List the states: each switch in both positions, each option that changes what is offered, each role, no data / one / many. Take them from the design when there is one, else from the code.
4. Walk the happy path as a user in each state the change can reach: click through, submit, wait.
5. Confirm the durable effect at the far end, not that the UI stopped spinning: read the row, check the queue, open the file, look at the email. "Returned 200" is not verified.
6. Walk the unhappy paths the change can reach and name the ones you chose and skipped: interrupted midway, submitted twice fast, stale or expired credentials, input the client allows and the server rejects (and the reverse), empty and very large state, a retry after failure.
7. Keep the failure: a step that fails is the finding; do not route around it.
8. Probe only with a probe shown to both fail and pass (confirm the target is under the pointer with `document.elementFromPoint`); "loads with no errors" is not "works".
9. Report, numbered: each step and what you saw, the findings each with its state and step, and what you could not exercise and why.
10. When you cannot run it, say so and stop; offer to read the two sides of the contract against each other, name the fields that do not line up, or write the integration test that would catch it.

## Gate checklist

Do not report a flow verified until every box is ticked:

- [ ] §EE1 The path from interaction to durable effect is written down, layer by layer.
- [ ] §EE2 Every state that changes the flow is listed (from the design when there is one), and the flow was walked in each state the change can reach, in what users get, not only a test harness.
- [ ] §EE3 The durable effect was confirmed at the far end in each state, not inferred from the UI.
- [ ] §EE4 Every write a link, callback or return URL triggers was replayed with another record's id and once more with the same id, and the far end checked after each. (N/A: no such write)
- [ ] §EE5 The unhappy paths chosen and skipped are named.
- [ ] §EE6 The report lists each step, each finding with its state and step, and what could not be exercised.
