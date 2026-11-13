---
name: kc-testing
description: "Testing conventions for test files and the code they cover in TypeScript, JavaScript and other languages: tests first, a test for every behavior and bug fix at the unit that owns it and nothing it didn't change, exact assertions, no class-name assertions, gates tested both ways, local setup helpers, and tests placed beside their unit. Use when writing or reviewing tests, or any change that adds behavior or fixes a bug."
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
  - §T13. A change that moves a value updates every fixture that restates it
  - §T14. A failing assertion names what is wrong
- Sweeps

## Rules

The loop is not a formality at the end. A change is not done until it is green.

- Write the failing test first. Watch it fail for the right reason, then make it pass. A test that passed the moment you wrote it proved nothing.
- A test is written for a break it would catch in real use, never to make a suite or a coverage count green: it sets up a situation the code really meets and fails when that behaviour breaks. Code nothing real reaches is deleted, not tested.
- Run the project's check and test commands after each meaningful edit, not once at the very end when the cause of a failure is buried under ten changes.
- Never disable, skip, or narrow a test to reach green. If a test is wrong, say why before changing it, and change it as its own visible decision.
- Do not start a long-running process to "verify" a change. A dev server or watcher never exits; use the one-shot check and test commands.
- Tests live beside the code they cover, named after it.
- A test sits beside the unit that owns the behaviour it asserts, even when only one caller uses that unit today; the caller's test checks only its wiring. A reviewer's "put it next to X" is checked against this before it is followed.
- Every test, assertion or guard a change removes (by hand, a restore, a revert, a merge, a regeneration) is listed with what covers its behaviour now, or called out as intended.
- Assert the exact value when you know it: `toBe(3)`, not `toBeGreaterThan(0)`. A tolerance is for values that are genuinely inexact, stated as one.
- Assert what a user or caller observes (role, text, state, a returned value), not a class name standing in for it.
- Test what the change adds, once, at the unit that owns it. A shared unit's new behaviour is tested in the shared unit's tests; each caller's test covers only its own wiring (that it turns the option on, the values and names it passes). Behaviour the change didn't touch gets no new case. When the test diff dwarfs the code diff, cut it back to that.
- A condition that mounts or enables something is tested both ways, met and not met, so deleting it fails a test. Two exceptions: the off side of an opt-in the change adds is every existing caller's unchanged behaviour, not a new one, and needs no new case; and a guard whose only job is to keep an absent optional input from crashing (`onChange?.(value)`) is not a gate.
- Setup repeated across tests becomes a local helper (`renderWidget(overrides?)`, `makeItem(id)`), not copy-paste. Setup one test uses stays inline in it, and `describe` blocks stay flat: nest one only for a group that shares setup its siblings don't.
- Cover the unhappy paths deliberately: the empty collection, the expired token, the duplicate submit, the interrupted write. The happy path is the one that already works.
- When a bug is fixed, the regression test comes with it in the same change, and it must fail without the fix. Where nothing the repo runs can reach the changed code (a template no test runner loads, a print stylesheet, a config only production reads), the pull request records the before and after it was checked with, and says the gap is there; the fix doesn't bring a new test framework with it.
- A form or request that saves user input is tested for every state that behaves differently (at least clearing a saved value), asserting the request body that goes out, not only that the save succeeded.
- A test of an output (a response, a rendered page, an export, a message) asserts what it contains, so an output that comes back empty fails it. A status code, "it rendered" or "no error" passes when every field is missing. Shared test helpers that check responses assert their content too.
- A test names the record it expects: the one it created, or one picked with an order whose last key is unique. `first` over an order with ties (a position that restarts per group, a timestamp, an unordered query) returns any of the tied rows, so the test passes or fails depending on the database's mood.
- Code that compares against "now" takes it from the app's clock and passes it in (a bound parameter to SQL), not from the database (`CURRENT_TIMESTAMP`, `NOW()`, `CURRENT_DATE`), and its tests freeze that clock. A database clock can't be frozen, so a test that checks "not due yet" passes or fails by the hour CI happens to run.
- A test sets every attribute its result depends on, instead of taking the factory's default. A factory that samples values (a random type, a random offset) makes a test that leaves them unset pass or fail by the draw, and the run's seed usually doesn't reproduce it. Read the factory before relying on its defaults.
- A fixture standing for data the code receives (an API response, a stored record) is shaped like real records, including the ones older code saved (a key missing, a null, a number as a string), not like the type: a fixture built from the type only ever tests what the current code writes.
- A change that moves or renames a value (an enum member, a type, a category, a status, a config key) updates every test, factory and setup that hard-codes the old value, in the same change. "Still passes" is no reason to leave one: the next test that reads that value inherits the wrong data.
- An assertion compares the records it found to the set it expects (or asserts they exist first), and never dereferences a lookup that can come back empty (`find_by(...).attr`, `list.find(...)!.x`, `rows[0].field`): when it fails, the message names what is missing or wrong, not a crash on nil. A sibling test's shape (a loop of per-item lookups) is not copied when it breaks this.
- A UI test awaits only the testing library's own waits and events between an action and its last assertion, so every update the action starts (a hover tooltip, a transition, a ripple) lands inside them. A bare `await` on something else (a clipboard read, a timer, a fetch) leaves a gap where a slow runner lets those updates land outside, and the test fails in CI only. End hover state the action leaves behind (`unhover`) rather than wait for its effect.
- A test that fails only in CI is reproduced locally before a fix is called done: slow down the suspected gap (a delay at that `await`, a slower mock) until it fails the way CI does, then show the fix passes under the same delay. A fix that passed locally before and after proves nothing.
- When the end-to-end suite runs in a harness or fixture app, each headline user-facing feature also gets at least one test that drives the shipped app (its demo or default configuration, with its seed data). A suite that only ever sees clean fixtures cannot catch a bug that needs the real combination of settings and data.

Detection criteria and per-box review failure modes live in the `## Review checklist` of the `kc-testing` skill (`kc-conventions:kc-testing`), with the detail under its `## Review detail`. These rules are the statement of the convention; that checklist is how a diff gets graded against it.

## Review checklist

The testing gate agent ticks every box against the diff. A box is FAIL if any matching construct violates the rule; the gate is FAIL if any box is FAIL. The whole gate is N/A only when the diff changes no behavior and touches no test file (state that).

- [ ] §T1 Every new behavior (a feature, prop, option, branch, or bug fix) has a test that exercises it, and a bug fix's test fails without the fix. Each case puts the code in a situation it really meets and fails when the behaviour it names breaks: a case that asserts what its own setup put there (a mock's stub, a constant), covers a state nothing real reaches, or still passes with its line broken FAILS. Each is tested once, at the unit that owns it: a test case the diff adds FAILS when it pins behaviour the diff didn't change, re-tests a shared unit's behaviour through a caller (the caller's test covers only its own wiring), or repeats a case the owning unit's tests already have. **Enumerate**: one line per test case the diff adds, naming the changed behaviour it pins and why this file owns it. Every test, assertion, check or guard the diff deletes, however it arrives (by hand, a restore of an older file, a revert, a merge, a regeneration, a refactor), is listed with the test or check that covers its behaviour now, or the removal is named as intended with its reason; a deletion with neither FAILS, and the behaviour it pinned counts as untested again. **Enumerate** these too: one line per removed test case or assertion in the diff. Code that nothing the repo runs can reach (no runner loads it, shown by a search of the test setup) passes when the pull request records the before and after it was checked with and names the gap; with neither recorded it FAILS. (N/A: no behavior change, no test case added and no test or check removed in the diff)
- [ ] §T2 No assertion on a class name as the evidence that a state is correct; assert what the user or a consumer observes (role, text, accessible state, a data attribute, an emitted value). A class that is itself the contract (a `className`-style prop the component forwards) is exempt. **Enumerate with the `class-assertions.sh` sweep** (see below). (N/A: only when `class-assertions.sh` returns 0 hits, stated as `grepped class assertions: 0 hits`)
- [ ] §T3 Every gate (a condition that mounts, enables, or routes something) is tested both ways: once with the condition met and once without, so deleting the gate fails a test. **Enumerate with the `surviving-mutants.sh` sweep's output** when the dispatch gives it: every surviving mutant, gate or not, gets its own verdict, the test that would fail on it, or no behaviour (the code changes nothing) and its deletion. Without it, or when it printed `not run`, each gate is named with the test covering each side. Two sides need no new case, and their verdict says which applies: the off side of an opt-in the change adds (existing callers' unchanged default), and a guard that only keeps an absent optional input from crashing (`onChange?.(value)`). Neither is a reason to ask for a test. (N/A: no gating logic, condition or early exit added or changed)
- [ ] §T4 Setup repeated across 2+ tests (the same render-plus-provider boilerplate, fixture literals, or datetime construction) is a local helper, not copy-paste. Setup means more than one plain expression: a repeated one-expression read stays inline at each test (simplicity §P11). The converse also FAILS: a helper, locator or lazy fixture the diff adds that only one test uses, and a nested `describe` whose group shares no setup its siblings lack. (N/A: no setup, helper or `describe` added in the diff's tests)
- [ ] §T5 A new or moved test sits beside the unit that owns the behaviour it asserts and is named after it; a caller's test file asserts only the caller's own wiring, never the cases of a unit it calls. Where the diff or a reviewer puts a test ("next to the existing case") is checked against this before it is followed. (N/A: no test file added or moved)
- [ ] §T6 Assertions are exact when the value is known (`toBe(3)`, `toEqual([0, 25, 50])`), not bounds or truthiness that a wrong value also satisfies (`toBeGreaterThan(0)`, `toBeTruthy()`, `toBeDefined()`). A tolerance is fine where the value is genuinely inexact (floating point, measured geometry), stated as `toBeCloseTo`. **Enumerate with the `loose-assertions.sh` sweep** (see below). (N/A: only when `loose-assertions.sh` returns 0 hits, stated as `grepped loose assertions: 0 hits`)
- [ ] §T7 A submit is tested per state: each form or request that saves user input has a test for every field state that behaves differently (at least clearing a saved value; see correctness §B5), and each test asserts the request body sent, not only the success path. (N/A: the diff adds or changes no submit of user input)
- [ ] §T8 Every test of an output the diff adds or changes (a response, a rendered page, an export, a message) asserts at least one value inside it that the change is responsible for, so an empty or field-less output fails the test. A test that asserts only a status code, that something rendered, or that no error was raised FAILS. A shared helper or example that checks responses counts as the test, and is held to the same rule. (N/A: the diff adds or changes no output and no test of one)
- [ ] §T9 Every expected record in a test is named, not re-derived: it is a record the test created and holds, or a lookup whose order ends on a unique key. A `first`/`last`/`take` (or `[0]` on a query result) over an order that can tie FAILS; the evidence names the ordering columns and why they cannot tie. **Enumerate**: grep the test diff for `.first`, `.last`, `.take` and `[0]` on query results, one verdict per hit. (N/A: `grepped first/last/take: 0 hits`)
- [ ] §T10 Time-dependent behaviour is tested at a frozen time: each test of code that compares against now (due, overdue, today, expiry, local hour) freezes the clock, and the code reads now from that clock, not from the database. A query the diff adds or changes that uses `CURRENT_TIMESTAMP`, `NOW()` or `CURRENT_DATE` for a comparison a test covers FAILS. **Enumerate**: grep the diff for those three, one verdict per hit. (N/A: `grepped database clock: 0 hits` and no time comparison added)
- [ ] §T11 Every record a new or changed test builds sets each attribute the code under test branches on; the evidence names the factory and confirms each such attribute is either set in the test or fixed (not sampled) in the factory. A branch-deciding attribute left to a factory that samples it FAILS. When the change handles data saved by older code or another client, a test builds that shape (the key missing, the null, the string), and the evidence names the real record or schema it was taken from. (N/A: the diff adds or changes no test that builds records, and handles no data saved by older code or another client)
- [ ] §T12 In every UI test the diff adds or changes, each `await` between the first user action and the last assertion is the testing library's own (a user event, `findBy*`, `waitFor`); a bare `await` on anything else (`navigator.clipboard.readText()`, a sleep, a direct fetch) FAILS, and so does hover or focus state an action leaves behind without an `unhover`/`blur` or a wait for its effect. A fix for a CI-only failure in such a test names the delay that reproduced it locally. **Enumerate**: grep the test diff for `await ` lines that are not `user.`, `findBy`, `findAllBy` or `waitFor`, one verdict per hit. (N/A: the diff adds or changes no UI test)
- [ ] §T13 When the diff moves or renames a value (an enum member, a type, a category, a status, a config key, a constant), every test file, factory and setup in the repo that hard-codes the old value is updated in the diff, not only the tests the change broke. A fixture still holding the old value FAILS even when the suite passes, and so does one the author listed and left because it passed. **Enumerate**: list the literals the diff's non-test lines remove or replace, grep every test and factory file for each, one verdict per hit. (N/A: the diff moves or renames no value, stated as `removed literals: none`)
- [ ] §T14 Every assertion the diff adds or changes compares the records found to the set expected (the whole collection to the expected one, or presence asserted first), and none dereferences a lookup that can return nothing (`find_by(...).attr`, `list.find(...)!.x`, `rows[0].field`), so a missing or wrong record fails with a message that names it, not a crash on nil or undefined. A sibling test's loop of per-item lookups is not a reason to keep that shape (simplicity §P13 defers to this box). **Enumerate**: grep the test diff for a member access, `!` or `[0]` directly on a lookup result, one verdict per hit. (N/A: the diff adds or changes no assertion on looked-up records)

## Review detail

Test rules for the diff under review. Covers eight independent failure modes: behavior shipped without a test, class names asserted as a proxy for behavior, a gate tested from one side only, setup copied between tests instead of named once, a test placed away from its unit, bounds asserted where the exact value is known, a submit tested only on its happy path, and an output tested only for its status.

### §T1. New behavior has a test

A change a user or caller can observe ships with a test that would fail if the change were reverted. The test has to reach the new behavior through the unit's real entry point (render the component, call the exported function, hit the route), not through a helper the test builds itself.

**Flag:**
- A new prop, option, or branch with no test that sets it.
- A bug fix with no regression test, or a regression test that passes with the old code (it pins the fixture, not the fix). Ask the author to revert the fix locally and watch the test fail.
- A test that only covers the happy path of a change whose risk is on the unhappy one (empty input, a missing value, a duplicate submit).

**Do not flag:** pure refactors with no observable change, when the existing tests already cover the behavior (name those tests in the evidence).

**A real situation, and a real failure.** A test exists to catch a break before a user does, not to make a suite or a coverage count green. Each case puts the code in a situation it really meets (an input a caller sends, a state the data can be in, a sequence a person goes through) and fails when the behaviour it names breaks. Check it the way §T3's mutation sweep does: break the line the case is about and watch that case fail. When nothing real reaches a branch, delete the branch rather than write a case for it.

**Flag:**
- A case that asserts what its own setup put there: a mock asserted to return its stub, a constant compared with itself, a stubbed call asserted to have been made with the arguments the test passed straight through.
- A case for a state the code can never reach (an input every caller already rules out, a link that points to itself), written to cover a line.
- A case that still passes when the line it names is broken.

Examples: a test that a price formatter "formats prices" by mocking the formatter; a test that a retry helper retries, against a stub that never fails; a guard against a symlink that resolves to itself, which no real repository has, given a test when it should have been deleted.

**What a diff removes is accounted for.** The diff of a restore, revert, merge or regeneration looks like a pile of changes, and the lines it quietly takes out are the ones nobody reviews. For each test, assertion, validation or guard the diff removes, say what covers its behaviour now (another case, the owner's test, a check elsewhere) or that the behaviour is gone on purpose. Examples: a refactor that dropped an input validation together with its test, so neither exists; a revert that took a security check along with the change it reverted; restoring an older version of a test file that deleted the cases added since.

**Once, where it lives.** The other way a change's tests go wrong is by saying too much. A test diff that restates behaviour the change didn't touch, re-tests a shared unit through each of its callers, and adds a case for every guard a reviewer can imagine ends up several times the size of the code change, and the reader can't find the cases that matter. Each behaviour the change adds is tested once, at the unit that owns it.

- A shared formatter gains a `currency` option that the checkout page passes. The formatter's tests get a case per currency rule; the checkout page's test checks only that it passes the storefront's currency. Not: the default formatting again (unchanged), the formatting rules again through the checkout page, or a case for a missing option that falls back to the old default.
- A shared table gains sortable columns, turned on by one list page. The table's tests sort; the list page's test checks that it marks the right columns sortable.
- An endpoint gains a filter. The endpoint's tests filter; a client that calls it checks the parameter it sends, not the filtering.

**Flag:**
- A case for behaviour the diff didn't change (the old default, a click that already worked), unless the change could plausibly have broken it and no existing test pins it; then name why.
- A caller's test that asserts the shared unit's behaviour (validation, submit handling, formatting) instead of what the caller passes it.
- A case per imaginable guard: an optional callback called with `?.`, a fallback to the existing default. See §T3 for what is and isn't a gate.

```tsx
// Flag: the caller re-tests the shared form's Enter handling and validation
it('submits once on Enter', ...)
it('does not submit on Enter when the name is empty', ...)
it('submits once when Create is clicked', ...)

// Prefer: the caller's own wiring only
it('saves the typed name on Enter', async () => {
  renderOrderNoteForm({ onSave })
  await user.type(screen.getByRole('textbox', { name: 'Note' }), 'Fragile{Enter}')
  expect(onSave).toHaveBeenCalledWith({ note: 'Fragile' })
})
```

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

**What needs no new case.** Both ways is for a condition that changes what someone gets. Two sides don't:

- The off side of an opt-in the change adds. A new `sortable` option that defaults to off leaves every existing table as it was; the off side is old behaviour, so the met side's test is the new one, and §T1 says unchanged behaviour gets no new case.
- A guard whose only job is to keep an absent optional input from crashing: `onChange?.(value)`, `if (logger) logger.info(...)`. Its not-met side is "nothing happens"; a test for it pins the language's optional call, not the code's behaviour.

A surviving mutant on either gets that verdict, not a request for a test.

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

The converse holds too: setup that one test uses stays inline in it. A locator helper, a lazily built fixture or a nested `describe` that serves one case adds a layer the reader has to unwind for nothing. Keep `describe` blocks flat: one per unit, with a nested one only for a group that shares setup its siblings don't.

Keep the helper local to the test file unless several files genuinely share it. Per-index assertion chains collapse the same way: `expect(result.map((item) => item.offset)).toEqual([0, 25, 50])` over three separate `expect` lines.

### §T5. A test sits beside its unit

A test file lives next to the unit it covers and is named after it (`widget-list.tsx` beside `widget-list.test.tsx`, or whatever suffix the target repo already uses; grep for it). A test in a distant folder is easy to miss when the unit changes, and a test named after something else hides what it covers.

The unit that owns the behaviour is the one whose change would make the case fail, which is not always the file the diff is open in or the one next to the nearest similar case. A formatter's cases belong in the formatter's test even when only a page calls it today, and the page's test then asserts only that it calls the formatter. A reviewer's "put it next to X" is followed only when X is that owner; when X is itself in the wrong place, the test goes to the owner and the answer says why (§S14).

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

The shape of a fixture is an input too. A shared fixture written from the type has every key the type requires, so every test built on it sees only records the current code would write. Records saved by an older version, another client or an import can lack a key, hold a null, or carry a number as a string, and code that breaks on them passes every test. Take fixtures from real records (a recorded API response, a sample of rows, the server's schema for which keys are optional), and give a change that handles such data a test with that shape. Examples: an order fixture that always has a discount field, while old orders have none; a profile fixture with a numeric age where the API sends a string.

### §T12. A UI test leaves nothing to update outside its waits

A test of a copy-link button clicked it, then awaited `navigator.clipboard.readText()`, then waited for the confirmation toast. The pointer stayed on the button, so its tooltip opened after the hover delay. Locally the clipboard read was instant and the tooltip opened inside the next wait; on CI the read took long enough for the tooltip, and the toast's enter transition, to update outside any wait, and the setup that fails tests on console errors failed it. The first fix waited for the tooltip at the end and passed locally, as the old test had, and CI failed again. Putting a 400 ms delay on the clipboard read reproduced the CI failure in one run; moving the pointer off the button after the click, waiting for the toast first and reading the clipboard inside `waitFor` passed under the same delay.

### §T13. A change that moves a value updates every fixture that restates it

Tests that build records by hand restate the values the code decides on. When a change moves one (a feature's category from `beta` to `addon`, a status renamed, a type split), nothing forces those restatements to follow: no test asserts the old value, so the suite stays green while the fixtures describe data that no longer exists. The next test that reads the value, or the next reader copying a setup, inherits the wrong data. Finding them takes one pass: list the literals the change removes, grep the tests and factories for each, and update every hit in the same change. Listing them while assessing the change and leaving them because they pass is the failure, not the exemption. Examples: orders created with a `pending` status the change renamed `open`; a plan fixture on a tier the change retired; a config key renamed in code and still set in a test helper.

### §T14. A failing assertion names what is wrong

`expect(items.find(byKey(key))!.category).toBe('addon')` inside a loop over keys fails with "cannot read property of undefined" when one key is missing: the failure says a lookup came back empty and not which key. Compare the found set to the expected one instead, so the failure is a diff that names the key and its wrong value: `expect(categoriesByKey(keys)).toEqual(Object.fromEntries(keys.map((key) => [key, 'addon'])))`, or `expect(rows.map(r => r.id)).toEqual(ids)` before reading fields. The same goes for `find_by(...).attr`, `rows[0].field`, and a `.get()` whose miss raises: a lookup that can miss gets its presence asserted, or is replaced by a comparison of the whole result. When a sibling test already loops over per-item lookups, the finding names this box rather than following the sibling (simplicity §P13).

## Sweeps

Save the diff under review to a file (`gh pr diff <num> > /tmp/review.diff`, or `git diff <default-branch>...HEAD > /tmp/review.diff`) and run each script over it; `-` reads the diff from stdin for the two assertion sweeps. Those two scan only added lines in test files (`KC_TEST_PATHS` in `scripts/lib/diff-lines.sh`: `*.test.*`, `*.spec.*`, `*_test.*`, `*_spec.*`, `test_*.py`, and anything under `test/`, `tests/`, `spec/`, `__tests__/` or `e2e/`). Each prints one `path:line: text` hit per line, where `line` is the new-side line number, and nothing else. Give every hit its own verdict, and state each receipt with its count, `0 hits` included.

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

- `surviving-mutants.sh` (§T3), run by the review's caller, never by a gate: the dispatch gives its output, and the gate grades it. In a throwaway checkout of HEAD, it breaks each condition and early exit on the diff's added code lines one at a time (and swaps the two sides of a value fallback, `a?.b || c.d` or `??`, which a fixture that leaves one side empty never tells apart), runs the tests, and prints each break no test noticed, after a summary line. The caller runs it from the repo root, with the install command as `--setup` when a fresh checkout needs one, once per area with `--paths` set to its paths, before dispatching the gates. In a fix check it runs on the whole diff, so a test added for an earlier survivor is shown to catch it. It takes minutes, inside its `--max-minutes` budget (default 8), and lists every line the budget did not reach. Receipt: its summary line, then a verdict per survivor and per line not reached; `not run: <reason>` is stated as the receipt, and §T3 is then walked by hand.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/skills/kc-testing/scripts/surviving-mutants.sh" <diff-file> --test '<command>' [--setup '<command>'] [--paths '<regex>']
  ```
