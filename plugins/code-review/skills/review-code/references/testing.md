# Testing gate

> The conventions themselves are stated canonically in the kit's `rules/testing.md`, which loads at authoring time. This file is the review side: the detection criteria and failure modes for grading a diff. Each box stays self-contained so a gate agent needs nothing but this file; when a convention changes, change `rules/testing.md` first and update the affected boxes here to match.

Test rules for the diff under review. Covers six independent failure modes: behavior shipped without a test, class names asserted as a proxy for behavior, a gate tested from one side only, setup copied between tests instead of named once, a test placed away from its unit, and bounds asserted where the exact value is known.

## Gate checklist

The testing gate agent ticks every box against the diff. A box is FAIL if any matching construct violates the rule; the gate is FAIL if any box is FAIL. The whole gate is N/A only when the diff changes no behavior and touches no test file (state that).

- [ ] §T1 Every new behavior (a feature, prop, option, branch, or bug fix) has a test that exercises it, and a bug fix's test fails without the fix. (N/A: no behavior change in diff)
- [ ] §T2 No assertion on a class name as the evidence that a state is correct; assert what the user or a consumer observes (role, text, accessible state, a data attribute, an emitted value). A class that is itself the contract (a `className`-style prop the component forwards) is exempt. **Enumerate by grep** (see below). (N/A: only when the grep returns 0 hits, stated as `grepped class assertions: 0 hits`)
- [ ] §T3 Every gate (a condition that mounts, enables, or routes something) is tested both ways: once with the condition met and once without, so deleting the gate fails a test. (N/A: no gating logic added or changed)
- [ ] §T4 Setup repeated across 2+ tests (the same render-plus-provider boilerplate, fixture literals, or datetime construction) is a local helper, not copy-paste. (N/A: no repeated setup in the diff's tests)
- [ ] §T5 A new or moved test sits beside the unit it covers and is named after it. (N/A: no test file added or moved)
- [ ] §T6 Assertions are exact when the value is known (`toBe(3)`, `toEqual([0, 25, 50])`), not bounds or truthiness that a wrong value also satisfies (`toBeGreaterThan(0)`, `toBeTruthy()`, `toBeDefined()`). A tolerance is fine where the value is genuinely inexact (floating point, measured geometry), stated as `toBeCloseTo`. **Enumerate by grep** (see below). (N/A: only when the grep returns 0 hits, stated as `grepped loose assertions: 0 hits`)

## §T1. New behavior has a test

A change a user or caller can observe ships with a test that would fail if the change were reverted. The test has to reach the new behavior through the unit's real entry point (render the component, call the exported function, hit the route), not through a helper the test builds itself.

**Flag:**
- A new prop, option, or branch with no test that sets it.
- A bug fix with no regression test, or a regression test that passes with the old code (it pins the fixture, not the fix). Ask the author to revert the fix locally and watch the test fail.
- A test that only covers the happy path of a change whose risk is on the unhappy one (empty input, a missing value, a duplicate submit).

**Do not flag:** pure refactors with no observable change, when the existing tests already cover the behavior (name those tests in the evidence).

## §T2. No class-name assertions as a proxy for behavior

A class name is an implementation detail: the style can change, move to a wrapper, or be merged away by a class-merging helper, and the assertion breaks while the behavior is fine. Worse, the class can be present while the behavior is broken, and the test stays green. In a DOM emulator the stylesheet usually is not even loaded, so the class proves nothing about what renders.

```tsx
// Flag: the class stands in for "this item is selected"
expect(screen.getByText('Widget A')).toHaveClass('bg-primary')

// Prefer: assert the state itself
expect(screen.getByRole('option', { name: 'Widget A' })).toHaveAttribute('aria-selected', 'true')
```

**Exempt:** a component whose contract is to forward a class the consumer passes in (a `className` or `getItemClassName` prop). There the class is the output under test.

**Enumerate by grep, do not eyeball.** Over the diff's added test lines:

```bash
<diff command> | grep -nE '^\+.*(toHaveClass|className|classList)'
```

One line per hit with a verdict, and the count. `0 hits` is printed explicitly.

## §T3. Gates are tested both ways

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

## §T4. Repeated setup becomes a local helper

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

## §T5. A test sits beside its unit

A test file lives next to the unit it covers and is named after it (`widget-list.tsx` beside `widget-list.test.tsx`, or whatever suffix the target repo already uses; grep for it). A test in a distant folder is easy to miss when the unit changes, and a test named after something else hides what it covers.

**Do not flag:** end-to-end or integration suites that the target repo keeps in their own top-level folder by convention; confirm the convention by listing that folder.

## §T6. Exact assertions when the value is known

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

**Enumerate by grep, do not eyeball.** Over the diff's added test lines:

```bash
<diff command> | grep -nE '^\+.*(toBeGreaterThan|toBeLessThan|toBeGreaterThanOrEqual|toBeLessThanOrEqual|toBeTruthy|toBeFalsy|toBeDefined|not\.toBeNull|not\.toBeUndefined)'
```

Adapt the matcher names to the target repo's test framework before running, and state which pattern was used. One line per hit with a verdict, and the count. `0 hits` is printed explicitly.
