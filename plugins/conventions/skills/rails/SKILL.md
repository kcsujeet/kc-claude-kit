---
name: rails
description: "Rails conventions for Ruby source, specs and migrations: copying sibling files of the same kind, Rails naming and model conventions, work in the app's own layers, check-then-act races, per-record queries and N+1s (aggregates that preloading does not fix, bulk passes at a shared seam, computed serializer attributes, time-dependent memos), request-shaped risks (unbounded work, null and empty input, GETs that write, HTTP verbs), renaming, retiring or backfilling stored values, and spec honesty (N+1 specs, mutation checks, real data shapes, schema dumps). Use when writing or reviewing a Rails model, controller, command or service object, query, serializer, contract or form object, job, migration, backfill or spec."
user-invocable: false
paths:
  - "**/*.{rb,rake}"
  - "**/Gemfile"
  - "**/db/**/*"
---

# Rails

## Contents

- Rules
- Review checklist
- Review detail
  - §RL1. Copy the siblings
  - §RL2. Rails conventions
  - §RL3. Work in the app's own layers
  - §RL4. Per-record queries and N+1s
  - §RL5. Request-shaped risks
  - §RL6. Renaming, retiring or backfilling a stored value (in `references/backfills.md`)
  - §RL7. Specs that prove the change
- Sweeps

## Rules

A Rails app almost never needs a new shape. It already has dozens of controllers, models, jobs and whatever layers it adds (commands, service objects, form objects, contracts, query objects, serializers). New code looks like its siblings; a file that does not is the finding.

### Siblings and conventions

- Before writing or accepting a file, read two or three siblings of the same kind (a controller against other controllers, a job against other jobs) and match their shape: base class, callbacks, how they build the record, where they validate, what they delegate. Say which siblings and what differs. A deviation is stated and justified, never silent.
- New code acts on the subject of its home. A route, method or constant that only borrows its home's inputs belongs where its subject lives.
- Rails conventions hold: the file path matches the class, pluralisation is conventional, every `has_many` / `has_one` declares `dependent:`, a reusable filter is a `scope :name, -> { }` rather than an inline `where` repeated at call sites, and callbacks are the documented ones.

### Layers

- Work lives in the layer the app already uses for it: input parsing in its parser or service, validation where the app validates (model validations, contracts or form objects), writes in its write layer, scoping in its query layer, rendering in its serializers, authorization in its policies. A controller that builds and saves inline, or validates by hand, is a finding when its siblings do not.
- One check lives in one place. The same rule in a validator and again in the command is one too many, unless the second guards a race (it runs under a lock the first cannot), and a comment says so.
- A hook or option is only there when something uses it: no override point kept for one subclass that could do its work directly, no contract or form option nothing reads.
- Bulk writes use `insert_all` / `upsert_all` with an explicit `unique_by`, and dedupe their input first: Postgres rejects an upsert that touches the same row twice.
- A check-then-act on a shared resource (credits, seats, quota, a "first record" check, a generated unique code) runs under the same lock or transaction as the act, or the race is stated and accepted. Take the lock before the check, not around the write after it.

### Queries

- `includes` / `preload` only fixes readers that walk loaded rows in Ruby. A method that chains a scope or aggregates (`assoc.where(...).sum`, `.count`, `.exists?`, `.pluck`) still queries once per record; it needs a bulk pass over the whole set.
- A bulk pass is installed at a seam every caller goes through (the serializer or render entry point), not called from the one route that was slow, and is named for what it does, not for its first caller.
- Every computed serializer attribute (a method, not a column) is checked for a per-record query, including one that calls another computed attribute.
- A response the client only counts returns a count, not a serialized collection.
- No plain `@x ||=` memo on a value that depends on time or a window; it freezes silently.

### Requests

- Nothing unbounded runs in a request: rows in an upload, records serialized, external calls in a loop. Each has an explicit cap with a clear message, or moves to a background job.
- A GET never writes. Reads may run on a replica with writes blocked, and a crawler or prefetch can trigger them. Create a missing record on the first real write instead.
- Every accepted attribute has a defined result for present, `null`, `""` and missing, traced through type coercion, validation and the write. A cleared value either clears cleanly or falls back the same way every other write path does.
- The HTTP verb matches the effect: a read is a GET, and a POST that writes nothing is a finding.

### Stored values and backfills

- A rename, merge or retirement of a stored value (an enum member, a status or reason constant, a column's meaning) starts from a grep of every write site, and the new name must be true for every meaning the old value carried. When it is not, re-derive per row or fall back to an honest vague value.
- A backfill runs as a batched, resumable task (for example `maintenance_tasks`), not inside a migration, whenever it is unbatched, filters on a column with no usable index, or touches a table of unknown size. The PR says it must be run.
- A backfill that classifies rows by their stored value knows every writer of that column, in every repo, and checks each for a value that collides.

### Specs

- An N+1 fix is pinned with the app's N+1 detector (for example Prosopite or Bullet) over three records, not a hand-rolled query counter, and one spec covers a route that never asked for the fix.
- A spec for a bug reproduces the data the way the app writes it (a nullable column left null), not the way a fixture makes convenient.
- Every behaviour the change claims is mutation-checked: break it, and a specific spec fails.
- `db/schema.rb` is never regenerated from a stale local database; its diff holds only the intended change.

## Review checklist

The rails gate ticks every box against the diff. A box is FAIL if any matching construct violates it; N/A only when the diff has no matching construct, stated. Every grep receipt states its hit count and gives every hit a `file:line` verdict.

- [ ] §RL1 Siblings: for every changed Ruby file, two or three siblings of the same kind were read and named by path, and the evidence says what the new file does differently (base class, callbacks, record building, validation, delegation). A changed file with no named siblings is FAIL, never N/A. (N/A: only specs and config changed)
- [ ] §RL2 Rails conventions: path matches class, pluralisation conventional, every new association declares `dependent:`, a filter used in more than one place or named for a concept is a `scope`, callbacks are documented ones. Enumerate added `has_many|has_one|where(` lines. (N/A: no model, association or query added)
- [ ] §RL3a Layers: each piece of work sits in the layer its siblings put it in; no controller building, saving or validating inline where siblings delegate. (N/A: no controller, command or service touched)
- [ ] §RL3b One check, one place: no rule checked twice (validator or contract and again in the write), unless the second runs under a lock the first cannot and a comment says so. (N/A: no validation or guard added)
- [ ] §RL3c No dead hooks or options: every override point, callback hook and contract or form option added is used by something today. Enumerate added `option :`, `attr_reader`, and methods that only call `super`. (N/A: none added)
- [ ] §RL3d Bulk writes: every `insert_all|upsert_all` has `unique_by` and deduped input. (N/A: no bulk write)
- [ ] §RL3e Races: every check-then-act on shared state takes its lock or transaction before the check, or the race is stated. Enumerate added `exists?|lock|with_lock|first_or_create|find_or_create`. (N/A: no check-then-act)
- [ ] §RL4a Per-record reads: every added `sum|count|average|minimum|maximum|any?|exists?|pluck` reached per record is classified (walks loaded rows vs queries); a querying one has a bulk pass. (N/A: none added)
- [ ] §RL4b A bulk pass sits at a seam every caller passes and is named for what it does; callers that still miss it are named. (N/A: no bulk pass)
- [ ] §RL4c Every added or touched computed serializer attribute was checked for per-record queries. (N/A: no serializer touched)
- [ ] §RL4d No time-dependent `@x ||=` memo; an endpoint whose client only counts returns a count. (N/A: none added)
- [ ] §RL5a No unbounded work in a request; a cap has a clear message, or the work moves to a job. (N/A: nothing unbounded added)
- [ ] §RL5b No GET or HEAD writes: every read path added or touched saves, creates and enqueues nothing. (N/A: no read path)
- [ ] §RL5c Every accepted attribute has a defined result for present, `null`, `""` and missing, traced (or run) through coercion, validation and the write. (N/A: no attribute added or its handling unchanged)
- [ ] §RL5d HTTP verb matches effect. (N/A: no new endpoint)
- [ ] §RL6 Stored values: when the diff renames, merges or retires a stored value or adds a backfill, every box in `references/backfills.md` was walked. (N/A: no enum, status constant, column meaning or backfill changed)
- [ ] §RL7a N+1 specs use the app's detector over three records, and one covers a route that did not ask for the fix. (N/A: no N+1 fix)
- [ ] §RL7b A bug-fix spec builds data the way the app writes it. (N/A: not a bug fix)
- [ ] §RL7c Mutation-checked: each claimed behaviour broken in turn failed a specific spec, and the tree was restored clean. (N/A: diff adds no behaviour)
- [ ] §RL7d `db/schema.rb` diff holds only the intended change. (N/A: `db/` untouched)

## Review detail

### §RL1. Copy the siblings

"There was no pattern to follow" is almost never true in a Rails app. Pick siblings from the same directory family (`app/controllers/`, `app/models/`, `app/jobs/`, and the app's own layer folders), read them, and write in the evidence which ones and what the new file does differently. A difference is a finding unless the change already says why.

Typical misses this catches: a create action that builds its record inline when its siblings build it in a setup callback; a subclass that overrides a save hook only to wrap it in a lock, when siblings take the lock up front; a validation repeated in the write step that siblings leave to the validator.

### §RL2. Rails conventions

Deviating from Rails conventions costs every future reader an assumption they are entitled to make. A scope beats an inline `where(active: true)` repeated across call sites, because the concept gets one name and one definition. An association without `dependent:` leaves deletes to chance.

### §RL3. Work in the app's own layers

Whatever layers the app adds (service objects, commands, form objects, contracts, query objects), each kind of work has one home. Find it from the siblings, not from preference.

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

### §RL5. Request-shaped risks

Request timeouts usually raise inside the app and render as a 500, so intermittent errors on large input are unbounded work until proven otherwise. Prefer a cap with a clear message when the work is fast, a background job when it is not.

A GET that creates a missing record breaks on read replicas that block writes and under prefetching. Return an unsaved default on read and create on the first write.

Trace every accepted attribute: a PATCH treats a missing key as "no change", type coercion can turn `""` into `nil`, and a numericality validation then rejects `nil`, so "clear this field" may be impossible. Run the validator and model when it is not plain from the code.

### §RL6. Renaming, retiring or backfilling a stored value

See `references/backfills.md`. Failing any of its boxes fails this gate.

### §RL7. Specs that prove the change

A hand-rolled counter that watches one SQL pattern only proves what you already suspected; the app's detector scans every query. Three records, because detectors need repetition. A route that never asked for the fix proves the seam is general.

Mutation-check: remove the hook, the assignment, the preload in turn; each should fail a specific spec. A mutation that fails every spec in a file usually broke loading, not the behaviour.

`bin/rails db:migrate` rewrites `db/schema.rb` from the local database. A database behind the main branch silently drops other migrations' columns and indexes from the dump. For a data-only change the schema diff is a version bump at most.

## Sweeps

The citation map, run first: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/added-lines.sh <diff-file>`.

The rails gate's receipts are greps over the added lines of `<diff-file>` for the patterns its boxes name (§RL2, §RL3c, §RL3e, §RL4a), each stated with its hit count and a verdict per hit.
