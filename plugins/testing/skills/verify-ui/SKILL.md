---
name: verify-ui
description: Verify a UI change visually before calling it done. Trigger on "check the UI", "does this look right", "verify my UI change", "screenshot this page", "check dark mode", "check mobile", or before reporting a frontend change complete. Drives the actual screen with realistic data across states, viewports, themes and font scales, and reports what was checked and what was seen. Use when a change touches anything a person looks at.
---

# Verifying a UI change

A green test suite tells you nothing about whether the screen looks right. Unit tests assert the values; they do not notice that the heading is clipped, the empty state never renders, or the total sits under a sticky footer.

So look at it. Once, deliberately, before saying it is done.

## Hard rules

- **Never report a UI change complete without having seen it.** "The tests pass" is not the same claim and must not be presented as one.
- **Report what you did and what you saw**, screen by screen. Not "verified the layout" but "narrow viewport, dark mode: the invoice total wraps under the button".
- **Keep the failure.** If a state renders wrong, that is the finding. Do not adjust the data until it looks fine and then call it passing.
- **Realistic data or nothing.** `Lorem ipsum`, `Test User`, and a three-row list prove only that the happy path with short strings works. Production has 400 rows, names with diacritics, and a description that runs four lines.
- **State what you could not check.** No device, no seed data, no access to that route: say so explicitly rather than quietly narrowing the sweep.
- **Spot checks are not QA.** Opening the screen you just changed and seeing that it renders is a smoke test. QA walks every state the screen can be in, the way a QA engineer works through a test plan, and does that every time, not only when asked.
- **When there is a design, the design is the test plan.** Walk it state by state and compare the app to it. "It renders" and "it matches the design" are different claims.

## Workflow

### Step 1 — list the surfaces

Name every screen, component, and state the diff can reach. A shared component means every consumer of it, not just the one you were working on. If the list is long, say so and prioritize, rather than checking three and implying you checked all.

### Step 1b — when there is a design, build the state matrix from it

Before opening the app, walk the design (mockup, prototype, spec) and write down every state it shows. A state is any setting or condition that changes what the screen renders. Illustrations, not a complete list:

- every on/off switch on the screen, in both positions (a disabled record often hides whole sections, not just a badge)
- every option of a choice that changes the layout (visibility, type, mode, plan)
- every role or permission that sees the screen differently
- with and without each optional piece of data (no items, one item, many)
- every drawer, dialog, menu and confirmation the screen opens, with its exact wording

Then put the app in each state and diff it against the design: which sections, fields, columns and actions appear, in which states, and what they do. Each difference in structure or behaviour is a finding, unless the ticket or the product owner decided otherwise; name that decision when you skip one.

A design is not a pixel spec for things the app already has a pattern for. Titles, button labels, casing, icons, chips and wording follow the app's existing patterns so the product stays consistent; a difference there is not a finding unless the design introduces something the app has no pattern for.

### Step 2 — get real data in front of it

Use the project's seed or fixture path if it has one. Otherwise construct data that is deliberately awkward: a long name, an empty collection, a large collection, a zero amount, a negative amount, a missing optional field, a non-Latin string.

The point is not coverage for its own sake. Every one of those is a shape that has broken a layout before.

### Step 3 — walk the states

For each surface, look at every state it can be in, not only the populated one:

- loading
- empty
- error
- populated, typical
- populated, overflowing (long strings, large counts)
- interactive states worth seeing: focus, hover, disabled, selected

A missing empty state and a missing loading state are the two most commonly shipped omissions, because the developer's data is always already there.

### Step 4 — vary the environment

- **Narrow and wide viewport.** The narrow one is where things break; check it first.
- **Dark and light**, if the project supports both. A colour defined only inside one theme block is invisible in the other.
- **Largest font scale** the platform offers. Text that fits at default clips at 200%.
- **Keyboard only**, for anything interactive: is focus visible, and can you reach every control?

### Step 5 — look for the specific defects

Scan each capture for these, by name, rather than glancing at it:

- clipped or truncated text
- overlapping elements
- content under a safe area, sticky header, or fixed footer
- horizontal scroll on the page body
- a table or code block that overflows instead of scrolling inside its own container
- numbers that fail to line up in a column
- an image with no dimensions causing layout shift
- contrast that fails in one theme but not the other

### Step 6 — report

One line per surface: what you looked at, in which configurations, and what you saw. Then the findings, each with the state and configuration that produced it, so someone else can reproduce it without guessing.

Finish with what you did not check and why.

## Tools

Use whatever the project already has: a browser tool if one is connected, the project's own screenshot or visual-regression setup, a simulator, or a dev server plus a manual look. Do not install a new visual testing framework to satisfy this skill; the point is to look at the screen, not to build an apparatus for looking at screens.

If nothing is available and you genuinely cannot see the UI, say that plainly and let the user decide. A confident "looks good" from something that never rendered the page is the exact failure this skill exists to prevent.

## Gate checklist

Do not report a UI change verified until every box is ticked:

- [ ] Every surface the diff reaches is listed, including other consumers of shared components.
- [ ] If a design exists, the state matrix is written from it, covering every switch in both positions, every layout-changing option, every role, empty/one/many, and every drawer and dialog.
- [ ] The app was put in every state of the matrix and compared to the design section by section, not only the state you happened to land in.
- [ ] Each finding is about structure or behaviour; cosmetic differences where the app has an existing pattern (titles, labels, casing, icons) follow the app.
- [ ] Loading, empty and error states were each seen.
- [ ] Narrow viewport, the other theme and a keyboard pass were done, or the report says why not.
- [ ] The report lists each state checked, each finding with the state that produces it, and what was not checked.
