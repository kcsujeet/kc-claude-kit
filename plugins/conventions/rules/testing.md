---
paths:
  - "**/*.{ts,tsx,js,jsx,mjs,cjs,rb,py,swift,go,java,kt,php,cs,rs}"
---
<!-- Generated from skills/testing/SKILL.md by scripts/build-rules.sh. Edit the skill, not this file. -->

# Testing discipline

The loop is not a formality at the end. A change is not done until it is green.

- Write the failing test first. Watch it fail for the right reason, then make it pass. A test that passed the moment you wrote it proved nothing.
- Run the project's check and test commands after each meaningful edit, not once at the very end when the cause of a failure is buried under ten changes.
- Never disable, skip, or narrow a test to reach green. If a test is wrong, say why before changing it, and change it as its own visible decision.
- Do not start a long-running process to "verify" a change. A dev server or watcher never exits; use the one-shot check and test commands.
- Tests live beside the code they cover, named after it.
- Assert the exact value when you know it: `toBe(3)`, not `toBeGreaterThan(0)`. A tolerance is for values that are genuinely inexact, stated as one.
- Assert what a user or caller observes (role, text, state, a returned value), not a class name standing in for it.
- A condition that mounts or enables something is tested both ways, met and not met, so deleting it fails a test.
- Setup repeated across tests becomes a local helper (`renderWidget(overrides?)`, `makeItem(id)`), not copy-paste.
- Cover the unhappy paths deliberately: the empty collection, the expired token, the duplicate submit, the interrupted write. The happy path is the one that already works.
- When a bug is fixed, the regression test comes with it in the same change, and it must fail without the fix.
- A form or request that saves user input is tested for every state that behaves differently (at least clearing a saved value), asserting the request body that goes out, not only that the save succeeded.
- A test of an output (a response, a rendered page, an export, a message) asserts what it contains, so an output that comes back empty fails it. A status code, "it rendered" or "no error" passes when every field is missing. Shared test helpers that check responses assert their content too.
- A test names the record it expects: the one it created, or one picked with an order whose last key is unique. `first` over an order with ties (a position that restarts per group, a timestamp, an unordered query) returns any of the tied rows, so the test passes or fails depending on the database's mood.
- Code that compares against "now" takes it from the app's clock and passes it in (a bound parameter to SQL), not from the database (`CURRENT_TIMESTAMP`, `NOW()`, `CURRENT_DATE`), and its tests freeze that clock. A database clock can't be frozen, so a test that checks "not due yet" passes or fails by the hour CI happens to run.
- A test sets every attribute its result depends on, instead of taking the factory's default. A factory that samples values (a random type, a random offset) makes a test that leaves them unset pass or fail by the draw, and the run's seed usually doesn't reproduce it. Read the factory before relying on its defaults.
- When the end-to-end suite runs in a harness or fixture app, each headline user-facing feature also gets at least one test that drives the shipped app (its demo or default configuration, with its seed data). A suite that only ever sees clean fixtures cannot catch a bug that needs the real combination of settings and data.

Detection criteria and per-box review failure modes live in the `## Review checklist` of the `testing` skill (`conventions:testing`), with the detail under its `## Review detail`. These rules are the statement of the convention; that checklist is how a diff gets graded against it.
