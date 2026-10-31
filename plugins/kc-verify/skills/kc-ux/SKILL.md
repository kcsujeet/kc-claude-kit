---
name: kc-ux
description: Verify a person can use a change before calling it done. Trigger on "is this easy to use", "check the UX", "check the flow", "walk it like a user", "would a user get this", or before reporting complete a change to something a person does (a form, a flow, a link, a setting, a confirmation). Walks the change as someone new to the product, then the flows around it, with realistic data, and reports every place a person has to stop and work something out. For how it looks, use kc-ui.
---

# Verifying a change is usable

A screen can match its design in every state and still leave people stuck: a link that opens the wrong part of a page, a step in an order nobody expects, a Discard that already saved, a confirmation whose words don't match what it does. `kc-verify:kc-ui` checks that the change looks right. This checks that a person can use it. A change a person both sees and uses gets both.

## Hard rules

- **Nobody should have to learn the product to use it.** Use the change as a person who has never seen the product and wants to get something done, not as the person who built it. Anything that makes them stop and work it out (hunt, scroll, guess, read instructions, remember another screen) is a usability finding, even when every element works as built: people who have to learn a product to use it give up on it (Step 2).
- **A moved field is two screens.** When a screen stops editing a value and points elsewhere ("managed in product settings", a read-only value with a link), follow the pointer: open the destination, confirm the field is there and saves, and that the first screen shows the new value without a reload. Compare the destination with the design's version of it too. A pointer to a screen that cannot edit the value is a bug, and so is a read-only value that no screen edits.
- **The evidence rules are kc-ui's.** See it in the running app, never a stand-in; use realistic data; keep the failure; say what you could not check. Those hard rules in `kc-verify:kc-ui` apply here unchanged.

## Workflow

### Step 1 — set up as kc-ui does

List the surfaces the change reaches and get real data and a dev-only sign-in in front of them: `kc-verify:kc-ui` Steps 1 and 2.

### Step 2 — walk it as someone new to the product

For each changed screen, name the goal it serves (choose a plan, add a storefront, fix a failed order) and reach it from each entry point the way a person who has never seen the product would. Note every place you had to stop and work something out, even where everything works as built:

- an action that lands away from what it names: "Choose a plan" opening the top of a page with the plans out of sight, "Add a storefront" opening the list instead of the form;
- a screen that doesn't show what it is for or what to do next: an empty list with no way to add the first item, a success message with nowhere to go;
- a control placed where nobody would look for it, or a step that needs something from another screen the person has to remember, or doesn't have yet;
- an error that says what went wrong but not what to do, or a dead end with no way back or forward.

Look once the page has finished loading, since content that arrives late (a signed-in header, a banner) can push what matters out of view. A flow people know from other products keeps the order they know (`kc-conventions:kc-simplicity` §P17).

### Step 3 — walk the flows around the change

Each screen can be usable on its own while the path through it breaks. QA by a person finds these first, because a person moves between screens and keeps going. Walk them on every surface the change reaches:

- **Switch context mid-page.** Change the current tenant, workspace or account while on each changed page. Every panel follows, with no reload; a record that belongs to the previous context shows a clear not-found, not a blank or half-loaded page.
- **Go where the write shows up.** After each create, edit, archive or delete, visit every other screen that shows something derived from it (a list, a count, a badge, a picker on another page) without reloading, and check it changed, and that it didn't appear where its filters exclude it.
- **Use the records real data holds.** Include records the new screens can no longer create: blank optional fields, old links, defaults from before a migration. Then try the new actions next to them (create one more, link, delete).
- **Keep archived records around.** Archive, deactivate or soft-delete one of each kind the screen counts or lists, then check every count, list and picker leaves it out unless it says otherwise.
- **Cross the tenant line.** View a record linked to records in another tenant or workspace from this one: the others show by name or not at all, never as raw ids, and can't be changed from here.
- **Do each interaction twice.** Search, pick, search again, pick again; add, remove, add; open, close, reopen. State that survives one pass often breaks on the second.
- **Clear every field you can edit, and save; then enter an invalid value and save.** Expect a message on the field, or a sensible default, never a generic error.
- **Discard every kind of change.** In each section with Save and Discard, change a field, pick a file and remove a file, then Discard. The saved record is unchanged after a reload, with no request sent before Save.
- **Read every confirmation against what happens.** After confirming, check the result matches the words: "remove" that deletes, or "delete" that only unlinks, is a finding. Read alerts and helper text the same way, as the user would: plain words, no internal terms, no stray spaces around an inserted value.
- **See signed-in state everywhere it shows.** Sign in from each entry point, then check every surface that shows who is signed in, and what a signed-in person should and shouldn't see.
- **Start from a fresh record.** Create the thing through the UI and take it through the whole flow it exists for. When a result looks wrong, check the inputs before calling it a bug: a total of zero explains a skipped payment.
- **Keyboard only**, for anything interactive: is focus visible, and can you reach every control?

### Step 4 — report

Report as `kc-verify:kc-ui` Step 6 does: one line per surface, each finding with the state that produces it and the steps from a fresh page load, and what was not checked. A QA pass on shipped work ends at the report there too. For someone who doesn't know the change, add the walkthrough of kc-ui Step 6b.

## Gate checklist

Do not report a change usable until every box is ticked:

- [ ] Each changed screen was walked toward its goal from each entry point as someone new to the product, after the page finished loading, and every place that made the person stop and work something out (an action landing away from what it names, no clear next step, a control nobody would find, a dead end, an error with no way forward) is reported as a finding.
- [ ] Every pointer to another screen ("managed in X", a read-only value with a link) was followed: the destination has the field, it saves, the first screen shows the new value without a reload, and the destination matches the design's version. Every read-only value has a screen that edits it, or the report names it as a bug.
- [ ] Each changed page was re-checked after switching the current tenant or workspace on it, with no reload.
- [ ] After each write, every other screen showing data derived from it (lists, counts, badges, pickers) was visited without a reload, including filtered ones it must not appear in.
- [ ] Records in states the new UI can't create (blank optional fields, old links, pre-migration defaults) were used next to the new actions.
- [ ] Archived, deactivated and soft-deleted records were checked out of every count, list and picker.
- [ ] A record linked to another tenant's records was viewed from this tenant: no raw ids, nothing of theirs editable.
- [ ] Each interaction was done twice in a row (search and pick twice; add, remove, add).
- [ ] Every editable field was cleared and saved, and saved with an invalid value; every confirmation's words were checked against what actually happened, and every alert read for plain wording.
- [ ] In each section with Save and Discard, a field change, a picked file and a removed file were each discarded, and the saved record was unchanged after a reload.
- [ ] Signed-in state was checked on every surface that shows it, after signing in from each entry point.
- [ ] A record created fresh through the UI was taken through the whole flow it exists for.
- [ ] A keyboard-only pass reached every control the change adds, with focus visible, or the report says why not.
