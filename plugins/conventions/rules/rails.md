---
paths:
  - "**/*.{rb,rake}"
  - "**/Gemfile"
  - "**/db/**/*"
---
<!-- Generated from skills/rails/SKILL.md by scripts/build-rules.sh. Edit the skill, not this file. -->

# Rails

A Rails app almost never needs a new shape. It already has dozens of controllers, models, jobs and whatever layers it adds (commands, service objects, form objects, contracts, query objects, serializers). New code looks like its siblings; a file that does not is the finding.

## Siblings and conventions

- Before writing or accepting a file, read two or three siblings of the same kind (a controller against other controllers, a job against other jobs) and match their shape: base class, callbacks, how they build the record, where they validate, what they delegate. Say which siblings and what differs. A deviation is stated and justified, never silent.
- New code acts on the subject of its home. A route, method or constant that only borrows its home's inputs belongs where its subject lives.
- Rails conventions hold: the file path matches the class, pluralisation is conventional, every `has_many` / `has_one` declares `dependent:`, a reusable filter is a `scope :name, -> { }` rather than an inline `where` repeated at call sites, and callbacks are the documented ones.

## Layers

- Work lives in the layer the app already uses for it: input parsing in its parser or service, validation where the app validates (model validations, contracts or form objects), writes in its write layer, scoping in its query layer, rendering in its serializers, authorization in its policies. A controller that builds and saves inline, or validates by hand, is a finding when its siblings do not.
- One check lives in one place. The same rule in a validator and again in the command is one too many, unless the second guards a race (it runs under a lock the first cannot), and a comment says so.
- A hook or option is only there when something uses it: no override point kept for one subclass that could do its work directly, no contract or form option nothing reads.
- Bulk writes use `insert_all` / `upsert_all` with an explicit `unique_by`, and dedupe their input first: Postgres rejects an upsert that touches the same row twice.
- A check-then-act on a shared resource (credits, seats, quota, a "first record" check, a generated unique code) runs under the same lock or transaction as the act, or the race is stated and accepted. Take the lock before the check, not around the write after it.

## Queries

- `includes` / `preload` only fixes readers that walk loaded rows in Ruby. A method that chains a scope or aggregates (`assoc.where(...).sum`, `.count`, `.exists?`, `.pluck`) still queries once per record; it needs a bulk pass over the whole set.
- A bulk pass is installed at a seam every caller goes through (the serializer or render entry point), not called from the one route that was slow, and is named for what it does, not for its first caller.
- Every computed serializer attribute (a method, not a column) is checked for a per-record query, including one that calls another computed attribute.
- Serializer and view params carry the data (the signed-in customer, the current shop), not a flag worked out from it for one consumer; the consumer that needs it decides.
- The client asks for what it needs; the server doesn't hand it everything. A serializer exposes its own model's attributes, and another model's data reaches the client only through a relationship the client chooses to include, never as that model's attributes copied onto this serializer or sent by default.
- A response the client only counts returns a count, not a serialized collection.
- No plain `@x ||=` memo on a value that depends on time or a window; it freezes silently.

## Requests

- Nothing unbounded runs in a request: rows in an upload, records serialized, external calls in a loop. Each has an explicit cap with a clear message, or moves to a background job.
- A GET never writes. Reads may run on a replica with writes blocked, and a crawler or prefetch can trigger them. A record every parent needs is created the way the parent's other default records are, with the parent, plus a backfill for parents that already exist.
- Every accepted attribute has a defined result for present, `null`, `""` and missing, traced through type coercion, validation and the write. A cleared value either clears cleanly or falls back the same way every other write path does.
- The HTTP verb matches the effect: a read is a GET, and a POST that writes nothing is a finding.

## Stored values and backfills

- A rename, merge or retirement of a stored value (an enum member, a status or reason constant, a column's meaning) starts from a grep of every write site, and the new name must be true for every meaning the old value carried. When it is not, re-derive per row or fall back to an honest vague value.
- A backfill runs as a batched, resumable task (for example `maintenance_tasks`), not inside a migration, whenever it is unbatched, filters on a column with no usable index, or touches a table of unknown size. The PR says it must be run.
- A backfill that classifies rows by their stored value knows every writer of that column, in every repo, and checks each for a value that collides.

## Specs

- An N+1 fix is pinned with the app's N+1 detector (for example Prosopite or Bullet) over three records, not a hand-rolled query counter, and one spec covers a route that never asked for the fix.
- A spec for a bug reproduces the data the way the app writes it (a nullable column left null), not the way a fixture makes convenient.
- Every behaviour the change claims is mutation-checked: break it, and a specific spec fails.
- `db/schema.rb` is never regenerated from a stale local database; its diff holds only the intended change.
