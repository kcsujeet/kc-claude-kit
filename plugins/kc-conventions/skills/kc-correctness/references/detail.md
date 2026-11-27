# Correctness: examples and edge cases per box

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

**Content people write.** Code that finds, parses or rewrites what a person composed meets every shape they can compose, not the one in the ticket. Before reviewing it, list the shapes: plain text, line breaks inside one block, several blocks, inline formatting or a link set right against other words, images (beside text and on their own), tables, blank lines, empty, and none at all. Run each through every path that moves the content (insert it, replace it, remove it, replace it back) and check what is left. A shop's order email swapped one store's footer for another by finding the old footer by its words. Review checked the reported case each round (plain text, then line breaks, then bold next to a comma) and walked each fix only against that case, so a footer with a logo, a logo-only footer and a store with no footer all failed only in the fifth round: an image has no words to find, and a missing footer leaves nothing to replace. The list finds all of them in one pass. It also catches an address parser given a second line, a mention parser given a name inside a link, and a cleaner that strips markup from a pasted table. A pattern that decides whether text is markup is tested on the near-misses too: an address in angle brackets (`<b@shop.com>`), an abbreviation (`<i.e. note>`) and a hyphenated word (`<u-turn>`) are not tags, and a pattern that eats them deletes what the person typed; and on a long run of its opening character, since `<[^>]*>` backtracks quadratically on `'<'.repeat(n)`, so a long paste freezes the page. A conversion (rich text to plain text and back) keeps what was typed: collapsing blank lines or trimming spaces rewrites the person's text. When each round finds a new shape the same code misses, the approach is the finding (`kc-code-review` §G5).

**Lifecycle states.** A record is rarely just present or absent: it can be deactivated, archived, deleted, disconnected or expired, and each new list, picker, count, badge and export decides what to do with each. Name each state the record can be in (read the model, not the happy path) and say, per surface, whether such records show, show marked, or stay out; a surface that silently includes them is the finding. Examples: deactivated users in a new settings list of teammates; archived products in a new sales report; expired access tokens in an admin list; a disconnected integration still offered in a picker.

**Timezone.** When the app configures a time zone, a date formatted or parsed without it follows the machine's zone. `Intl.DateTimeFormat` without a `timeZone` option, or a string with no offset parsed by `new Date()`, is the common shape. Grep the repo for how it configures the zone before flagging, and cite it.

### §B3. Data shape

Check the declared type of every value that crosses a boundary against what actually arrives: the API contract, the props a caller passes, what storage returns, what a URL or form field holds (always a string). Drift between the contract and the type, an `as` cast that asserts the expected shape instead of checking it, and `any` carrying a wrong type through are findings here when the runtime value can differ from the type. State the mismatch: what the type says, what arrives, and where.

Records older code wrote can lack a key the current code always writes; that is §B16's "written by an older version" state, checked against the server's schema or a sample of real rows, not the type.

**A unit reused from a new caller.** A component, hook or function written for one caller often depends on a cleanup that caller does before handing data over (a default, a parse, a filter). A new caller that passes the raw response skips it, and the type, written for the cleaned data, doesn't say so. List the unit's callers and what each does to the data first; the new caller does the same, or the unit does it itself. Examples: a price breakdown built for a settings screen that fills missing prices, reused on a saved order whose older rows lack one, so the total came out as NaN; a date picker fed an ISO string where its first caller passed a `Date`; a list component reused on an endpoint that, unlike the first, returns archived rows.

### §B4. Regression

Do not trust the PR description for this box; check the history. For every symbol the diff changes, search the changelog, the repo's dev logs if it keeps them, and `git log -S <symbol> --oneline` for an earlier fix to the same code. When one exists, read it and confirm the diff does not undo it (a guard removed, a boundary rule reverted, a workaround deleted without the cause being fixed). The receipt names the sources searched and the commits found, or `no prior fix found` with the search stated.

**A step that combines work.** A merge, rebase, conflict resolution, squash, cherry-pick, regeneration or file copy is a place work gets lost quietly, and a clean finish proves nothing about it: the tool picked one side and said nothing. For each file both sides touched, list what each side changed there (`git log <base>..<side> -- <file>`, and for a merge `git diff <parent> <merge> -- <file>` against each parent) and confirm each survives in the result. Examples: a branch cut before another change merged, whose stale copy of a file was kept in the merge and undid that change; a rebase that dropped one hunk of a conflicted file; regenerated client code overwriting hand edits made to it.

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

A value also waits under the rules it was written by. A product note whose editor allows only bold is shown on the storefront through a shared viewer that defaults to links and images too; the editor's limit never reaches the reader, so a note saved by another route (an import, an older version, an API call) shows a link or image the editor would have refused. A coupon code validated on write (upper case, fixed length) and parsed loosely on read (trimmed, case-folded, prefix-matched) accepts what no one could enter. Each reader of a value reads it under the rules it was written by, and a shared component with a wider default gets the narrow schema passed at every reader.

The same habit catches a sign-in hint cookie that outlives its session, a draft saved by an older version in a shape the new code can't read, a retried job whose first run half-finished, and a script that updates its own install and then reads a path it stored before the update.

**How to check.** For each value the diff writes for later or reads from earlier, write the table: the value, each state it can be in when read, each event between the write and the read, and the `file:line` that handles each, or "unhandled". A row with no handler is the finding. A form value the user submits is §B5's; this box is for values that wait.

### §B17. A sibling or parallel path shares the original's rules and guards

A new field, path or kind of record is usually built by copying the shape of one that exists, and the copy carries the code but not the rules that grew around the original: the fallback when it is blank, the validation, who may use it, what it shows when empty, its default, and the guards that keep it safe (waiting while a connection is in an errored or disconnected state, skipping a deactivated owner, a limit, a retry). Before accepting the new one, list every rule its sibling has, one row each, and give each a verdict for the new one: same, differs on purpose, or missing. A difference is not settled by writing it into help text or a comment; it goes to whoever owns the behaviour as a decision, with the sibling's behaviour beside it.

Examples: a new sender-name setting with no fallback when blank, while the signature setting beside it falls back to the shop's name; a scheduled send from a new kind of account that skips the wait-while-errored guard the original kind has; a new payment method that skips the fraud check the cards have; a new import path that skips the validation the upload path runs.

### §B18. A reliance on another unit's internal behaviour is a hidden contract

Some code works only because another unit does something it never promised in a signature: the base class calls the hook, the framework yields to the block, the parent's method runs because the override calls `super`, a model fires its callback, the host calls the plugin. Nothing in the code at hand says so, so a change on the other side (an override that stops calling `super`, a refactor that no longer fires the callback) removes the behaviour and everything still compiles and reads well. For each reliance the diff adds or touches, name it, then prefer a seam the owner can see (the check passed as an explicit argument, an interface the owner declares), and pin what stays implicit with a test that fails when the other side stops. After integrating upstream work (a merge, a rebase, a dependency bump), trace each reliance again: the diff of the integration will not show a thing that stopped being called.

Examples: a validation passed as a block the base class yields to, lost when a subclass's override was rewritten without calling `super`, with no test failing; a model callback that no longer fires after the code that triggered it was refactored; a plugin hook skipped once the host stopped calling it.
