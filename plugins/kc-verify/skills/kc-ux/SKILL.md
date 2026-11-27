---
name: kc-ux
description: "Verify a person can use a change before calling it done: walk it as a newcomer. Trigger on \"is this easy to use\", \"check the UX\", \"check the flow\", \"walk it like a user\", \"would a user get this\", or before reporting complete a form, flow, link, setting or confirmation. Looks are kc-ui."
---

# Verifying a change is usable

A screen can match its design in every state and still leave people stuck. `kc-verify:kc-ui` checks that the change looks right; this checks that a person can use it. A change a person both sees and uses gets both. The evidence rules are kc-ui's (see it in the running app, realistic data, keep the failure, say what you could not check). Full wording: `references/detail.md`.

## Steps

1. Set up as kc-ui does: list the surfaces the change reaches and get real data and a dev-only sign-in in front of them (`kc-verify:kc-ui` Steps 1 and 2).
2. For each changed screen name the goal it serves and reach it from each entry point as someone who has never seen the product, after the page finished loading. Note every place you had to stop and work something out, even where everything works as built: an action that lands away from what it names, no clear next step, a control nobody would find, a dead end, an error with no way forward. A flow people know keeps its order (`kc-conventions:kc-simplicity` §P17).
3. A moved field is two screens: follow every pointer ("managed in X", a read-only value with a link), confirm the destination has the field and saves, the first screen shows the new value without a reload, and compare the destination with the design.
4. Switch the tenant, workspace or account mid-page: every panel follows with no reload.
5. After each write visit every other screen showing something derived from it, without reloading, including filtered ones it must not appear in.
6. Use records the new UI cannot create (blank optional fields, old links, pre-migration defaults) next to the new actions.
7. Archive, deactivate or soft-delete one record of each kind and check every count, list and picker leaves it out.
8. View a record linked to another tenant's records: no raw ids, nothing of theirs editable.
9. Do each interaction twice in a row (search and pick twice; add, remove, add).
10. Clear every editable field and save; save an invalid value. Expect a message on the field or a sensible default, never a generic error.
11. In each section with Save and Discard, change a field, pick a file and remove a file, then Discard: the saved record is unchanged after a reload and no request went before Save.
12. Read every confirmation, alert and helper text against what happens: plain words, no internal terms.
13. Check signed-in state on every surface that shows it, after signing in from each entry point.
14. Create a fresh record through the UI and take it through the whole flow it exists for; check inputs before calling a result a bug.
15. Use the keyboard alone: focus visible, every control reachable.
16. Report as `kc-verify:kc-ui` Step 6: one line per surface, each finding with its state and the steps from a fresh page load, and what was not checked; add the walkthrough of kc-ui Step 6b for someone who does not know the change.

## Gate checklist

- [ ] Do not report a change usable until every box is ticked:

- [ ] §UX1 Each changed screen was walked toward its goal from each entry point as someone new, after load; every stop-and-work-it-out place is reported as a finding.
- [ ] §UX2 Every pointer to another screen was followed: the destination has the field, saves, the first screen updates without reload, and matches the design; a read-only value with no editing screen is a bug.
- [ ] §UX3 Each changed page was re-checked after switching the tenant or workspace on it, with no reload.
- [ ] §UX4 After each write, every other screen showing derived data (lists, counts, badges, pickers) was visited without a reload, including filtered ones it must not appear in.
- [ ] §UX5 Records in states the new UI cannot create were used next to the new actions.
- [ ] §UX6 Archived, deactivated and soft-deleted records were checked out of every count, list and picker.
- [ ] §UX7 A record linked to another tenant's records was viewed from this tenant: no raw ids, nothing of theirs editable.
- [ ] §UX8 Each interaction was done twice in a row.
- [ ] §UX9 Every editable field was cleared and saved, and saved invalid; every confirmation's words and every alert were checked against what happened.
- [ ] §UX10 In each Save and Discard section a field change, a picked file and a removed file were each discarded; the saved record was unchanged after a reload.
- [ ] §UX11 Signed-in state was checked on every surface that shows it, after signing in from each entry point.
- [ ] §UX12 A record created fresh through the UI was taken through the whole flow it exists for.
- [ ] §UX13 A keyboard-only pass reached every control the change adds, with focus visible, or the report says why not.
