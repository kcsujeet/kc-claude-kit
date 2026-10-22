# Renaming, retiring or backfilling a stored value

Read in full by the rails gate when the diff changes an `enum` member, a status, reason, type or kind constant, a column's meaning or type, or writes a backfill. Failing any box here fails §RL6.

**Trigger sweep:** grep the added lines for `enum :`, changed constants, `update_all`, `update_columns`, `in_batches`, `execute`, `UPDATE`, and every file under `db/migrate/` and the app's task folder.

## Checklist

- [ ] §RL6.1a Every write site of the old value is enumerated by grep, not just the one the diff touches; count and each `file:line` stated. One symbol set by three branches carries three meanings. (N/A: no value retired)
- [ ] §RL6.1b The new name is checked against each of those meanings, not only against the diff's own branch, where it is true by construction. (N/A: no rename)
- [ ] §RL6.1c If the new name is not true for every case, there is no blanket rename: the backfill re-derives per row from data that still exists, or falls back to the vaguest honest value (`unknown`, `other`, nil). Vague beats wrong. (N/A: new name true for every case)
- [ ] §RL6.1d The state before the backfill finishes is confirmed, not assumed: reading a value no longer in a Rails enum returns nil, and what the UI does with nil is stated. (N/A: nothing left unbackfilled)
- [ ] §RL6.1e A real value is written rather than the old one left in place; an unmapped value drops the row out of every filter on that column. (N/A: no rows carry the old value)
- [ ] §RL6.2a The backfill is a batched, resumable task, not a migration, whenever the update is unbatched, the filtered column has no usable index, or the table's size is unknown. (N/A: no backfill)
- [ ] §RL6.2b Index usability is checked by leading column: an index on `(org_id, reason)` does nothing for a bare `reason =` filter. (N/A: no filtered backfill)
- [ ] §RL6.2c The PR says the task must be run, since nothing runs it automatically. (N/A: no task added)
- [ ] §RL6.2d A relabel uses `update_columns`, so `updated_at` ordering is not disturbed, and a comment says why. (N/A: not a relabel)
- [ ] §RL6.3a Every writer of the source column is enumerated in every repo that writes it (backend writers and frontend payload builders), with the shape each writes. (N/A: backfill copies the column unchanged)
- [ ] §RL6.3b Each value the backfill classifies on is checked for collisions: no other writer can produce the same stored value with a different meaning. (N/A: backfill does not branch on the value)
- [ ] §RL6.3c A disagreement count was run against production data: rows where the old and new reading differ, sampled against their source records. (N/A: no reinterpretation)
- [ ] §RL6.3d A refinement is scored against the real rows it touches, as fixes versus breaks, before it is adopted. (N/A: no refinement)

## Why

A retired value is usually overloaded. A status set by three code paths for three reasons, mapped onto a new name derived from the one path being edited, puts a confident false label on rows from the other two. Ask what the old value proved, not what the new one is called; the check has to start from a grep of every write site.

A backfill inside a migration holds row locks on every matched row for one transaction and blocks the deploy while it runs. A batched task throttles, resumes and runs on someone's schedule. A data backfill is not DDL; its risk is long-held row locks, and its mitigation is batching.

A backfill that guesses a row's meaning from its stored value is only as good as its list of writers. A timestamp at exactly midnight UTC may mean "a picked date" from one writer and "an event ending at 4 PM in Vancouver" from another. Count disagreements rather than the size of the ambiguous bucket, and score any rule tweak on the real rows before trusting it.
