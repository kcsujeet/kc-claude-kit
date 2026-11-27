# Rails: examples and edge cases per box

### §RL1. Do it the way similar code does

"There was no pattern to follow" is almost never true in a Rails app. Similar code means code that does the same kind of job, wherever it lives: the folder layout differs between apps, so search by what the code does (`rule(`, `validates`, `def call`, `has_many`, `render json:`, `scope :`), not by which directory it sits in.

Read about ten pieces, not two or three. Two or three can be the odd ones out; ten show what the app does by default and which files are the exceptions. Read them per layer the change touches:

| Layer | What to match |
|---|---|
| Validation | where it lives (model validations, contracts, form objects, a validation library such as dry-validation), how ids are checked against the caller's scope, the wording of messages |
| The write | commands, service objects or the model; how they are called, transactions, callbacks, what they return |
| Controllers, routes and API shape | base class, before actions, how records are found and authorized, how params are read, response shape, member versus collection routes |
| Associations | how they are declared, `dependent:`, scopes on them, whether one record is reached through another |
| Serializers | which fields and relationships they expose, how related data is included, conditional fields |
| Queries and scopes | how filtering, scoping to the tenant, sorting and paging are done; what is loaded and when |
| Jobs and specs | queue choice, arguments, retries; spec type, factories, how requests are made and asserted |

Write in the evidence what you read and what differs. A difference is a finding unless the change already says why.

A new way of doing any of these is the last resort. Try each existing way first and show why it does not fit; then ask the developer before building the new one. A shape that only one file uses is not a pattern to copy either.

Typical misses this catches: a create action that builds its record inline when similar actions build it in a setup callback; a subclass that overrides a save hook only to wrap it in a lock, when similar code takes the lock up front; a validation repeated in the write step that similar code leaves to the validator; a controller that rewrites its own request params when no other controller does; a new serializer variant for one response when similar responses reuse the existing serializer.

### §RL2. Rails conventions

Deviating from Rails conventions costs every future reader an assumption they are entitled to make. A scope beats an inline `where(active: true)` repeated across call sites, because the concept gets one name and one definition. An association without `dependent:` leaves deletes to chance.

### §RL3. Work in the app's own layers

Whatever layers the app adds (service objects, commands, form objects, contracts, query objects), each kind of work has one home. Find it from similar code, not from preference.

A check done in two places drifts. The exception is a race: a validator runs before any lock, so a check that must see committed state (no child rows were added since) belongs after the lock in the write, and the validator copy goes.

```ruby
# FAIL: the contract checks, then the command checks again under the lock
rule { base.failure('has orders') if record.orders.exists? }   # contract
raise CommandInvalid, 'has orders' if @record.orders.exists?   # command, after lock!

# PASS: one check, after the lock, with the reason
@record.lock!                                   # a concurrent insert waits here
raise CommandInvalid, 'has orders' if @record.orders.exists?
```

Take a race's lock before its check:

```ruby
# FAIL: the "first record" check runs before the lock, so two creates can both see none
@first = !shop.storefronts.exists?
shop.with_lock { record.save! }

# PASS
shop.lock!
@first = !shop.storefronts.exists?
record.save!
```

### §RL4. Per-record queries and N+1s

Preloading does nothing for a reader that chains a scope onto the association: `member.transactions.usage.where(created_at: window..).sum(:amount)` runs one SUM per member even with `transactions` loaded, because the chain builds a new relation. Classify each per-record read: walks loaded rows (preload fixes it) or queries (needs a bulk pass computing for the whole set at once).

Install the bulk pass where every caller passes, typically the method that renders records for the API, and ask which callers still miss it. A pass called only from `#index` leaves `create`, `update` and `show` still querying per record. Note that records reached through nested includes may skip the seam.

A computed serializer attribute that calls another computed attribute doubles the cost. Measure before claiming: state query counts and timings produced in the session, with the environment named.

**§RL4d. The client asks for what it needs.** The server serves each record's own fields and the relationships to reach the rest; the client includes the related records it needs, so each screen pays only for what it reads. Copying an associated record's fields onto a serializer (`attribute :currency do |order| order.store.currency end`) works once and then spreads: the next screen needs one more field, the same values appear in two serializers that drift, and the client can no longer tell which record a value belongs to or cache it once. Expose the value on its own model's serializer, add the relationship if it is missing (`belongs_to :store`), and have the client include it (`?include=store`). When a field must stay hidden from some callers, gate it on that model's serializer, not by copying a safe subset elsewhere. An association's ids as an attribute (`attribute :tag_ids do |post| post.taggings.map(&:tag_id) end`) is the same copy: the relationship already carries the ids, and the attribute needs a preload on every render path or it queries per record. The same holds for which records come back: a serializer that drops some of a relationship's records (`has_many :comments do |post| post.comments.reject(&:hidden?) end`) hides a rule the client can't see or turn off, applies to every caller of that serializer, and returns a different set from the same request depending on context. Make it a filter the client sends and the query applies, so each screen asks for the set it shows; a flag that gates the behaviour is checked where the query applies that filter.

### §RL5. Request-shaped risks

Request timeouts usually raise inside the app and render as a 500, so intermittent errors on large input are unbounded work until proven otherwise. Prefer a cap with a clear message when the work is fast, a background job when it is not.

A GET that creates a missing record breaks on read replicas that block writes and under prefetching. Creating it on the first write instead leaves every reader handling a row that may not exist. Create it the way the parent's other default records are created, with the parent, and backfill parents that already exist.

Trace every accepted attribute: a PATCH treats a missing key as "no change", type coercion can turn `""` into `nil`, and a numericality validation then rejects `nil`, so "clear this field" may be impossible. Run the validator and model when it is not plain from the code.

A write that replaces a set (`order.storefront_ids = [...]`) removes as well as adds. Authorization that checks only the added ids lets a caller drop links to records they cannot reach, typically from a screen that never showed those links. Check both directions.

### §RL6. Renaming, retiring or backfilling a stored value

See `references/backfills.md`. Failing any of its boxes fails this gate.

### §RL7. Specs that prove the change

A hand-rolled counter that watches one SQL pattern only proves what you already suspected; the app's detector scans every query. Three records, because detectors need repetition. A route that never asked for the fix proves the seam is general.

Mutation-check: remove the hook, the assignment, the preload in turn; each should fail a specific spec. A mutation that fails every spec in a file usually broke loading, not the behaviour.

`bin/rails db:migrate` rewrites `db/schema.rb` from the local database. A database behind the main branch silently drops other migrations' columns and indexes from the dump. For a data-only change the schema diff is a version bump at most.
