---
name: kc-testing
description: "Testing conventions for test files and the code they cover in TypeScript, JavaScript and other languages: tests first, a test for every behavior and bug fix, exact assertions, no class-name assertions, gates tested both ways, local setup helpers, and tests placed beside their unit. Use when writing or reviewing tests, or any change that adds behavior or fixes a bug."
user-invocable: false
paths:
  - "**/*.{ts,tsx,js,jsx,mjs,cjs,rb,py,swift,go,java,kt,php,cs,rs}"
---

# Testing discipline

## Contents

- Rules
- Review checklist
- Review detail
  - §T1. New behavior has a test
  - §T2. No class-name assertions as a proxy for behavior
  - §T3. Gates are tested both ways
  - §T4. Repeated setup becomes a local helper
  - §T5. A test sits beside its unit
  - §T6. Exact assertions when the value is known
  - §T7. A submit is tested per state, by its request body
  - §T8. An output is tested by what it contains
  - §T9. A test names its expected record
  - §T10. Time comes from a clock the test can freeze
  - §T11. A test pins every input its result depends on
  - §T12. A UI test leaves nothing to update outside its waits
- Sweeps

## Rules

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
- A UI test awaits only the testing library's own waits and events between an action and its last assertion, so every update the action starts (a hover tooltip, a transition, a ripple) lands inside them. A bare `await` on something else (a clipboard read, a timer, a fetch) leaves a gap where a slow runner lets those updates land outside, and the test fails in CI only. End hover state the action leaves behind (`unhover`) rather than wait for its effect.
- A test that fails only in CI is reproduced locally before a fix is called done: slow down the suspected gap (a delay at that `await`, a slower mock) until it fails the way CI does, then show the fix passes under the same delay. A fix that passed locally before and after proves nothing.
- When the end-to-end suite runs in a harness or fixture app, each headline user-facing feature also gets at least one test that drives the shipped app (its demo or default configuration, with its seed data). A suite that only ever sees clean fixtures cannot catch a bug that needs the real combination of settings and data.

Detection criteria and per-box review failure modes live in the `## Review checklist` of the `kc-testing` skill (`kc-conventions:kc-testing`), with the detail under its `## Review detail`. These rules are the statement of the convention; that checklist is how a diff gets graded against it.

## Review checklist

The testing gate agent ticks every box against the diff. A box is FAIL if any matching construct violates the rule; the gate is FAIL if any box is FAIL. The whole gate is N/A only when the diff changes no behavior and touches no test file (state that).

- [ ] §T1 Every new behavior (a feature, prop, option, branch, or bug fix) has a test that exercises it, and a bug fix's test fails without the fix. (N/A: no behavior change in diff)
- [ ] §T2 No assertion on a class name as the evidence that a state is correct; assert what the user or a consumer observes (role, text, accessible state, a data attribute, an emitted value). A class that is itself the contract (a `className`-style prop the component forwards) is exempt. **Enumerate with the `class-assertions.sh` sweep** (see below). (N/A: only when `class-assertions.sh` returns 0 hits, stated as `grepped class assertions: 0 hits`)
- [ ] §T3 Every gate (a condition that mounts, enables, or routes something) is tested both ways: once with the condition met and once without, so deleting the gate fails a test. (N/A: no gating logic added or changed)
- [ ] §T4 Setup repeated across 2+ tests (the same render-plus-provider boilerplate, fixture literals, or datetime construction) is a local helper, not copy-paste. (N/A: no repeated setup in the diff's tests)
- [ ] §T5 A new or moved test sits beside the unit it covers and is named after it. (N/A: no test file added or moved)
- [ ] §T6 Assertions are exact when the value is known (`toBe(3)`, `toEqual([0, 25, 50])`), not bounds or truthiness that a wrong value also satisfies (`toBeGreaterThan(0)`, `toBeTruthy()`, `toBeDefined()`). A tolerance is fine where the value is genuinely inexact (floating point, measured geometry), stated as `toBeCloseTo`. **Enumerate with the `loose-assertions.sh` sweep** (see below). (N/A: only when `loose-assertions.sh` returns 0 hits, stated as `grepped loose assertions: 0 hits`)
- [ ] §T7 A submit is tested per state: each form or request that saves user input has a test for every field state that behaves differently (at least clearing a saved value; see correctness §B5), and each test asserts the request body sent, not only the success path. (N/A: the diff adds or changes no submit of user input)
- [ ] §T8 Every test of an output the diff adds or changes (a response, a rendered page, an export, a message) asserts at least one value inside it that the change is responsible for, so an empty or field-less output fails the test. A test that asserts only a status code, that something rendered, or that no error was raised FAILS. A shared helper or example that checks responses counts as the test, and is held to the same rule. (N/A: the diff adds or changes no output and no test of one)
- [ ] §T9 Every expected record in a test is named, not re-derived: it is a record the test created and holds, or a lookup whose order ends on a unique key. A `first`/`last`/`take` (or `[0]` on a query result) over an order that can tie FAILS; the evidence names the ordering columns and why they cannot tie. **Enumerate**: grep the test diff for `.first`, `.last`, `.take` and `[0]` on query results, one verdict per hit. (N/A: `grepped first/last/take: 0 hits`)
- [ ] §T10 Time-dependent behaviour is tested at a frozen time: each test of code that compares against now (due, overdue, today, expiry, local hour) freezes the clock, and the code reads now from that clock, not from the database. A query the diff adds or changes that uses `CURRENT_TIMESTAMP`, `NOW()` or `CURRENT_DATE` for a comparison a test covers FAILS. **Enumerate**: grep the diff for those three, one verdict per hit. (N/A: `grepped database clock: 0 hits` and no time comparison added)
- [ ] §T11 Every record a new or changed test builds sets each attribute the code under test branches on; the evidence names the factory and confirms each such attribute is either set in the test or fixed (not sampled) in the factory. A branch-deciding attribute left to a factory that samples it FAILS. (N/A: the diff adds or changes no test that builds records)
- [ ] §T12 In every UI test the diff adds or changes, each `await` between the first user action and the last assertion is the testing library's own (a user event, `findBy*`, `waitFor`); a bare `await` on anything else (`navigator.clipboard.readText()`, a sleep, a direct fetch) FAILS, and so does hover or focus state an action leaves behind without an `unhover`/`blur` or a wait for its effect. A fix for a CI-only failure in such a test names the delay that reproduced it locally. **Enumerate**: grep the test diff for `await ` lines that are not `user.`, `findBy`, `findAllBy` or `waitFor`, one verdict per hit. (N/A: the diff adds or changes no UI test)

## Review detail

Test rules for the diff under review. Covers eight independent failure modes: behavior shipped without a test, class names asserted as a proxy for behavior, a gate tested from one side only, setup copied between tests instead of named once, a test placed away from its unit, bounds asserted where the exact value is known, a submit tested only on its happy path, and an output tested only for its status.

### §T1. New behavior has a test

A change a user or caller can observe ships with a test that would fail if the change were reverted. The test has to reach the new behavior through the unit's real entry point (render the component, call the exported function, hit the route), not through a helper the test builds itself.

**Flag:**
- A new prop, option, or branch with no test that sets it.
- A bug fix with no regression test, or a regression test that passes with the old code (it pins the fixture, not the fix). Ask the author to revert the fix locally and watch the test fail.
- A test that only covers the happy path of a change whose risk is on the unhappy one (empty input, a missing value, a duplicate submit).

**Do not flag:** pure refactors with no observable change, when the existing tests already cover the behavior (name those tests in the evidence).

### §T2. No class-name assertions as a proxy for behavior

A class name is an implementation detail: the style can change, move to a wrapper, or be merged away by a class-merging helper, and the assertion breaks while the behavior is fine. Worse, the class can be present while the behavior is broken, and the test stays green. In a DOM emulator the stylesheet usually is not even loaded, so the class proves nothing about what renders.

```tsx
// Flag: the class stands in for "this item is selected"
expect(screen.getByText('Widget A')).toHaveClass('bg-primary')

// Prefer: assert the state itself
expect(screen.getByRole('option', { name: 'Widget A' })).toHaveAttribute('aria-selected', 'true')
```

**Exempt:** a component whose contract is to forward a class the consumer passes in (a `className` or `getItemClassName` prop). There the class is the output under test.

**Enumerate by grep, do not eyeball.** Run the `class-assertions.sh` sweep (see Sweeps) over the diff's added test lines.

One line per hit with a verdict, and the count. `0 hits` is printed explicitly.

### §T3. Gates are tested both ways

A gate (`if (mode === Mode.EDIT) render <Editor/>`, a feature flag, a permission check, a view-type condition) is only pinned when a test shows it both open and closed. A test that only mounts the gated thing under the condition still passes if the condition is deleted, because the thing then mounts everywhere.

```tsx
// Flag: one side only; deleting the gate keeps this green
it('shows the editor in edit mode', () => {
  renderWidget({ mode: Mode.EDIT })
  expect(screen.getByTestId('widget-editor')).toBeInTheDocument()
})

// Prefer: both sides
it('hides the editor outside edit mode', () => {
  renderWidget({ mode: Mode.VIEW })
  expect(screen.queryByTestId('widget-editor')).not.toBeInTheDocument()
})
```

Component-level tests of the gated thing in isolation do not satisfy this box; the gate lives in the parent, so the test has to mount the parent.

### §T4. Repeated setup becomes a local helper

When 2+ tests repeat the same setup shape and vary one input, the repetition hides what each test is actually about. Extract a helper at the top of the file so each test reads as input and expected output.

- A render wrapper with defaults: `renderWidget(overrides?)` wrapping the provider boilerplate, returning what the tests assert on.
- A factory for the domain object: `makeItem(id, extra?)` instead of a full literal per test.
- An input builder for values that are noisy to construct: `at(hour, minute = 0)` instead of a full timestamp literal each time.

```tsx
// Flag: the same provider boilerplate per test, one prop varying
render(<SomeProvider value={defaults}><Widget mode="a" /></SomeProvider>)
render(<SomeProvider value={defaults}><Widget mode="b" /></SomeProvider>)

// Prefer
const renderWidget = (overrides: Partial<WidgetProps> = {}) =>
  render(<SomeProvider value={defaults}><Widget mode="a" {...overrides} /></SomeProvider>)
```

Keep the helper local to the test file unless several files genuinely share it. Per-index assertion chains collapse the same way: `expect(result.map((item) => item.offset)).toEqual([0, 25, 50])` over three separate `expect` lines.

### §T5. A test sits beside its unit

A test file lives next to the unit it covers and is named after it (`widget-list.tsx` beside `widget-list.test.tsx`, or whatever suffix the target repo already uses; grep for it). A test in a distant folder is easy to miss when the unit changes, and a test named after something else hides what it covers.

**Do not flag:** end-to-end or integration suites that the target repo keeps in their own top-level folder by convention; confirm the convention by listing that folder.

### §T6. Exact assertions when the value is known

A bound or a truthiness check passes for many wrong values. If the test knows the answer, it asserts the answer.

```ts
// Flag: a length of 1 passes, and so does 40
expect(result.length).toBeGreaterThan(0)
expect(widget.label).toBeTruthy()

// Prefer
expect(result).toHaveLength(3)
expect(widget.label).toBe('Widget A')
```

A tolerance is correct where the value is genuinely inexact (floating point, geometry measured in a real browser): `toBeCloseTo(value, digits)` states the tolerance instead of hiding it in a bound.

**Enumerate by grep, do not eyeball.** Run the `loose-assertions.sh` sweep (see Sweeps) over the diff's added test lines.

The script knows Jest, Vitest and Bun matcher names. If the target repo's test framework names its matchers differently, run the equivalent pattern by hand as well, and state which script or pattern was used. One line per hit with a verdict, and the count. `0 hits` is printed explicitly.

### §T7. A submit is tested per state, by its request body

A save that works when every field is filled in can still break when one is cleared: the field drops out of the payload, or arrives as `''` and fails validation (correctness §B5). For each form or request that saves user input, submit once per field state that behaves differently, at least once after clearing a saved value, and assert the body that went out (from the test's request mock or the recorded call), not only the success message.

```ts
// Flag: only the happy path, and only the outcome
await submitWidgetForm({ note: 'Fragile' })
expect(screen.getByText('Saved')).toBeVisible()

// Prefer: the cleared state too, asserting what was sent
await submitWidgetForm({ note: '' })
expect(lastRequestBody()).toEqual({ name: 'Widget A', note: null })
```

### §T8. An output is tested by what it contains

The quietest failures return a good status with nothing in it: a response with no fields, a page that renders its frame and no rows, an export with headers only. A test that checks only the status code, that the page rendered, or that no error was raised stays green through all of them. It proves the request was handled, not that it produced anything.

Each test of an output asserts at least one value the change is responsible for: a field in the response, a row on the page, a line in the file. When the suite checks many endpoints through one shared helper or shared example, that helper is where this lands: have it assert that the record carries its fields (for example that `attributes` is not empty), so every endpoint that uses it is covered at once.

```ts
// Flag: green even when every field is missing
const response = await get('/orders/ABC-1')
expect(response.status).toBe(200)

// Prefer: assert what the caller reads
expect(response.body.data.attributes).toMatchObject({ number: 'ABC-1', total: 42 })
```

Pair this with correctness §B6: a load cycle that empties a class's fields fails no status check, only a content check.

### §T9. A test names its expected record

A test that works out its expected value with a query has a second copy of the code's rule, and the two drift. The common form is `scope.first` over an order with ties: a `position` that restarts in each parent group, a `created_at` shared by rows inserted in one statement, or no order at all. The database returns any of the tied rows, and the order can change with the plan, the data volume or a vacuum, so the test flakes. Hold the record the setup created (`let!(:first_stage)`) and assert against it, or order on a unique last key (`reorder(:position, :id)`), the same way the code does.

### §T10. Time comes from a clock the test can freeze

Test helpers that freeze time (`travel_to`, `freeze_time`, fake timers) move the app's clock only. A query that reads the database's own clock ignores them, so a test of "an action dated today and due at 23:59 hasn't fired" fails whenever the suite runs across 23:59 or midnight, a few minutes a day, and passes on every rerun. Bind the app's current time into the query, and freeze it in the test at a time far from any boundary (noon), with a separate test for the boundary itself.

### §T11. A test pins every input its result depends on

Factories often sample values so that tests see variety: a random type, a random count, a random offset. That is fine for attributes the code under test ignores and a trap for the ones it branches on. A test of "due at 03:00, not yet due at 02:00" left the action's offset to the factory; one draw in about fifty picked an offset that fires regardless of time, and the case failed in CI and never locally. The neighbouring examples pinned the offset; the new one copied their shape but not that line. List the attributes the code branches on and set each one in the test.

### §T12. A UI test leaves nothing to update outside its waits

A test of a copy-link button clicked it, then awaited `navigator.clipboard.readText()`, then waited for the confirmation toast. The pointer stayed on the button, so its tooltip opened after the hover delay. Locally the clipboard read was instant and the tooltip opened inside the next wait; on CI the read took long enough for the tooltip, and the toast's enter transition, to update outside any wait, and the setup that fails tests on console errors failed it. The first fix waited for the tooltip at the end and passed locally, as the old test had, and CI failed again. Putting a 400 ms delay on the clipboard read reproduced the CI failure in one run; moving the pointer off the button after the click, waiting for the toast first and reading the clipboard inside `waitFor` passed under the same delay.

## Sweeps

Save the diff under review to a file (`gh pr diff <num> > /tmp/review.diff`, or `git diff <default-branch>...HEAD > /tmp/review.diff`) and run each script over it; `-` reads the diff from stdin. Both scan only added lines in test files (`*.test.*`, `*.spec.*`, and anything under `__tests__/`). Each prints one `path:line: text` hit per line, where `line` is the new-side line number, and nothing else. Give every hit its own verdict, and state each receipt with its count, `0 hits` included.

- `added-lines.sh` (citation map): every added line as `path:line: text`, with the source line number at the head SHA. Cite every finding's line from this output or from a sweep hit, never from a position in the diff file.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/added-lines.sh" <diff-file>
  ```

- `class-assertions.sh` (§T2): added test lines referencing `toHaveClass`, `className` or `classList`. Receipt: `grepped class assertions: N hits`.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/skills/kc-testing/scripts/class-assertions.sh" <diff-file>
  ```

- `loose-assertions.sh` (§T6): added test lines holding a bound or truthiness matcher. Receipt: `grepped loose assertions: N hits`.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/skills/kc-testing/scripts/loose-assertions.sh" <diff-file>
  ```
