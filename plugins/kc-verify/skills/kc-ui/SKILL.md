---
name: kc-ui
description: "Verify a UI change visually before calling it done, across states, viewports and themes. Trigger on \"check the UI\", \"does this look right\", \"verify my UI change\", \"screenshot this page\", \"check dark mode\", \"check mobile\", or before reporting a frontend change complete. Usability is kc-ux."
---

# Verifying a UI change

A green test suite says nothing about whether a screen looks right: tests assert values, not that a heading is clipped, an empty state never renders or the total sits under a sticky footer. So look at it, once, deliberately, before saying it is done. This skill checks that it looks right; whether a person can use it is `kc-verify:kc-ux`, and a change a person both sees and uses gets both. The full wording of every rule and step is in `references/detail.md`: read the matching `### ` section when a line here is unclear.

## Hard rules

- Never report a UI change complete without having seen it; "the tests pass" is a different claim.
- The browser check is not optional and never offered as a choice or follow-up. Start down dev servers; use the project's dev-only sign-in (Step 2), and only where it has none ask the user for theirs. Until then nothing is called fixed.
- Report what you did and saw, screen by screen, in configurations ("narrow, dark: the invoice total wraps under the button").
- Keep the failure: a state that renders wrong is the finding; do not adjust the data until it passes.
- Use realistic data: long names, diacritics, 400 rows.
- State what you could not check; spot checks are not QA, QA walks every state, every time.
- A design or reference is the test plan and the comparison is measured: per item against the reference, each total against its parts, kept as a test that fails when an item moves.
- Trace a layout bug through the element and every ancestor in code, then reproduce it at the report's content size in the renderer that produced it (read from evidence); see the fix in that version and the current one.
- Look at the shipped screen running the change's own code, not a story or the author's screenshots; a probe counts only after it was shown to fail (`kc-verify:kc-e2e`).

## Workflow

### Step 1 — list the surfaces

1. Name every screen, component and state the diff can reach; a shared component means every consumer. A long list is prioritized aloud, not silently cut.

### Step 1b — when there is a design, build the state matrix from it

1. Before opening the app, walk the design and write down every state: each switch in both positions, each layout-changing option, each role, none/one/many, each drawer, dialog and confirmation (with its wording, empty, one picked, several picked, editing), and what each create-form choice adds and where the new record lands.
2. Put the app in each state and diff it against the design: sections, fields, columns, actions, and per element presence, order, colour, variant, weight, copy and state. Each structure or behaviour difference is a finding unless the ticket or product owner decided otherwise (name that decision).
3. Compare each new or changed component with its siblings, measured (computed font size, weight, colour).
4. Titles, labels, casing, icons, chips and wording follow the app's patterns; a difference there is not a finding unless the design introduces something the app has no pattern for. Say it was weighed.

### Step 2 — get real data in front of it

1. Bring the app up with one tested command (`bin/dev`, `make up`, a compose file) run as written; write and run one from a clean state if none exists. The report and the walk receipt's `env<TAB><command><TAB><evidence the app answered>` line name it (`check-walk-receipt.sh` requires it).
2. Use the project's seed path, or deliberately awkward data: a long name, empty and large collections, a zero or negative amount, a missing optional field, a non-Latin string.
3. Sign in as a seeded local user through a dev-only credential the local backend mints itself, guarded at every layer (secret only in development, mint refuses elsewhere, compile-time frontend check, build fails if set for production, never in a file). Without one, propose it; the user signs in only until it exists.
4. For a session cookie scoped to a parent domain, sign in from a separate headless browser on a mapped throwaway subdomain (`--host-resolver-rules="MAP qa-abc-1.example.test 127.0.0.1"`), never the developer's own browser.

### Step 3 — walk the states

1. Walk loading, empty, error, populated typical, populated overflowing, and focus, hover, disabled and selected; empty and loading are the most often missing.
2. When the surface finds or rewrites content people write, each shape of it is a state (plain, line breaks, several blocks, formatting, links, images, tables, empty, none) through every action that moves it.
3. Fill a list or page past the viewport and check the background, footer and scrolling hold.
4. Set off each behaviour every way a person can (click, slow and fast scroll, keyboard, deep link, reload), while loading and once settled, on every page sharing the component.

### Step 4 — vary the environment

1. Walk narrow (390 or less), laptop (1280) and wide (1920 or more); narrow first. Walk every dimension the change varies along: viewport, data size, locale (two, one right-to-left), print or PDF, and for a form, dialog or drawer every way out (submit, cancel then submit again, a failed save).
2. List those on the walk receipt's `states:` field (widths in px); `check-walk-receipt.sh` fails a change whose states leave one uncovered.
3. Check dark and light when the project has both, and the largest font scale.

### Step 5 — look for the specific defects

1. Scan each capture by name: clipped text, overlap, content under a safe area or sticky header, page-body horizontal scroll, a table or code block overflowing instead of scrolling, misaligned numbers, an image without dimensions, contrast failing in one theme, a background or border stopping early (scroll to the end), a field sized unlike its neighbours.

### Step 6 — report

1. One line per surface: what you looked at, in which configurations, what you saw. Then findings, each with the state and configuration that produce it, then what you did not check and why.
2. A QA pass on shipped work ends at the report: change no code until the user agrees which findings are bugs or questions and which go in a hotfix versus a ticket. A remark about one finding is input to the triage, not a go-ahead.

### Step 6b — a walkthrough for others (a video of how to test)

1. Before review, the ticket's description ends with a **How to test** section (PR links, merge order, setup, numbered cases with expected results, the video), written for someone who has never seen it, in the team's usual local environment (no ports or worktrees of your own session). Append it without rewording the rest.
2. Open with the setup; one captioned case per frame with its state and expected result; box what to look at in red with a short label.
3. Make a short MP4 (H.264, `yuv420p`, `+faststart`), not a GIF, about 5 s a case; join frames with the `concat` filter, each image its own `-loop 1 -t <seconds>` input.
4. Use the product's main aspect ratio (16:9 for laptops), every frame the same size, framed on the part that changes.
5. Capture at 2x from a headless browser (Playwright `deviceScaleFactor: 2`), never an agent tool's screenshot; draw captions and boxes into the page before the shot; encode at the frames' own size (`-crf 16 -tune stillimage`); read a frame back at 100%.
6. Reach each state through the app's own controls; read every frame whole (menus, highlights, badges, overlays).
7. Embed it as a block media node (copy one from a ticket whose video plays); have someone press play before review.

## Tools

- [ ] Use what the project has (a browser tool, its screenshot setup, a simulator, a dev server); install no new framework. If you cannot see the UI, say so.

## Gate checklist

- [ ] Do not report a UI change verified until every box is ticked:

- [ ] §UI1 Every surface the diff reaches is listed, including other consumers of shared components and every screen any branch or PR of the work changes.
- [ ] §UI2 The app was brought up with one tested command run as written; it is named in the report and the walk receipt's `env` line, or a script was written for it first.
- [ ] §UI3 The app was signed in through the project's dev-only credential, not someone's password; where none exists the guarded path was proposed.
- [ ] §UI4 A parent-domain session cookie was set in a separate headless browser on a mapped throwaway subdomain, never the developer's browser.
- [ ] §UI5 If a design exists, the state matrix covers every switch in both positions, layout-changing option, role, empty/one/many, drawer and dialog.
- [ ] §UI6 Every drawer and dialog was opened and filled in: empty, one item picked, several, and editing an existing item.
- [ ] §UI7 Every matrix state of the running change was compared to the design element by element, its capture beside ours on the walk receipt (`check-walk-receipt.sh`); code and screenshots count for none.
- [ ] §UI8 Items matching a reference (template, guide, total, sheet) were measured against it in numbers, kept as a test that fails when an item moves off it.
- [ ] §UI9 Every new or changed component, and each one moved into a new container, was measured against its siblings (title, subtitle, labels, spacing, field width against content).
- [ ] §UI10 Every behaviour the change touches was set off every way a person can, while loading and settled, on every page sharing the component.
- [ ] §UI11 Findings are about structure or behaviour; cosmetic differences where the app has a pattern follow the app.
- [ ] §UI12 Loading, empty and error states were each seen.
- [ ] §UI13 A surface that finds or rewrites written content was walked with every shape of it through every action that moves it.
- [ ] §UI14 Each create form was submitted for every option that changes it, and the new record's landing state was compared with the design.
- [ ] §UI15 A list or page was filled past the viewport, and the background, footer and scrolling held.
- [ ] §UI16 Every layout defect was traced through its ancestors and reproduced at the report's content size in the named renderer and version; the fix was seen in that version and the current one.
- [ ] §UI17 Narrow, the other theme and the largest font scale were done (or the report says why not); every varied dimension is on the walk receipt's `states:` field.
- [ ] §UI18 Every UI fix was seen fixed in a browser before it was called done, internal admin pages included, not only covered by specs.
- [ ] §UI19 The report lists each state checked, each finding with its state, and what was not checked.
- [ ] §UI20 After a QA pass on shipped work, no code changed until the user agreed which findings are bugs, which are questions, and hotfix versus ticket.
- [ ] §UI21 Before review the ticket ends with How to test (PR links, setup, numbered cases, expected results) and the walkthrough MP4 that opens with the setup, captions each case and boxes what to look at.
- [ ] §UI22 The How to test setup (ticket and PR) is the team's usual local environment, with no port, worktree or server entry from your own session.
- [ ] §UI23 The walkthrough is in the product's main aspect ratio, every frame the same size, captured at 2x in a headless browser and encoded at its own size; a frame read at 100% is sharp.
- [ ] §UI24 The walkthrough is a block player, seen playing on the ticket; each state was reached through the app's own controls and every frame read whole.
