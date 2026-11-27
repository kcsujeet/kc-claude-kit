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

- [ ] §RL1 Done the way similar code does it: for each changed Ruby file the evidence names ~10 similar files per layer, their pattern and the differences; none named FAILS (see §RL1).
- [ ] §RL2 Rails conventions: path matches class, conventional pluralisation, every new association declares `dependent:`, a repeated or named filter is a `scope`, callbacks are documented ones.
- [ ] §RL3a Layers: each piece of work sits in the layer similar code puts it in; no controller building, saving or validating inline where similar controllers delegate.
- [ ] §RL3b One check, one place: no rule checked twice (validator or contract, then the write) unless the second runs under a lock and a comment says so. (N/A: no validation or guard added)
- [ ] §RL3c No dead hooks or options: every override point, callback and option added is used today; enumerate added `option :`, `attr_reader`, and methods that only call `super`. (N/A: none added)
- [ ] §RL3d Bulk writes: every `insert_all|upsert_all` has `unique_by` and deduped input. (N/A: no bulk write)
- [ ] §RL3e Races: every check-then-act on shared state takes its lock or transaction before the check, or the race is stated; enumerate `exists?|lock|with_lock|first_or_create`.
- [ ] §RL4a Per-record reads: every added `sum|count|average|any?|exists?|pluck` reached per record is classified (walks loaded rows vs queries); a querying one has a bulk pass. (N/A: none added)
- [ ] §RL4b A bulk pass sits at a seam every caller passes and is named for what it does; callers that still miss it are named. (N/A: no bulk pass)
- [ ] §RL4c Every added or touched computed serializer attribute was checked for per-record queries. (N/A: no serializer touched)
- [ ] §RL4d The client asks for what it needs: a serializer attribute belongs to its own model (no `object.store.currency`); expose it on that model's serializer and have the client include it.
- [ ] §RL4e Params handed to a serializer or view carry data, not a decision precomputed for one consumer (`signed_in: customer.present?`); pass the record. (N/A: no serializer or view params added)
- [ ] §RL4f Which records the client gets is the client's filter: no serializer drops records by status, flag or context param (`object.events.reject(&:archived?)`); the client sends the filter.
- [ ] §RL4g No time-dependent `@x ||=` memo; an endpoint whose client only counts returns a count. (N/A: none added)
- [ ] §RL5a No unbounded work in a request; a cap has a clear message, or the work moves to a job. (N/A: nothing unbounded added)
- [ ] §RL5b No GET or HEAD writes: every read path added or touched saves, creates and enqueues nothing. (N/A: no read path)
- [ ] §RL5c Every accepted attribute has a defined result for present, `null`, `""` and missing, traced or run through coercion, validation and the write.
- [ ] §RL5d HTTP verb matches effect. (N/A: no new endpoint)
- [ ] §RL5e A write replacing a set of links (`tag_ids = [...]`) checks access to every id it removes as well as adds, and a spec removes one the caller cannot reach. (N/A: no set-replacing write)
- [ ] §RL6 Stored values: when the diff renames, merges or retires a stored value or adds a backfill, every box in `references/backfills.md` was walked.
- [ ] §RL7a N+1 specs use the app's detector over three records, and one covers a route that did not ask for the fix. (N/A: no N+1 fix)
- [ ] §RL7b A bug-fix spec builds data the way the app writes it. (N/A: not a bug fix)
- [ ] §RL7c Mutation-checked: each claimed behaviour broken in turn failed a specific spec, and the tree was restored clean. (N/A: diff adds no behaviour)
- [ ] §RL7d `db/schema.rb` diff holds only the intended change. (N/A: `db/` untouched)
- [ ] §RL8 New code acts on the subject of its home: a route, method or constant that only borrows its home's inputs sits where its subject lives. (N/A: nothing added)

Examples and edge cases per box: references/detail.md (read when a box is unclear).

## Sweeps

The citation map, run first: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/added-lines.sh <diff-file>`.

The rails gate's receipts are greps over the added lines of `<diff-file>` for the patterns its boxes name (§RL2, §RL3c, §RL3e, §RL4a), each stated with its hit count and a verdict per hit.
