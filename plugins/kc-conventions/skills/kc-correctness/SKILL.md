---
name: kc-correctness
description: "Correctness conventions for source files in TypeScript, JavaScript, Ruby, Python, Swift, Go, Java, Kotlin, PHP, C# and Rust: logic errors (off-by-one, wrong operator, inverted condition, stale state or closure, wrong dependency array), unhandled edge cases (empty, null, zero, boundary values, timezone), data that does not match its declared type at a boundary, and regressions of bugs the repo already fixed. Use when writing or reviewing a change to conditions, loops, state, hooks or data crossing a boundary, or when hunting for bugs in a diff."
user-invocable: false
paths:
  - "**/*.{ts,tsx,js,jsx,mjs,cjs,rb,py,swift,go,java,kt,php,cs,rs}"
---

# Correctness

## Contents

- Rules
- Review checklist
- Review detail
  - §B1. Logic
  - §B2. Edge cases
  - §B3. Data shape
  - §B4. Regression
  - §B5. Every submitted value lands as intended
  - §B6. A new reference does not close a load cycle
  - §B7. A count uses the same filter as its list
  - §B8. Every use of a changed thing still works
  - §B9. A claim about a value comes from all its writers
  - §B10. A fix covers its whole class
  - §B11. A client mirror of a server calculation reads the server's inputs
  - §B12. A list shows only what the viewer can open
  - §B13. When one becomes many, nothing picks "the" one
  - §B14. A guard against a delete counts only what the delete would harm
  - §B15. A change moves only the states it is for
  - §B16. A stored value is read in every state it can reach
  - §B17. A new kind of actor passes the guards written for the old one
  - §B18. A switch turned off stops every reader
- Sweeps

## Rules

Code that reads well and is wrong is still wrong. Walk every change for the bugs a reader skims past.

- Consider the empty, null, zero and boundary input on every path you add or change, not only the value the feature was built for. When the code finds, parses or rewrites content people write (rich text, an email footer or signature, a template, a pasted address), first list every shape that content can take (plain text, line breaks, several blocks, inline formatting or a link against other words, images, tables, blank lines, empty, none at all) and run each one through every path that moves it: insert, replace, remove, and back again.
- Check every operator and condition for an off-by-one or an inversion: `<` against `<=`, `&&` against `||`, a negation that flips the meaning.
- Keep dependency arrays and closures current: an effect, memo, callback or handler reads the latest value of everything it uses.
- Do not let a cast hide a real type mismatch. When data crossing a boundary (an API response, props, storage) does not match its declared type, fix the type or parse the value. Records older code saved are §B16's "written by an older version" state; check them there. When a unit is reused from a new caller, compare what each caller does to the data before handing it over: a default or normalization the old caller applied and the new one doesn't is a mismatch the type won't show.
- Before changing code, check the repo's history for a bug already fixed there (the changelog, dev logs, `git log -S <symbol>`), so the change does not bring it back.
- Trace every submitted field from its input, through any transform and the request payload, to what the receiving end does with it, for each state the user can leave it in: set, changed, cleared, left alone, invalid. Each state must arrive in a shape the receiver accepts and have the effect the user expects.
- When a change adds a reference from one module or class to another, follow the references back and check that they do not close a loop. Inside a loop, code that runs when a module is defined (a subclass copying its parent's fields, a registration, class-level configuration) can run before what it needs exists, and fail with no error. Use the lazy form of the reference when the library has one.
- A count, total or summary of a list uses the same filter as the list: what the list hides (archived, deleted, inactive items) the count leaves out too.
- When a change alters a function, hook, component, helper, service, field, prop, route or column, or what a value means (a route parameter now holds a different kind of id, a setting now applies per item), find every use of it, in files the change doesn't touch and in a sibling repo that calls it, and check each one still works. The damage usually lands in a file that uses the changed thing, not beside the change.
- A bug fix covers every instance of its cause, not only the one that was reported. Once the cause is known, grep the repo, tests included, for the same pattern (the same query, call or assumption) and fix or list each hit; code written alongside the original, on the same day or in a sibling branch, is the first place to look.
- Before saying what a value holds ("this column is always blank", the cause of a flaky test), find every writer of it: the class body, every module or concern it includes and their callbacks, factories and seed code. A claim read off the visible class alone is a guess.
- When a change turns one into many (a shop's store becomes stores), every accessor that still picks "the" one (the first, the lowest id, a "default") is a leftover unless a stated product rule chooses it. Each reader uses the specific record it already has (the order's store, the one in the URL), and the accessor and every fallback to it go.
- A guard that refuses a delete or removal ("has orders", "has items") counts only the related records the delete would harm: completed payments, live work, records people still see. Abandoned, expired, failed, archived or deleted ones go with it, or are cleaned up, and the message says in plain words what blocks it and what to do instead.
- A change to a condition, fallback, default or validation moves only the states it is for. List every state that reaches the changed line, saved and unsaved values, empty ones and each option of a choice, when each input arrives (still loading, loaded after a first pass, retried) and each path that reaches it, with what each does before and after; any other state whose result moves is a new bug. A change a reviewer suggests is code too: walk it the same way before suggesting it, across every content shape when it handles what people write, and run it on a scratch copy with a test for the break it fixes before asking for it; one that can't be run is asked for as an outcome and a test, not as code.
- A value written now and read later (a cookie, a cache or storage entry, a URL parameter, a file, a row, a flag) is read in every state it can be in by then: missing, stale, written by an older version of the code, someone else's, half-written, or written by two writers at once (which copy wins, and by what stamp). List those states, and the events between the write and the read (a reload, a sign-out or expiry, back and forward, a retry, a restart, a second tab, an update or deploy), and give each one a path that handles it.

Detection criteria and per-box review failure modes live in the `## Review checklist` of the `kc-correctness` skill (`kc-conventions:kc-correctness`), with the detail under its `## Review detail`. These rules are the statement of the convention; that checklist is how a diff gets graded against it.

## Review checklist

The correctness gate agent ticks every box against the diff. A box is FAIL if any matching construct violates the rule; the gate is FAIL if any box is FAIL. Each box states its own N/A condition.

- [ ] §B1 Logic: no off-by-one, wrong operator, inverted condition, stale state or closure (an effect, callback or handler reading a value captured before it changed), or wrong dependency array (a value the body reads is missing, or a listed value changes every render). (N/A: the diff adds or changes no condition, loop, index or range arithmetic, state update, closure, or dependency array)
- [ ] §B2 Edge cases: every added or changed path handles empty collections, null/undefined, zero, and boundary values (first, last, exactly at a limit), every path that finds, parses or rewrites content people write was run with every shape on the §B2 list through insert, replace, remove and back, and every date or time the diff formats or parses uses the configured timezone rather than the machine's. (N/A: the diff changes no path that takes input, and formats or parses no date or time)
- [ ] §B3 Data shape: values crossing a boundary (an API response, props, storage, a URL or form value) match their declared type at runtime. A cast or `any` that lets a real mismatch through is a finding here; the syntax of the escape hatch itself is clarity §C17. When the diff passes data to an existing unit from a new caller, the evidence names the unit's other callers and what each does to the data first (defaults, normalization, parsing); a step the new caller skips FAILS. (N/A: no value crosses a boundary and no existing unit gets a new caller in the diff)
- [ ] §B4 Regression: the diff does not reintroduce a bug the repo already fixed. The changelog, the dev logs (when the repo keeps them) and `git log -S <symbol>` were checked for every touched symbol, and the receipt names what was searched. (N/A: the diff only adds new files and touches no existing symbol)
- [ ] §B5 Every submitted value lands as intended: for each field the diff sends (a form, a request built from user input), the evidence traces it from the input, through the transform and the payload, to the receiver's handling (its parsing, the keys it accepts, its validations), for each state the user can leave it in: set, changed, cleared, left alone, invalid. Each state arrives in a shape the receiver accepts and has the effect the user expects. A field with no trace FAILS by default. The receiving code was read (in this repo or the backend's), and run when its effect is not plain from the code. (N/A: the diff sends no user-entered value)
- [ ] §B6 A new reference does not close a load cycle: for each reference the diff adds from one module or class to another (an import, a require, a constant, a serializer or association that names another class), the evidence follows that class's own references back and states whether they lead to the first one. When they close a loop and any module in it does work at definition time (inheritance that copies the parent's declarations, a registry, class-level configuration, a decorator), the box FAILS unless the reference is lazy (a block, a proc, a string name or a deferred import that resolves on first use). A cycle with no definition-time work is clarity §C14. (N/A: the diff adds no reference between modules)
- [ ] §B7 A count uses the same filter as its list: every count, total or summary the diff adds or changes is computed with the same conditions as the list it summarises (soft-deleted, archived, inactive, other-tenant rows excluded alike), and the evidence names both queries. (N/A: the diff adds or changes no count, total or summary)
- [ ] §B8 Every use of a changed thing still works: each use the dispatch's uses list holds (kc-gates' `trace-uses.sh`: every use of each function, hook, component, helper, service, field, prop, route or column the diff changes, files the diff doesn't touch included) gets one verdict, breaks, behaviour changes or fine, with the reason, and the receipt says `uses: <n> listed, <n> judged`, the counts equal. A use that breaks, or whose behaviour changes in a way its caller doesn't expect, FAILS, citing the use's `file:line`; a listed test that failed is a finding too. With no list given, the evidence lists every reader of what changed, found by grep, the same way. A count that differs from the list FAILS like a sampled sweep. (N/A: the diff changes nothing another file or repo uses)
- [ ] §B9 A claim about a value's contents, in a comment, a commit message or a test's reasoning ("positions are blank", "this is the only writer"), was checked against every writer: the class body, each included module or concern and its callbacks, factories and seeds. One that read only the visible class body FAILS. (N/A: the diff states nothing about what a value holds)
- [ ] §B10 A fix covers its whole class: when the diff fixes a bug, the evidence names its cause as a searchable pattern, the grep that was run for it across code and tests, and a verdict per hit (fixed here, safe and why, or listed for follow-up). A fix with no such sweep FAILS. (N/A: the diff fixes no bug)
- [ ] §B11 A client that mirrors a server calculation (a price, a total, a balance it shows before the server charges it) reads each input from the record the server reads, and the evidence names the server code and the client read side by side. An input read from a different record that holds the same value only some of the time (a copy, a legacy column, a record that can be deleted) FAILS. (N/A: the diff mirrors no server calculation)
- [ ] §B12 A list shows only what the viewer can open: when each listed item has its own access check (its page turns some viewers away), the list applies the same check, server-side, and the evidence names both. A list gated only as a whole, whose items then refuse the viewer, FAILS. (N/A: no list of items with their own access check)
- [ ] §B13 Nothing picks "the" one after one becomes many: when the diff, or the feature it continues, turns a one-to-one into a one-to-many, every accessor that returns a single record from the many (`first`, lowest id, `default_*`, a single-record association with an order) and every fallback to it (`order.store || shop.store`) is listed with its readers. Each FAILS unless a product rule says how that record is chosen, and the finding names the specific record each reader should use instead. (N/A: no cardinality change in scope)
- [ ] §B14 A guard that refuses a delete or removal counts only the related records the delete would harm, and the evidence lists each status or state the related record can have with a verdict (blocks, goes with it). A guard that counts every related row, so an abandoned, expired, failed or archived one blocks the delete, FAILS, as does a message that names an internal term or no way forward. (N/A: no delete guard in scope)
- [ ] §B15 A change moves only the states it is for: for each changed condition, fallback, default or validation, and for each one a finding proposes, the evidence lists every state that reaches the line (each value its inputs can hold: saved and unsaved, empty, each option of a choice, each existing record; when each input arrives: before and after data loads, a first pass and a later one, a retry; and each path that reaches the line, with the checks it runs first) with the result before and after. A state outside the change's purpose whose result moves FAILS; a proposed fix that moves one is rewritten or dropped before it is reported. A proposed fix that changes behaviour is run, not only read: applied to a scratch copy with a test for the break it fixes, then the suite and each listed state run, and the evidence says `ran:` with the result; one that can't be run is asked for as the outcome and its test, not as code. (N/A: no condition, fallback, default or validation changed or proposed)
- [ ] §B16 A stored value is read in every state it can reach: for each value the diff writes for a later step or reads from an earlier one (a cookie, a cache or storage entry, a URL or query parameter, a file, a row, a flag), the evidence is a table with one row per state or event and the `file:line` that handles it, or "unhandled". The states are what it can be when read (missing, stale, written by an older version, another user's or session's, half-written, written by two writers at once, with which copy wins and by what stamp); the events are what can happen between the write and the read (reload, sign-out or expiry, back and forward, retry, restart, a second tab, an update or deploy). A row with no handler FAILS. A submitted form value is §B5. (N/A: the diff writes or reads no value that waits for a later step)
- [ ] §B17 A new kind of actor passes the guards written for the old one: when the diff lets a new kind of record own or perform an action another kind did (a store sending reminders only a person sent, a service account placing orders a customer placed, a gift card paying for what a customer's card paid), every guard, filter and early return on that action's paths keyed on the old kind (its active status, its connection, its ownership, its plan, a join through its id) is listed, in jobs, schedulers and services as well as the code the diff touches, each with a verdict: holds for the new kind, needs the new kind's own check, or doesn't apply. A guard that drops, refuses or stalls the new kind's work FAILS, citing its `file:line`. (N/A: no action gains a new kind of owner or performer)
- [ ] §B18 A switch turned off stops every reader: when the diff puts a feature or its data behind a switch (a feature flag, a permission, a plan, a setting), the evidence lists every reader of what is switched (each serializer and every subclass that declares the field again, background jobs and work already queued, scheduled steps, outgoing mail or webhooks, signed-out and public pages, exports and links built from it), each with the line that checks the switch or why it needn't. A reader that still uses the switched data or behaviour while the switch is off FAILS. (N/A: the diff adds or widens no switch)

**Point, do not double-report.** A removed export or a changed shared prop shape is structure §S10. A cast asserting a type the value does not have, as syntax, is clarity §C17. Duplicated markup, dead imports, or props threaded through and never read after a refactor are simplicity §P9. A locale formatter with no explicit time zone is datetime §D7. When a bug and one of those boxes describe the same line, report it once, under the closer fit, and name the other box in the evidence.

## Review detail

Bug rules for the diff under review. Covers eight independent failure modes: logic that computes the wrong thing, inputs the code does not handle, data that is not the shape its type claims, a fix the repo already made being undone, a submitted value that does not have the effect the user meant, a new reference that closes a load cycle, a count that disagrees with its list, a value whose readers still expect its old meaning, and code that still picks "the" one record after one became many.

**Every finding is verified before it is reported.** Open the actual file at the actual line at the head SHA (`git show <sha>:<path>`) and confirm the bug exists there; a finding from a hunk alone, or from another agent's summary, is not verified. **A claim about library or platform behavior** (a date library, a recurrence library, React, `Intl`, a CSS framework, a remote API) **cites the documentation fetched or the installed source read this session**, inline in the finding. Cached knowledge drifts between versions.

### §B1. Logic

Walk each changed condition, loop and state update, and ask what it computes, not what it was meant to compute:

- **Off-by-one:** `<` against `<=`, `length` against `length - 1`, an exclusive end treated as inclusive, a loop that skips the first or last item.
- **Wrong operator:** `&&` where `||` was meant, `=` or `==` where `===` was meant, `??` where `||` was meant (or the reverse, when `0` or `''` is a real value).
- **Inverted condition:** a negation that flips the branch, an early return guarding the wrong case.
- **Stale state or closure:** an effect, callback, timer or event handler that captured a value and keeps reading it after it changed; a state update computed from the previous render's value where the functional form was needed.
- **Wrong dependency array:** a value the body reads is missing, so the effect or memo runs against a stale value; or a listed value is a new object every render, so it runs every time.

### §B2. Edge cases

For each changed path, feed it the inputs the feature was not built around: an empty array or string, `null` and `undefined`, `0`, a negative number, the first and last item, a value exactly at a limit. A path that throws, renders nothing useful, or computes a wrong result for one of them is a finding.

**Content people write.** Code that finds, parses or rewrites what a person composed meets every shape they can compose, not the one in the ticket. Before reviewing it, list the shapes: plain text, line breaks inside one block, several blocks, inline formatting or a link set right against other words, images (beside text and on their own), tables, blank lines, empty, and none at all. Run each through every path that moves the content (insert it, replace it, remove it, replace it back) and check what is left. A shop's order email swapped one store's footer for another by finding the old footer by its words. Review checked the reported case each round (plain text, then line breaks, then bold next to a comma) and walked each fix only against that case, so a footer with a logo, a logo-only footer and a store with no footer all failed only in the fifth round: an image has no words to find, and a missing footer leaves nothing to replace. The list finds all of them in one pass. It also catches an address parser given a second line, a mention parser given a name inside a link, and a cleaner that strips markup from a pasted table. When each round finds a new shape the same code misses, the approach is the finding (`kc-code-review` §G5).

**Timezone.** When the app configures a time zone, a date formatted or parsed without it follows the machine's zone. `Intl.DateTimeFormat` without a `timeZone` option, or a string with no offset parsed by `new Date()`, is the common shape. Grep the repo for how it configures the zone before flagging, and cite it.

### §B3. Data shape

Check the declared type of every value that crosses a boundary against what actually arrives: the API contract, the props a caller passes, what storage returns, what a URL or form field holds (always a string). Drift between the contract and the type, an `as` cast that asserts the expected shape instead of checking it, and `any` carrying a wrong type through are findings here when the runtime value can differ from the type. State the mismatch: what the type says, what arrives, and where.

Records older code wrote can lack a key the current code always writes; that is §B16's "written by an older version" state, checked against the server's schema or a sample of real rows, not the type.

**A unit reused from a new caller.** A component, hook or function written for one caller often depends on a cleanup that caller does before handing data over (a default, a parse, a filter). A new caller that passes the raw response skips it, and the type, written for the cleaned data, doesn't say so. List the unit's callers and what each does to the data first; the new caller does the same, or the unit does it itself. Examples: a price breakdown built for a settings screen that fills missing prices, reused on a saved order whose older rows lack one, so the total came out as NaN; a date picker fed an ISO string where its first caller passed a `Date`; a list component reused on an endpoint that, unlike the first, returns archived rows.

### §B4. Regression

Do not trust the PR description for this box; check the history. For every symbol the diff changes, search the changelog, the repo's dev logs if it keeps them, and `git log -S <symbol> --oneline` for an earlier fix to the same code. When one exists, read it and confirm the diff does not undo it (a guard removed, a boundary rule reverted, a workaround deleted without the cause being fixed). The receipt names the sources searched and the commits found, or `no prior fix found` with the search stated.

### §B5. Every submitted value lands as intended

A schema that accepts the right inputs is half the job. What matters is what each value becomes by the time the receiver saves it, and whether that is what the user meant. Walk every field the change sends, in every state the user can leave it in (set, changed, cleared, left alone, invalid), through three steps:

1. **The transform.** What does the form or schema output? A helper can quietly turn `''`, `null` or unparseable text into `undefined`.
2. **The payload.** What goes over the wire? `JSON.stringify` drops `undefined` keys, and on a PATCH a missing key usually means "no change".
3. **The receiver.** What does the endpoint do with it? Read its parsing, the keys it accepts, and its validations and callbacks; `''` may become `null`, which a numeric validation then rejects.

Illustrations of values that fail along the way, not a complete list:

- Clearing a field sends nothing on a PATCH, so the old value silently stays.
- `''` or `null` fails a validation, so the save errors instead of clearing.
- A key the receiver does not accept is ignored.
- A number sent as a string, a date without its offset, or a `0` the receiver reads as "unset".

When the effect is not plain from the code, run it: call the receiver's parser and validation with each state and record what comes back. The tests follow the same states (testing §T7).

### §B6. A new reference does not close a load cycle

A reference between two modules is harmless until it closes a loop. Inside a loop, the language has to finish defining one module before it can define the next, so one of them is defined while something it depends on is still half-built. Most code tolerates that, because nothing is read until later. Code that does work at definition time does not:

- A subclass that copies its parent's declared fields, attributes or callbacks when it is defined gets whatever the parent had declared so far, which can be nothing.
- A registry or plugin list that a module adds itself to on load may be read before the module has loaded.
- Class-level configuration that reads another class's constants or settings may read them before they are set.

None of these raises an error. The module loads, the output is quietly missing fields, and the failure shows up only where that output is used. It can also depend on load order, so it can pass in development and tests and break in production, or the reverse.

**How to check.** For each new reference from A to B, open B and follow its references (and those of the classes it inherits from or includes) until they end or come back to A. Record the path. When they come back, look for definition-time work in every module on the path. If there is any, the reference must be lazy: most libraries accept a block, a proc, a string class name, or a deferred import that resolves on first use. When the fix is not plain, load the modules in the order production does (eager loading, a production build) and inspect the definition-time result directly: list the subclass's fields and compare them with the parent's.

Example: a shop's base serializer for catalog items declares a relationship to the translation serializer, and the translation serializer references the store serializer. A change adds a reference from the store serializer to the storefront serializer, which references the product serializer, a subclass of the catalog base. At boot, loading the catalog base pulls in that whole chain before the base has declared its fields, so the product serializer copies an empty list. Every product response then ships with no fields and no error, and every request test still passed, because each one checked only the status (testing §T8).


### §B7. A count uses the same filter as its list

A count shown beside a list is read as "how many of these there are". When the list hides archived or deleted rows and the count does not, the two disagree, and the count grows with every item ever archived. Compare the count's query with the list's: the same owner, the same soft-delete or archive condition, the same visibility rule. When the list's filter lives in a model method or scope, the count reuses it.

### §B8. Every use of a changed thing still works

A change is reviewed where it was made, and its damage lands where the changed thing is used: a function that now takes cents while a caller in an untouched file still passes dollars, a prop removed while another screen still passes it, a column renamed while a report still selects it. A reviewer who searches for those uses finds some; one handed the list finds all of them, so the caller gives the gate `trace-uses.sh`'s list and the gate judges each item. A change that makes a value mean something new (a storefront's page now takes the storefront's own id where it used to take the shop's, a field that held one id now holds another kind) updates the code it is working on, while every other reader keeps sending the value where the old meaning is expected. Nothing fails loudly: the lookup finds nothing, and the screen shows its empty or signed-out state. Grep every reader of the value, including ones the diff never touched, and confirm each one now gets what it needs, or derive the old meaning from the new where it is still needed.

### §B9. A claim about a value comes from all its writers

A class body rarely shows every write. An included module can set a field in a `before_create` callback, a factory or seed can fill it, and a database default can apply on insert. A spec once blamed a flaky tie on a `position` column "always blank", read off the model and its factory; an included ordering concern numbered positions within each parent group, so rows from two groups both sat at position 0, and the real cause was that tie. Grep for the field's name across the model's included modules, the callbacks they register, factories, seeds and migrations before writing down what it holds.

### §B10. A fix covers its whole class

A bug report names one symptom; the cause usually has siblings. A flaky ordering was fixed in the job that picked a row, while a test written the same day picked its expected row with the same tied query and stayed flaky for weeks. The fix's own description named the cause, so the sweep was one grep away. Write the cause as a pattern (`stages.first` over a per-group position), grep for it in code and tests, and give each hit a verdict in the PR. When diagnosing a later failure, read the earlier fix's description first (§B4): it may already explain the cause.

### §B11. A client mirror of a server calculation reads the server's inputs

A checkout shows the discounted price before the server charges it, so the client repeats the server's math. When the two read their inputs from different records, they agree only while those records agree. A discount rate moved from each storefront to a shop-wide settings row: the server read the row, the client still read the storefront, and a shop that deleted its last storefront showed full price while the server charged the discounted one, so payment failed. Put the server's read and the client's read side by side, and when a setting moves, move every reader (§B8).

### §B12. A list shows only what the viewer can open

A page that lists items, each behind its own access check, is safe only when the list applies that check too. Gating the list as a whole (any signed-in customer may open it) still shows every item, and the viewer then gets turned away by the ones they can't open, after learning they exist. Filter the list on the server with the same rule the item's page applies, and test it with a viewer who can open some items and not others.

### §B13. When one becomes many, nothing picks "the" one

A shop had one store, so code reached it as `shop.store`. When shops gain several stores, keeping `shop.store` as "the first one" lets old code compile and run, and it silently picks whichever store has the lowest id: a charge priced with that store's settings, an email branded with its logo, a fallback `order.store || shop.store` that sends the wrong store's message. None of it fails; it is just wrong for every shop with a second store.

**How to check.** Find every accessor that returns one record from the many (an ordered single-record association, `.first`, a `default_` method) and grep its readers. Each reader already has, or can get, the specific record it means: the order's store, the store in the URL, the store on the customer's account. Point it there, then delete the accessor and its fallbacks. Keep one only when a product rule says which record it is ("the store the shop marked primary"), and name that rule in the code.


### §B14. A guard against a delete counts only what the delete would harm

A shop could not delete a storefront "that has checkouts". Every checkout counted, so one guest who opened a checkout and left (expired) locked the storefront forever, and a test environment, where nobody completes payments, filled with storefronts nobody could delete. The guard existed to keep payment history; only paid checkouts, and ones still in progress, hold any.

**How to check.** List every status or state the related record can have and decide, for each, whether deleting the parent harms it. Count only those. Expired, failed, cancelled, archived and soft-deleted rows go with the parent or are cleaned up first. Then read the message as the person who hit it would: it names what blocks the delete in their words and says what to do instead ("turn it off").

### §B15. A change moves only the states it is for

A change is written with one state in mind, and the line it touches is reached by others. Each of these fixed the state in view and broke one nobody listed:

- An order page showed its payment method as `order.paymentMethodName || 'Store credit'`, so a failed card payment, with no method name, read "Store credit". A reviewer suggested falling back to "Store credit" only when the saved method is store credit. Before anything is saved, the customer's choice lives in the unsaved form, so a customer who had just picked store credit now saw "-".
- `count || 0` became `count ?? 0` to keep a real `0`, and `NaN` from a failed parse now reached the screen.
- An early return for a missing quantity, `if (!quantity) return`, also skipped a quantity of `0`.
- A stricter validation (a maximum length, a required field) rejected records already saved under the old rule, so every later edit of them failed.
- An order email swapped its footer whenever its sender changed, as a reviewer had suggested. A saved draft opened before the storefront list loaded was signed as the shop on the first pass, then "changed" to its storefront when the list arrived, so the storefront's footer showed twice. The suggestion was walked only against a person picking another storefront.
- A reviewer suggested reading a shop's storefronts straight from the shop instead of through the old lookup, which also checked the shop's plan, so shops on a plan without storefronts listed them again.

**How to check.** For each changed condition, fallback, default or validation, write down every state that reaches it: read each input where it comes from (the saved record, the unsaved form, the URL, a default), and list its values, including empty, each option of a choice, and records saved before the change. Then list when each input arrives (still loading, loaded, loaded after a first pass that ran without it, retried) and each path that reaches the line (every caller, with the checks each runs before it). Next to each row, write what happens before and after. Only the rows the change is for may move. Run the code when the result is not plain from reading it.

**A suggestion is a change too.** A fix proposed in a review is code someone will write because the reviewer asked, so it gets this walk before the comment is drafted, not after the author ships it. A suggestion whose table moves a row it is not for is rewritten until it doesn't, or dropped. Reading is not enough for one that changes behaviour, since the row the reviewer didn't think of is the one it breaks: apply it to a scratch copy of the branch, write the test for the break it fixes, run the suite and each row of the table, and only then ask for it, with `ran:` and the result in the evidence. When it can't be run, ask for the outcome and the test that proves it, not the code, and say it wasn't run. When the code handles content people write, the rows include every shape on §B2's list: a fix walked only against the case in the comment fixes that case and breaks the next shape, as a "read a line break as a space" suggestion did when bold text set against a comma was the next footer tried.
### §B16. A stored value is read in every state it can reach

A value written now and read later meets everything that happens in between. By the time it is read it can be missing, stale, written by an older version of the code, someone else's, half-written, or written by two writers at once, where the copy that wins is decided by a stamp taken before the slower one read its source; and code written along the path the feature was built on handles one of those.

An order page reads `?receipt=<id>` from its address to thank the buyer. Opened from the browser's history a week later, the address names an order since refunded. Opened from a link someone shared, it names another shop's order. Opened after the session expired, the page can't load the order at all. The page reaches each of these with no new code, and each needs its own answer.

The same habit catches a sign-in hint cookie that outlives its session, a draft saved by an older version in a shape the new code can't read, a retried job whose first run half-finished, and a script that updates its own install and then reads a path it stored before the update.

**How to check.** For each value the diff writes for later or reads from earlier, write the table: the value, each state it can be in when read, each event between the write and the read, and the `file:line` that handles each, or "unhandled". A row with no handler is the finding. A form value the user submits is §B5's; this box is for values that wait.

## Sweeps

Save the diff under review to a file and run the script over it; `-` reads the diff from stdin. No other sweep is bundled for this topic.

- `added-lines.sh` (citation map): every added line as `path:line: text`, with the source line number at the head SHA. Cite every finding's line from this output or from a sweep hit, never from a position in the diff file.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/added-lines.sh" <diff-file>
  ```

### §B17. A new kind of actor passes the guards written for the old one

Code that performs an action is full of checks written when only one kind of record did it: send only when the writer's account is active and their email connected, place the order only for a customer in good standing, charge only a card its owner still holds. When a new kind starts doing the same action (a store sends on a person's behalf, a service account places orders, a gift card pays), the diff adds the new path and those checks stay where they were, often in a job or scheduler the diff never opens. The work is then dropped or stalls without an error: a reminder scheduled from the store's address never goes out because its writer has no email of their own connected; a service account's order sits unpaid because the payment step asks for a customer's billing profile.

**How to check.** Name the action and the old kind. Grep each place that performs or queues the action (the job, the scheduler's query, the service, the early returns before it) for conditions on the old kind, and give each a verdict for the new kind. Then run the new kind through the path end to end, scheduled and immediate.

### §B18. A switch turned off stops every reader

A feature behind a flag, a permission or a plan is usually switched off where people see it: the menu entry, the settings page, the picker. The data it created keeps flowing through every other reader: a serializer that still sends it (and a subclass for public pages that declares the field again on its own), a job that sends queued work through it, an email footer built from it, an export. Turning the switch off then hides the setting and leaves the behaviour on. A custom storefront domain switched off for a shop kept appearing in every order email, since the link builder read the saved domain and never the switch.

**How to check.** List every reader of what the switch guards, by grep on the field, the association and the method names, subclasses included. Each reader checks the switch, through one method on the record that owns it so the readers agree, or says why it needn't. Then turn the switch off and walk each reader, signed-out pages and queued work included.
