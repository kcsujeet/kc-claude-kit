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

## Workflow

### Step 1 — list the surfaces

Name every screen, component, and state the diff can reach. A shared component means every consumer of it, not just the one you were working on. If the list is long, say so and prioritize, rather than checking three and implying you checked all.

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
