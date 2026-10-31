---
name: kc-ui
description: Verify a UI change visually before calling it done. Trigger on "check the UI", "does this look right", "verify my UI change", "screenshot this page", "check dark mode", "check mobile", or before reporting a frontend change complete. Drives the actual screen with realistic data across states, viewports, themes and font scales, and reports what was checked and what was seen. Use when a change touches anything a person looks at.
---

# Verifying a UI change

A green test suite tells you nothing about whether the screen looks right. Unit tests assert the values; they do not notice that the heading is clipped, the empty state never renders, or the total sits under a sticky footer.

So look at it. Once, deliberately, before saying it is done.

## Hard rules

- **Never report a UI change complete without having seen it.** "The tests pass" is not the same claim and must not be presented as one.
- **The browser check is not optional.** It is part of fixing a UI bug, the same as the code change: never offer it as a choice or a follow-up ("QA first, or post as is?"), and never tell a tester or reviewer something is fixed before you have seen it fixed. If the dev servers are down, start them; if a sign-in stands in the way, use the project's dev-only sign-in (Step 2), and only where it has none, ask the user for theirs. Until then nothing is called fixed.
- **Report what you did and what you saw**, screen by screen. Not "verified the layout" but "narrow viewport, dark mode: the invoice total wraps under the button".
- **Keep the failure.** If a state renders wrong, that is the finding. Do not adjust the data until it looks fine and then call it passing.
- **Realistic data or nothing.** `Lorem ipsum`, `Test User`, and a three-row list prove only that the happy path with short strings works. Production has 400 rows, names with diacritics, and a description that runs four lines.
- **State what you could not check.** No device, no seed data, no access to that route: say so explicitly rather than quietly narrowing the sweep.
- **Spot checks are not QA.** Opening the screen you just changed and seeing that it renders is a smoke test. QA walks every state the screen can be in, the way a QA engineer works through a test plan, and does that every time, not only when asked.
- **When there is a design, the design is the test plan.** Walk it state by state and compare the app to it. "It renders" and "it matches the design" are different claims.
- **A moved field is two screens.** When a screen stops editing a value and points elsewhere ("managed in product settings", a read-only value with a link), follow the pointer: open the destination, confirm the field is there and saves, and that the first screen shows the new value without a reload. Compare the destination with the design's version of it too. A pointer to a screen that cannot edit the value is a bug, and so is a read-only value that no screen edits.
- **Trace a layout bug before parking it.** A reported layout defect (a gap, a bar, content past its background) is read in code first: the element's styles, then every ancestor up to the root layout (display, fixed sizes, overflow, backgrounds). "Needs a look in the browser" is not a status; reproduce it there with the same content size the report shows.
- **Look at the shipped screen, not a stand-in.** A story, fixture page or test harness is not the app. Check the change where users see it, with its real configuration, and treat a probe as evidence only after it has been shown it can fail (see `kc-verify:kc-e2e`).

## Workflow

### Step 1 — list the surfaces

Name every screen, component, and state the diff can reach. A shared component means every consumer of it, not just the one you were working on. If the list is long, say so and prioritize, rather than checking three and implying you checked all.

### Step 1b — when there is a design, build the state matrix from it

Before opening the app, walk the design (mockup, prototype, spec) and write down every state it shows. A state is any setting or condition that changes what the screen renders. Illustrations, not a complete list:

- every on/off switch on the screen, in both positions (a disabled record often hides whole sections, not just a badge)
- every option of a choice that changes the layout (visibility, type, mode, plan)
- every role or permission that sees the screen differently
- with and without each optional piece of data (no items, one item, many)
- every drawer, dialog, menu and confirmation the screen opens, with its exact wording, in each state of filling it in: empty, one item picked, several picked, and editing an existing item (what appears after a pick is where drawers differ most)
- what each choice in a create form adds to the form (picking one option can reveal a required field), and the state the new record lands in after create: switched on or off, which sections show

Then put the app in each state and diff it against the design: which sections, fields, columns and actions appear, in which states, and what they do. Each difference in structure or behaviour is a finding, unless the ticket or the product owner decided otherwise; name that decision when you skip one.

Then compare every new or changed component with its siblings on the same screen: a new card next to existing cards uses the same title size, subtitle style, field label style and spacing. Measure it (computed font size, weight and colour) rather than eyeballing it.

A design is not a pixel spec for things the app already has a pattern for. Titles, button labels, casing, icons, chips and wording follow the app's existing patterns so the product stays consistent; a difference there is not a finding unless the design introduces something the app has no pattern for.

### Step 2 — get real data in front of it

Use the project's seed or fixture path if it has one. Otherwise construct data that is deliberately awkward: a long name, an empty collection, a large collection, a zero amount, a negative amount, a missing optional field, a non-Latin string.

The point is not coverage for its own sake. Every one of those is a shape that has broken a layout before.

Sign in as a seeded local user without anyone's password. When sign-in goes through an outside identity provider, a check that waits on the user's password stalls every time a dev server restarts or runs on a new port: browser sessions and cookies are kept per origin. Look for a credential the local backend can mint itself, often an auth strategy it already accepts (an API key, a signed token) that only tests create. Have the frontend send it only in its development mode. If the project has no such path, propose one before building it, guarded at every layer:

- The secret signing the credential exists only in development, so staging and production reject it.
- The mint command refuses to run outside the development environment.
- The frontend reads it behind a compile-time development check, so production builds drop it.
- The build fails if the variable is set for a production build, rather than ignoring it.
- The credential lives in the process environment, never in a committed file or in chat.

### Step 3 — walk the states

For each surface, look at every state it can be in, not only the populated one:

- loading
- empty
- error
- populated, typical
- populated, overflowing (long strings, large counts)
- interactive states worth seeing: focus, hover, disabled, selected

A missing empty state and a missing loading state are the two most commonly shipped omissions, because the developer's data is always already there.

### Step 3b — walk the flows around the change

Each state above can look right while the path into it is broken. QA by a person finds these first, because a person moves between screens and keeps going. Walk them on every surface the change reaches:

- **Switch context mid-page.** Change the current tenant, workspace or account while on each changed page. Every panel follows, with no reload; a record that belongs to the previous context shows a clear not-found, not a blank or half-loaded page.
- **Go where the write shows up.** After each create, edit, archive or delete, visit every other screen that shows something derived from it (a list, a count, a badge, a picker on another page) without reloading, and check it changed, and that it didn't appear where its filters exclude it.
- **Use the records real data holds.** Include records the new screens can no longer create: blank optional fields, old links, defaults from before a migration. Then try the new actions next to them (create one more, link, delete).
- **Keep archived records around.** Archive, deactivate or soft-delete one of each kind the screen counts or lists, then check every count, list and picker leaves it out unless it says otherwise.
- **Cross the tenant line.** View a record linked to records in another tenant or workspace from this one: the others show by name or not at all, never as raw ids, and can't be changed from here.
- **Do each interaction twice.** Search, pick, search again, pick again; add, remove, add; open, close, reopen. State that survives one pass often breaks on the second.
- **Clear every field you can edit, and save; then enter an invalid value and save.** Expect a message on the field, or a sensible default, never a generic error.
- **Discard every kind of change.** In each section with Save and Discard, change a field, pick a file and remove a file, then Discard. The saved record is unchanged after a reload, with no request sent before Save.
- **Read every confirmation against what happens.** After confirming, check the result matches the words: "remove" that deletes, or "delete" that only unlinks, is a finding. Read alerts and helper text the same way, as the user would: plain words, no internal terms, no stray spaces around an inserted value.
- **Follow every action to where it lands.** People shouldn't have to learn the product to use it. Click each button and link the change adds or points somewhere new, from each entry point, and check it lands where the thing it names can be done at once, with no hunting, scrolling past other content or reading first: "Choose a plan" lands on the plans, not the top of a page above them; "Add a storefront" opens the form, not the list. Look once the page has finished loading, since content that arrives late (a signed-in header, a banner) can push the target out of view. The steps after that follow the order people know from other products (`kc-conventions:kc-simplicity` §P17).
- **See signed-in state everywhere it shows.** Sign in from each entry point, then check every surface that shows who is signed in, and what a signed-in person should and shouldn't see.
- **Fill it past the screen.** Make a list or page taller than the viewport and check the background, footer and scrolling hold.
- **Start from a fresh record.** Create the thing through the UI and take it through the whole flow it exists for. When a result looks wrong, check the inputs before calling it a bug: a total of zero explains a skipped payment.

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
- a background or border that stops before the content does (scroll to the very end of the page)

### Step 6 — report

One line per surface: what you looked at, in which configurations, and what you saw. Then the findings, each with the state and configuration that produced it, so someone else can reproduce it without guessing.

Finish with what you did not check and why.

A QA pass on something already shipped ends at the report: change no code until the findings are triaged with the user, each one sorted into a bug or a question for the team, then into a fix now (a hotfix) or a ticket for later, with what introduced it checked in history. A remark about one finding during that talk ("this should be X") is input to the triage, not a go-ahead to build X while the rest are untriaged.

### Step 6b — a walkthrough for others (a video of how to test)

When the evidence is for someone who doesn't know the change (a tester, the reporter, a reviewer), it must explain itself without you there. Before a change goes to review, its ticket gets a **How to test** section at the end of the description, written for someone who has never seen it: links to the change's pull requests (with the merge order when one depends on another), the setup, the cases as numbered steps with what to expect, and the walkthrough video embedded under them. Append it without rewording the rest of the description. Write the setup for the team's usual local environment (the hostnames and commands everyone runs), in the pull request's How to test too, never the ports, worktrees or server entries of your own session: a reader can't follow `localhost:3014` and a CORS override they don't run.

The walkthrough:

- **Open with the setup**: the data each case needs, the switch or setting and where it lives, and the checks in order.
- **One case per frame or clip, captioned** with the state ("Flag on, record not archived") and the expected result in one sentence.
- **Box what to look at.** A red outline around the part that changes, with a short label inside it ("Archived item hidden"). Where the change is something missing, box what remains and say so ("Only the open item shows").
- **Make it a video, not a GIF.** A GIF can't be paused or scrubbed, and a still first frame reads as an image, so people stop watching. Build a short MP4 (H.264, `yuv420p`, `+faststart`) with each frame held for a set time (about 5 seconds a case, 6 for the setup); the player's own controls let people pause on a case. With `ffmpeg`, give each image its own `-loop 1 -t <seconds>` input and join them with the `concat` filter: the concat demuxer's `duration` lines cut the first image short.
- **Shape it like the screen people use.** Record in the aspect ratio of the device the product is mainly used on: 16:9 for a product used on laptops (a 1440×810 viewport at 2x gives 2880×1620), portrait only when the ticket is about phones. Full-page shots of a long page come out tall and shrink to nothing in a player, so frame each case on the part that changes and keep every frame the same size.
- **Keep it sharp.** Capture each frame at 2x device pixels from a headless browser (Playwright's `deviceScaleFactor: 2`, a full-page or clipped `screenshot`), never from an agent tool's screenshot, which comes back downscaled and JPEG-compressed. Draw the captions and boxes into the page before the shot so they stay text, not scaled pixels, and encode at the frames' own size (`-crf 16 -tune stillimage`) without scaling down. Before sending it, pull a frame back out of the video and read small text at 100%.
- **Embed it as a player, and see it play.** Trackers render an attached video either as a block player or as an inline file chip, and the chip often won't play. A connector's "append this file inline" option tends to produce the chip, so write the block media node yourself, copying one from a ticket whose video already plays. Then have someone signed in open the ticket and press play before it goes to review: a successful upload says nothing about playback.

## Tools

Use whatever the project already has: a browser tool if one is connected, the project's own screenshot or visual-regression setup, a simulator, or a dev server plus a manual look. Do not install a new visual testing framework to satisfy this skill; the point is to look at the screen, not to build an apparatus for looking at screens.

If nothing is available and you genuinely cannot see the UI, say that plainly and let the user decide. A confident "looks good" from something that never rendered the page is the exact failure this skill exists to prevent.

## Gate checklist

Do not report a UI change verified until every box is ticked:

- [ ] Every surface the diff reaches is listed, including other consumers of shared components.
- [ ] The app was signed in through the project's dev-only credential, not someone's password; where it has none, the guarded path was proposed, and the user signed in only until it exists.
- [ ] When the work spans several branches or pull requests, the list covers every screen any of them changes, not only the one being worked on now.
- [ ] If a design exists, the state matrix is written from it, covering every switch in both positions, every layout-changing option, every role, empty/one/many, and every drawer and dialog.
- [ ] Every drawer and dialog was opened and filled in: empty, one item picked, several picked, and editing an existing item.
- [ ] The app was put in every state of the matrix and compared to the design section by section, not only the state you happened to land in.
- [ ] Every new or changed component was measured against its siblings on the same screen (title, subtitle, field labels, spacing).
- [ ] Every pointer to another screen ("managed in X", a read-only value with a link) was followed: the destination has the field, it saves, the first screen shows the new value without a reload, and the destination matches the design's version. Every read-only value has a screen that edits it, or the report names it as a bug.
- [ ] Each finding is about structure or behaviour; cosmetic differences where the app has an existing pattern (titles, labels, casing, icons) follow the app.
- [ ] Loading, empty and error states were each seen.
- [ ] Each changed page was re-checked after switching the current tenant or workspace on it, with no reload.
- [ ] After each write, every other screen showing data derived from it (lists, counts, badges, pickers) was visited without a reload, including filtered ones it must not appear in.
- [ ] Records in states the new UI can't create (blank optional fields, old links, pre-migration defaults) were used next to the new actions.
- [ ] Archived, deactivated and soft-deleted records were checked out of every count, list and picker.
- [ ] A record linked to another tenant's records was viewed from this tenant: no raw ids, nothing of theirs editable.
- [ ] Each interaction was done twice in a row (search and pick twice; add, remove, add).
- [ ] Every editable field was cleared and saved, and saved with an invalid value; every confirmation's words were checked against what actually happened, and every alert read for plain wording.
- [ ] In each section with Save and Discard, a field change, a picked file and a removed file were each discarded, and the saved record was unchanged after a reload.
- [ ] Each create form was submitted for every option that changes it, and the new record's landing state (on or off, sections shown) was compared with the design.
- [ ] Every button and link the change adds or retargets was followed from each entry point, after the page finished loading: it lands where the thing it names can be done, with no hunting, scrolling or reading first.
- [ ] Signed-in state was checked on every surface that shows it, after signing in from each entry point.
- [ ] A list or page was filled past the viewport, and a record created fresh through the UI was taken through its whole flow.
- [ ] Every reported layout defect was traced through its ancestors in code and reproduced at the content size the report shows, before it was fixed or left open.
- [ ] Narrow viewport, the other theme and a keyboard pass were done, or the report says why not.
- [ ] Every UI fix was seen fixed in a browser before it was reported done or anyone was told it is fixed, internal admin pages included (signed in through a dev-only credential, as in Step 2), not only covered by specs.
- [ ] The report lists each state checked, each finding with the state that produces it, and what was not checked.
- [ ] After a QA pass on shipped work, no code changed until the user agreed which findings are bugs, which are questions, and which go in a hotfix versus a ticket.
- [ ] Before review, the ticket's description ends with a How to test section (PR links, setup, numbered cases, expected results) and the walkthrough: a short MP4, not a GIF, that opens with the setup, captions each case with its state and expected result, and boxes and labels what to look at.
- [ ] The How to test setup, on the ticket and the pull request, is the team's usual local environment, with no port, worktree or server entry from your own session.
- [ ] The walkthrough is in the product's main device aspect ratio (16:9 for a laptop product, portrait only for a phone ticket), every frame the same size.
- [ ] The walkthrough's frames were captured at 2x in a headless browser, not from a downscaled tool screenshot, encoded at their own size, and a frame pulled from the video reads sharp at 100%.
- [ ] The walkthrough is embedded as a block player, not an inline file chip, and was seen playing on the ticket.
