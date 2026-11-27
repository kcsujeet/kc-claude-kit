---
name: kc-rails
description: "Rails conventions for Ruby source, specs and migrations: the app's own layers and patterns, races, N+1s, request-shaped risks, backfills, spec honesty. Use when writing or reviewing a Rails model, controller, command, service, query, serializer, contract, job, migration or spec."
user-invocable: false
paths:
  - "**/*.{rb,rake}"
  - "**/Gemfile"
  - "**/db/**/*"
---

# Rails

## Contents

- Review checklist
- Sweeps

## Review checklist

Tick every box for each construct you add or change. Report each: PASS, FAIL (file:line) or N/A (why).

- [ ] §RL1 Done the way similar code does it: for every changed Ruby file, the evidence names by path the similar code read for each layer the change touches (about ten pieces per layer, or all there are when fewer: validation, the write, controller, routes and API shape, associations, serializer, query, job, spec), states the pattern that code follows, and lists what the change does differently. Fewer than ten read when more exist FAILS, and so does any new way of doing a layer's job without evidence that the existing ways were tried and the developer agreed. A changed file with no similar code named is FAIL, never N/A. (N/A: only specs and config changed)
- [ ] §RL2 Rails conventions: path matches class, pluralisation conventional, every new association declares `dependent:`, a filter used in more than one place or named for a concept is a `scope`, callbacks are documented ones. Enumerate added `has_many|has_one|where(` lines. (N/A: no model, association or query added)
- [ ] §RL3a Layers: each piece of work sits in the layer similar code puts it in; no controller building, saving or validating inline where similar controllers delegate. (N/A: no controller, command or service touched)
- [ ] §RL3b One check, one place: no rule checked twice (validator or contract and again in the write), unless the second runs under a lock the first cannot and a comment says so. (N/A: no validation or guard added)
- [ ] §RL3c No dead hooks or options: every override point, callback hook and contract or form option added is used by something today. Enumerate added `option :`, `attr_reader`, and methods that only call `super`. (N/A: none added)
- [ ] §RL3d Bulk writes: every `insert_all|upsert_all` has `unique_by` and deduped input. (N/A: no bulk write)
- [ ] §RL3e Races: every check-then-act on shared state takes its lock or transaction before the check, or the race is stated. Enumerate added `exists?|lock|with_lock|first_or_create|find_or_create`. (N/A: no check-then-act)
- [ ] §RL4a Per-record reads: every added `sum|count|average|minimum|maximum|any?|exists?|pluck` reached per record is classified (walks loaded rows vs queries); a querying one has a bulk pass. (N/A: none added)
- [ ] §RL4b A bulk pass sits at a seam every caller passes and is named for what it does; callers that still miss it are named. (N/A: no bulk pass)
- [ ] §RL4c Every added or touched computed serializer attribute was checked for per-record queries. (N/A: no serializer touched)
- [ ] §RL4d The client asks for what it needs: every added serializer attribute belongs to the serializer's own model, and no relationship is loaded or sent unless the client includes it. An attribute whose value is read from another model (`object.store.currency`, a computed attribute that delegates to an associated record, an association's ids such as `taggings.map(&:tag_id)`) FAILS: expose it on that model's serializer and have the client include the relationship. When the association is missing from the client's path, add the relationship, not the attribute. (N/A: no serializer attribute added)
- [ ] §RL4e Params handed to a serializer or view carry data, not a decision precomputed for one consumer (`signed_in: customer.present?`): pass the record and let the attribute that needs it check it. (N/A: no serializer or view params added)
- [ ] §RL4f Which records the client gets is the client's filter: no serializer drops records from a collection or relationship by status, a flag or a context param (`object.events.reject(&:archived?)`, `has_many :events do ... end` returning a subset). The client sends the filter and the query applies it. (N/A: no serializer collection or relationship changed)
- [ ] §RL4g No time-dependent `@x ||=` memo; an endpoint whose client only counts returns a count. (N/A: none added)
- [ ] §RL5a No unbounded work in a request; a cap has a clear message, or the work moves to a job. (N/A: nothing unbounded added)
- [ ] §RL5b No GET or HEAD writes: every read path added or touched saves, creates and enqueues nothing. (N/A: no read path)
- [ ] §RL5c Every accepted attribute has a defined result for present, `null`, `""` and missing, traced (or run) through coercion, validation and the write. (N/A: no attribute added or its handling unchanged)
- [ ] §RL5d HTTP verb matches effect. (N/A: no new endpoint)
- [ ] §RL5e A write that replaces a set of links (`tag_ids = [...]`) checks the caller's access to every id it removes as well as every id it adds, and a spec removes one the caller can't reach. A check over `ids - current_ids` alone FAILS. (N/A: no set-replacing write)
- [ ] §RL6 Stored values: when the diff renames, merges or retires a stored value or adds a backfill, every box in `references/backfills.md` was walked. (N/A: no enum, status constant, column meaning or backfill changed)
- [ ] §RL7a N+1 specs use the app's detector over three records, and one covers a route that did not ask for the fix. (N/A: no N+1 fix)
- [ ] §RL7b A bug-fix spec builds data the way the app writes it. (N/A: not a bug fix)
- [ ] §RL7c Mutation-checked: each claimed behaviour broken in turn failed a specific spec, and the tree was restored clean. (N/A: diff adds no behaviour)
- [ ] §RL7d `db/schema.rb` diff holds only the intended change. (N/A: `db/` untouched)
- [ ] §RL8 New code acts on the subject of its home: a route, method or constant that only borrows its home's inputs sits where its subject lives. (N/A: nothing added)

Examples and edge cases per box: references/detail.md (read when a box is unclear).

## Sweeps

The citation map, run first: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/added-lines.sh <diff-file>`.

The rails gate's receipts are greps over the added lines of `<diff-file>` for the patterns its boxes name (§RL2, §RL3c, §RL3e, §RL4a), each stated with its hit count and a verdict per hit.
