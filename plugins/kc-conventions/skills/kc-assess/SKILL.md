---
name: kc-assess
description: Use at the start of a task, before building a fix: claims check, reproduce the failure first, trace a "reverted" or "stopped" report, list every reader of the broken value, compare a changed look with its reference.
---

# Assess a task

Step 1 of the working agreement's "Order of work on a task". Do this before any code, then present the cause and the fix with the rules the fix follows.

## Procedure

1. **Check the task is not already someone else's.** Who its tracker has it assigned to, and the pull requests that already name it: kc-gates' `task-claims.sh <key> --repo <owner/name>`, once per repository the task may touch. When it is assigned to someone else or a change for it is open, stop and ask whether to build, review that change, or leave it. A cleanup that deletes files (finished jobs, unused flags, scripts) also passes `--deleting <path>` from a local checkout: it lists who added each file, and only the `mine` ones are deleted unless the requester says otherwise; the `NOT YOURS` ones are listed for their authors.
2. **Read the issue and everything it links** (recordings, designs, logs), then find the cause.
3. **Reproduce the failure first, the way the reporter met it** (their entry point, renderer or runtime and version, environment, real-shaped data); a copy of one layer (a template rendered alone, another browser version, a fixture) is not a reproduction. Read what the failing run records (the request that failed and its status, the log line, the stack trace) before reading code to explain it. A cause reasoned from code alone is a guess until the failing run shows it. The proposal names that evidence for each problem on a `Reproduced:` line (the screenshot, the failing request, the log line), or says `Not reproduced: <why>`; the box below is required in every cause-and-fix proposal, and the person's approval of the proposal comes before any build.
4. **Trace a "changed, regressed, reverted or stopped" report from what is running back to the source** before any theory: which build or version is live, whether it contains the change, and what last touched that code (`git log` on the file).
5. **Before proposing anything new, list how the codebase already does the same job**, with paths, searching by the job ("where stored formatted text is shown") and not by the mechanism you planned (a sanitizer library). A new unit says why none of them fits.
6. **Answer what you can before asking.** Read the code, its history (`git log -S <text>` finds the change that made a field required), the change that made it so and the task's links; ask only what is left. The question stands on its own: the thing in plain words (not the name of a screen the person never saw), what you found, the options with their evidence and your pick. Cases: a reviewer asked why a field is required when the commit that made it so was one `git log -S` away; a question naming an internal screen its reader never opened. A result that differs from what the person entered, or from what the task asks, is a bug, never a question: reproduce it and fix it, and ask only about a call that is theirs (a value that comes back changed after saving, a total unlike the one the price rule gives, a field showing another record's value). A question from the person gets its answer and no edit (kc-gates' reply check flags one); if it reads as doubt, ask whether to change it.
7. **Keep what people have long relied on** (a required field, a default, a layout) unless the task asks to change it. A change they would notice is a product call: put it to the person with what you found, never fold it in as a tidy-up.
8. **When the cause is a design that lets this kind of bug happen** (state set after the first render, a cache filled on first use, a value read before anything writes it), present the fix for this case and the change to the design side by side, and say which to ship now. The narrow fix alone leaves the next case to the same design.
9. **List every reader of the broken value or input** (a grep for the field or call): what each does with the bad case and whether the fix covers it, so review confirms the list instead of finding the rest.
10. **For each reader a person reaches, state the state they are in** when the bad case gets there (which options are picked, what is shown and hidden), read from the conditions that show or hide each part or walked in the app. Check the fix against what they see in that state: a fix that blocks an action or reports an error works only if that error shows in that state.
11. **When the fix changes how something looks or reads** and people already hold it up against a reference (an official form or template, a standard symbol, the layout a trade uses), open that reference first and show the person a picture of the change on a real case beside it before building it out. A look judged wrong at first sight costs a sketch to learn from, or a finished change.
12. **Stop for approval** when the fix makes a call that is the person's (see "Ask before assuming") or they asked to see it first. Otherwise state the cause and the fix in a few lines. A change that stores something new, adds a unit or moves behaviour or data gets its shape written and approved first (`kc-conventions:kc-shape-the-change`); then build.

## Examples

Step 1 (assess):

- A fix built, tested and walked in the app for a task assigned to a teammate who already had a pull request open for it.
- A fix that guarded the one total that broke on a missing price, while a second reader of the same price was left for review to find.
- A null check added to the page that crashed but not to the export that reads the same field.
- A "save and continue" link that crashed on a cleared delivery date, fixed by validating the form first, when the link only shows for gift bundles and bundles hide the date field: the link did nothing and showed nothing.
- An empty-cart message added to a page that a filter had already emptied, so it never showed.
- A retry button for a failed upload placed in a panel that collapses on failure.
- A shop's public order page that sent signed-out customers to the sign-in screen, traced through the page's code and a backend test, when the browser's network log showed at once that the first request to answer 401 was an admin-only lookup.
- A job that failed overnight, explained from its code when its log named the row it stopped on.
- A shared state filled only after the first render: the patch held the page back until it was filled and said nothing of filling it before the first render, which would stop the next page that reads it early.
- "Reverted" reports: a layout "reverted" on a staging site, found to be the live build holding a later branch's stale copy of the file; a job that "stopped", found to be running an older release; prices that "changed overnight", found to follow a deploy.

Steps 5 to 7 (existing code, asking, long-held behaviour):

- A new sanitizing renderer built for product notes, when every stored rich-text field in the shop already shows through one viewer component.
- A question to a reviewer, "why is this field required?", when `git log -S` on the field names the commit and its reason.
- A "price" screen named in a question to someone who only knows the checkout page.
- A required customer phone number made optional while fixing its error message, a default currency dropped, a list's column order changed: each is a product call for the person, not a tidy-up.

Order of work, in general (an expensive check whose result later work throws away runs once, on the finished work):

- A small two-file fix reviewed by every gate and walked in the app while uncommitted, then reviewed and walked again at hand-off, so review and QA took two-thirds of the time.
- Screenshots for a pull request taken before the copy was final.
- A performance profile taken halfway through the refactor it was meant to judge.

Step 2 (build): say in one line what kind of mistake a fix is for, and check everything the fix adds against it, since a fix often repeats its own mistake in the code written for it. Cases: a lookup per row added while removing another; one hard-coded time zone taken out and a hard-coded locale put in; a line drawn where things usually are replaced by icons drawn where things usually are.

## Overlap by code, not only by task key

Work overlaps by the code it changes, not only by its task key. Besides the tracker's assignee and the pull requests that name the task, look for open pull requests, by anyone, that change the files the fix will change, and for commits to them on the default branch since the failure was reproduced: `task-claims.sh <key> --repo <owner/name> --path <file>... --since <commit>`, with `--since` run in a checkout. When one is open, stop and ask whether to build, review that change, or leave it. Example: a fix built for a task nobody else held, in a shared component that another open pull request, for a different task, had already changed.

Run the same check again right before marking the pull request ready, with the commit the work started from: the default branch moves while the work is open. When it already changed or fixed that code, or another open pull request now changes it, ask the person instead of handing off. Example: a pull request ready to hand off after another one merged, rewrote the same component and fixed the bug another way.

## Gate checklist

- [ ] §AS1 Reproduced: <reporter's entry point, environment, data, what was seen>, or Not reproduced: <why>, in every cause-and-fix proposal; a copy of one layer (a template rendered alone, another browser version, a fixture) does not count. (N/A: the task reports no problem)
