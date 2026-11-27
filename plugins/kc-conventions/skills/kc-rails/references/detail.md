# Rails: examples and edge cases per box

### §RL1. Do it the way similar code does

- "There was no pattern to follow" is almost never true in a Rails app. Similar code means code that does the same kind of job, wherever it lives: the folder layout differs between apps, so search by what the code does (`rule(`, `validates`, `def call`, `has_many`, `render json:`, `scope :`), not by which directory it sits in.

- [ ] Read about ten pieces, not two or three. Two or three can be the odd ones out; ten show what the app does by default and which files are the exceptions. Read them per layer the change touches:

| Layer | What to match |
|---|---|
| Validation | where it lives (model validations, contracts, form objects, a validation library such as dry-validation), how ids are checked against the caller's scope, the wording of messages |
| The write | commands, service objects or the model; how they are called, transactions, callbacks, what they return |
| Controllers, routes and API shape | base class, before actions, how records are found and authorized, how params are read, response shape, member versus collection routes |
| Associations | how they are declared, `dependent:`, scopes on them, whether one record is reached through another |
| Serializers | which fields and relationships they expose, how related data is included, conditional fields |
| Queries and scopes | how filtering, scoping to the tenant, sorting and paging are done; what is loaded and when |
| Jobs and specs | queue choice, arguments, retries; spec type, factories, how requests are made and asserted |

- [ ] Write in the evidence what you read and what differs. A difference is a finding unless the change already says why.

- A new way of doing any of these is the last resort. Try each existing way first and show why it does not fit; then ask the developer before building the new one. A shape that only one file uses is not a pattern to copy either.

- Typical misses this catches: a create action that builds its record inline when similar actions build it in a setup callback; a subclass that overrides a save hook only to wrap it in a lock, when similar code takes the lock up front; a validation repeated in the write step that similar code leaves to the validator; a controller that rewrites its own request params when no other controller does; a new serializer variant for one response when similar responses reuse the existing serializer.

- **Checklist wording (moved from SKILL.md):** Done the way similar code does it: for every changed Ruby file, the evidence names by path the similar code read for each layer the change touches (about ten pieces per layer, or all there are when fewer: validation, the write, controller, routes and API shape, associations, serializer, query, job, spec), states the pattern that code follows, and lists what the change does differently. Fewer than ten read when more exist FAILS, and so does any new way of doing a layer's job without evidence that the existing ways were tried and the developer agreed. A changed file with no similar code named is FAIL, never N/A. (N/A: only specs and config changed)

### §RL2. Rails conventions

- Deviating from Rails conventions costs every future reader an assumption they are entitled to make. A scope beats an inline `where(active: true)` repeated across call sites, because the concept gets one name and one definition. An association without `dependent:` leaves deletes to chance.

- **Checklist wording (moved from SKILL.md):** Rails conventions: path matches class, pluralisation conventional, every new association declares `dependent:`, a filter used in more than one place or named for a concept is a `scope`, callbacks are documented ones. Enumerate added `has_many|has_one|where(` lines. (N/A: no model, association or query added)

### §RL3. Work in the app's own layers

- Whatever layers the app adds (service objects, commands, form objects, contracts, query objects), each kind of work has one home. Find it from similar code, not from preference.

- A check done in two places drifts. The exception is a race: a validator runs before any lock, so a check that must see committed state (no child rows were added since) belongs after the lock in the write, and the validator copy goes.

```ruby
# FAIL: the contract checks, then the command checks again under the lock
rule { base.failure('has orders') if record.orders.exists? }   # contract
raise CommandInvalid, 'has orders' if @record.orders.exists?   # command, after lock!

# PASS: one check, after the lock, with the reason
@record.lock!                                   # a concurrent insert waits here
raise CommandInvalid, 'has orders' if @record.orders.exists?
```

- [ ] Take a race's lock before its check:

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

- Preloading does nothing for a reader that chains a scope onto the association: `member.transactions.usage.where(created_at: window..).sum(:amount)` runs one SUM per member even with `transactions` loaded, because the chain builds a new relation. Classify each per-record read: walks loaded rows (preload fixes it) or queries (needs a bulk pass computing for the whole set at once).

- [ ] Install the bulk pass where every caller passes, typically the method that renders records for the API, and ask which callers still miss it. A pass called only from `#index` leaves `create`, `update` and `show` still querying per record. Note that records reached through nested includes may skip the seam.

- A computed serializer attribute that calls another computed attribute doubles the cost. Measure before claiming: state query counts and timings produced in the session, with the environment named.

- **§RL4d. The client asks for what it needs.** The server serves each record's own fields and the relationships to reach the rest; the client includes the related records it needs, so each screen pays only for what it reads. Copying an associated record's fields onto a serializer (`attribute :currency do |order| order.store.currency end`) works once and then spreads: the next screen needs one more field, the same values appear in two serializers that drift, and the client can no longer tell which record a value belongs to or cache it once. Expose the value on its own model's serializer, add the relationship if it is missing (`belongs_to :store`), and have the client include it (`?include=store`). When a field must stay hidden from some callers, gate it on that model's serializer, not by copying a safe subset elsewhere. An association's ids as an attribute (`attribute :tag_ids do |post| post.taggings.map(&:tag_id) end`) is the same copy: the relationship already carries the ids, and the attribute needs a preload on every render path or it queries per record. The same holds for which records come back: a serializer that drops some of a relationship's records (`has_many :comments do |post| post.comments.reject(&:hidden?) end`) hides a rule the client can't see or turn off, applies to every caller of that serializer, and returns a different set from the same request depending on context. Make it a filter the client sends and the query applies, so each screen asks for the set it shows; a flag that gates the behaviour is checked where the query applies that filter.

### §RL5. Request-shaped risks

- Request timeouts usually raise inside the app and render as a 500, so intermittent errors on large input are unbounded work until proven otherwise. Prefer a cap with a clear message when the work is fast, a background job when it is not.

- A GET that creates a missing record breaks on read replicas that block writes and under prefetching. Creating it on the first write instead leaves every reader handling a row that may not exist. Create it the way the parent's other default records are created, with the parent, and backfill parents that already exist.

- [ ] Trace every accepted attribute: a PATCH treats a missing key as "no change", type coercion can turn `""` into `nil`, and a numericality validation then rejects `nil`, so "clear this field" may be impossible. Run the validator and model when it is not plain from the code.

- A write that replaces a set (`order.storefront_ids = [...]`) removes as well as adds. Authorization that checks only the added ids lets a caller drop links to records they cannot reach, typically from a screen that never showed those links. Check both directions.

### §RL6. Renaming, retiring or backfilling a stored value

- See `references/backfills.md`. Failing any of its boxes fails this gate.

- **Checklist wording (moved from SKILL.md):** Stored values: when the diff renames, merges or retires a stored value or adds a backfill, every box in `references/backfills.md` was walked. (N/A: no enum, status constant, column meaning or backfill changed)

### §RL7. Specs that prove the change

- A hand-rolled counter that watches one SQL pattern only proves what you already suspected; the app's detector scans every query. Three records, because detectors need repetition. A route that never asked for the fix proves the seam is general.

- Mutation-check: remove the hook, the assignment, the preload in turn; each should fail a specific spec. A mutation that fails every spec in a file usually broke loading, not the behaviour.

- `bin/rails db:migrate` rewrites `db/schema.rb` from the local database. A database behind the main branch silently drops other migrations' columns and indexes from the dump. For a data-only change the schema diff is a version bump at most.

### §RL3a

- **Checklist wording (moved from SKILL.md):** Layers: each piece of work sits in the layer similar code puts it in; no controller building, saving or validating inline where similar controllers delegate. (N/A: no controller, command or service touched)

### §RL3b

- **Checklist wording (moved from SKILL.md):** One check, one place: no rule checked twice (validator or contract and again in the write), unless the second runs under a lock the first cannot and a comment says so. (N/A: no validation or guard added)

### §RL3c

- **Checklist wording (moved from SKILL.md):** No dead hooks or options: every override point, callback hook and contract or form option added is used by something today. Enumerate added `option :`, `attr_reader`, and methods that only call `super`. (N/A: none added)

### §RL3e

- **Checklist wording (moved from SKILL.md):** Races: every check-then-act on shared state takes its lock or transaction before the check, or the race is stated. Enumerate added `exists?|lock|with_lock|first_or_create|find_or_create`. (N/A: no check-then-act)

### §RL4a

- **Checklist wording (moved from SKILL.md):** Per-record reads: every added `sum|count|average|minimum|maximum|any?|exists?|pluck` reached per record is classified (walks loaded rows vs queries); a querying one has a bulk pass. (N/A: none added)

### §RL4d

- **Checklist wording (moved from SKILL.md):** The client asks for what it needs: every added serializer attribute belongs to the serializer's own model, and no relationship is loaded or sent unless the client includes it. An attribute whose value is read from another model (`object.store.currency`, a computed attribute that delegates to an associated record, an association's ids such as `taggings.map(&:tag_id)`) FAILS: expose it on that model's serializer and have the client include the relationship. When the association is missing from the client's path, add the relationship, not the attribute. (N/A: no serializer attribute added)

### §RL4e

- **Checklist wording (moved from SKILL.md):** Params handed to a serializer or view carry data, not a decision precomputed for one consumer (`signed_in: customer.present?`): pass the record and let the attribute that needs it check it. (N/A: no serializer or view params added)

### §RL4f

- **Checklist wording (moved from SKILL.md):** Which records the client gets is the client's filter: no serializer drops records from a collection or relationship by status, a flag or a context param (`object.events.reject(&:archived?)`, `has_many :events do ... end` returning a subset). The client sends the filter and the query applies it. (N/A: no serializer collection or relationship changed)

### §RL5c

- **Checklist wording (moved from SKILL.md):** Every accepted attribute has a defined result for present, `null`, `""` and missing, traced (or run) through coercion, validation and the write. (N/A: no attribute added or its handling unchanged)

### §RL5e

- **Checklist wording (moved from SKILL.md):** A write that replaces a set of links (`tag_ids = [...]`) checks the caller's access to every id it removes as well as every id it adds, and a spec removes one the caller can't reach. A check over `ids - current_ids` alone FAILS. (N/A: no set-replacing write)
