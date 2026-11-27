# Testing: examples and edge cases per box

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

A render counts as setup however short. `render(<WidgetCard title="A" />)` in one test and `render(<WidgetCard title="B" badge />)` in another is one call each, and is still the same component set up twice with one prop varying: write `renderCard(overrides)` once. `repeated-render.sh` lists each inline render of a component that 2+ added lines of one test file render; a helper's own render is not a copy, so a file whose tests all go through a helper has no hits. A one-expression read (`screen.getByRole('button')`) stays inline (simplicity §P11).

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
