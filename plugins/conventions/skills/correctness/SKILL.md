---
name: correctness
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
  - §B8. When a value's meaning changes, every reader changes
  - §B9. A claim about a value comes from all its writers
  - §B10. A fix covers its whole class
  - §B11. A client mirror of a server calculation reads the server's inputs
  - §B12. A list shows only what the viewer can open
  - §B13. When one becomes many, nothing picks "the" one
- Sweeps

## Rules

Code that reads well and is wrong is still wrong. Walk every change for the bugs a reader skims past.

- Consider the empty, null, zero and boundary input on every path you add or change, not only the value the feature was built for.
- Check every operator and condition for an off-by-one or an inversion: `<` against `<=`, `&&` against `||`, a negation that flips the meaning.
- Keep dependency arrays and closures current: an effect, memo, callback or handler reads the latest value of everything it uses.
- Do not let a cast hide a real type mismatch. When data crossing a boundary (an API response, props, storage) does not match its declared type, fix the type or parse the value.
- Before changing code, check the repo's history for a bug already fixed there (the changelog, dev logs, `git log -S <symbol>`), so the change does not bring it back.
- Trace every submitted field from its input, through any transform and the request payload, to what the receiving end does with it, for each state the user can leave it in: set, changed, cleared, left alone, invalid. Each state must arrive in a shape the receiver accepts and have the effect the user expects.
- When a change adds a reference from one module or class to another, follow the references back and check that they do not close a loop. Inside a loop, code that runs when a module is defined (a subclass copying its parent's fields, a registration, class-level configuration) can run before what it needs exists, and fail with no error. Use the lazy form of the reference when the library has one.
- A count, total or summary of a list uses the same filter as the list: what the list hides (archived, deleted, inactive items) the count leaves out too.
- When a change alters what a value means (a route parameter or field now holds a different kind of id, a setting now applies per item), find every reader of that value and check each one still gets what it expects.
- A bug fix covers every instance of its cause, not only the one that was reported. Once the cause is known, grep the repo, tests included, for the same pattern (the same query, call or assumption) and fix or list each hit; code written alongside the original, on the same day or in a sibling branch, is the first place to look.
- Before saying what a value holds ("this column is always blank", the cause of a flaky test), find every writer of it: the class body, every module or concern it includes and their callbacks, factories and seed code. A claim read off the visible class alone is a guess.
- When a change turns one into many (a shop's store becomes stores), every accessor that still picks "the" one (the first, the lowest id, a "default") is a leftover unless a stated product rule chooses it. Each reader uses the specific record it already has (the order's store, the one in the URL), and the accessor and every fallback to it go.

Detection criteria and per-box review failure modes live in the `## Review checklist` of the `correctness` skill (`conventions:correctness`), with the detail under its `## Review detail`. These rules are the statement of the convention; that checklist is how a diff gets graded against it.

## Review checklist

The correctness gate agent ticks every box against the diff. A box is FAIL if any matching construct violates the rule; the gate is FAIL if any box is FAIL. Each box states its own N/A condition.

- [ ] §B1 Logic: no off-by-one, wrong operator, inverted condition, stale state or closure (an effect, callback or handler reading a value captured before it changed), or wrong dependency array (a value the body reads is missing, or a listed value changes every render). (N/A: the diff adds or changes no condition, loop, index or range arithmetic, state update, closure, or dependency array)
- [ ] §B2 Edge cases: every added or changed path handles empty collections, null/undefined, zero, and boundary values (first, last, exactly at a limit), and every date or time the diff formats or parses uses the configured timezone rather than the machine's. (N/A: the diff changes no path that takes input, and formats or parses no date or time)
- [ ] §B3 Data shape: values crossing a boundary (an API response, props, storage, a URL or form value) match their declared type at runtime. A cast or `any` that lets a real mismatch through is a finding here; the syntax of the escape hatch itself is clarity §C17. (N/A: no value crosses a boundary in the diff)
- [ ] §B4 Regression: the diff does not reintroduce a bug the repo already fixed. The changelog, the dev logs (when the repo keeps them) and `git log -S <symbol>` were checked for every touched symbol, and the receipt names what was searched. (N/A: the diff only adds new files and touches no existing symbol)
- [ ] §B5 Every submitted value lands as intended: for each field the diff sends (a form, a request built from user input), the evidence traces it from the input, through the transform and the payload, to the receiver's handling (its parsing, the keys it accepts, its validations), for each state the user can leave it in: set, changed, cleared, left alone, invalid. Each state arrives in a shape the receiver accepts and has the effect the user expects. A field with no trace FAILS by default. The receiving code was read (in this repo or the backend's), and run when its effect is not plain from the code. (N/A: the diff sends no user-entered value)
- [ ] §B6 A new reference does not close a load cycle: for each reference the diff adds from one module or class to another (an import, a require, a constant, a serializer or association that names another class), the evidence follows that class's own references back and states whether they lead to the first one. When they close a loop and any module in it does work at definition time (inheritance that copies the parent's declarations, a registry, class-level configuration, a decorator), the box FAILS unless the reference is lazy (a block, a proc, a string name or a deferred import that resolves on first use). A cycle with no definition-time work is clarity §C14. (N/A: the diff adds no reference between modules)
- [ ] §B7 A count uses the same filter as its list: every count, total or summary the diff adds or changes is computed with the same conditions as the list it summarises (soft-deleted, archived, inactive, other-tenant rows excluded alike), and the evidence names both queries. (N/A: the diff adds or changes no count, total or summary)
- [ ] §B8 When a value's meaning changes, every reader changes: when the diff changes what a value holds (a route parameter, field or prop now carries a different kind of id or a narrower or wider scope), the evidence lists every reader of that value found by grep, including ones the diff does not touch, and states for each that it still gets what it expects. (N/A: no value changes meaning)
- [ ] §B9 A claim about a value's contents, in a comment, a commit message or a test's reasoning ("positions are blank", "this is the only writer"), was checked against every writer: the class body, each included module or concern and its callbacks, factories and seeds. One that read only the visible class body FAILS. (N/A: the diff states nothing about what a value holds)
- [ ] §B10 A fix covers its whole class: when the diff fixes a bug, the evidence names its cause as a searchable pattern, the grep that was run for it across code and tests, and a verdict per hit (fixed here, safe and why, or listed for follow-up). A fix with no such sweep FAILS. (N/A: the diff fixes no bug)
- [ ] §B11 A client that mirrors a server calculation (a price, a total, a balance it shows before the server charges it) reads each input from the record the server reads, and the evidence names the server code and the client read side by side. An input read from a different record that holds the same value only some of the time (a copy, a legacy column, a record that can be deleted) FAILS. (N/A: the diff mirrors no server calculation)
- [ ] §B12 A list shows only what the viewer can open: when each listed item has its own access check (its page turns some viewers away), the list applies the same check, server-side, and the evidence names both. A list gated only as a whole, whose items then refuse the viewer, FAILS. (N/A: no list of items with their own access check)
- [ ] §B13 Nothing picks "the" one after one becomes many: when the diff, or the feature it continues, turns a one-to-one into a one-to-many, every accessor that returns a single record from the many (`first`, lowest id, `default_*`, a single-record association with an order) and every fallback to it (`order.store || shop.store`) is listed with its readers. Each FAILS unless a product rule says how that record is chosen, and the finding names the specific record each reader should use instead. (N/A: no cardinality change in scope)

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

**Timezone.** When the app configures a time zone, a date formatted or parsed without it follows the machine's zone. `Intl.DateTimeFormat` without a `timeZone` option, or a string with no offset parsed by `new Date()`, is the common shape. Grep the repo for how it configures the zone before flagging, and cite it.

### §B3. Data shape

Check the declared type of every value that crosses a boundary against what actually arrives: the API contract, the props a caller passes, what storage returns, what a URL or form field holds (always a string). Drift between the contract and the type, an `as` cast that asserts the expected shape instead of checking it, and `any` carrying a wrong type through are findings here when the runtime value can differ from the type. State the mismatch: what the type says, what arrives, and where.

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

### §B8. When a value's meaning changes, every reader changes

A change that makes a value mean something new (a storefront's page now takes the storefront's own id where it used to take the shop's, a field that held one id now holds another kind) updates the code it is working on, while every other reader keeps sending the value where the old meaning is expected. Nothing fails loudly: the lookup finds nothing, and the screen shows its empty or signed-out state. Grep every reader of the value, including ones the diff never touched, and confirm each one now gets what it needs, or derive the old meaning from the new where it is still needed.

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

## Sweeps

Save the diff under review to a file and run the script over it; `-` reads the diff from stdin. No other sweep is bundled for this topic.

- `added-lines.sh` (citation map): every added line as `path:line: text`, with the source line number at the head SHA. Cite every finding's line from this output or from a sweep hit, never from a position in the diff file.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/added-lines.sh" <diff-file>
  ```
