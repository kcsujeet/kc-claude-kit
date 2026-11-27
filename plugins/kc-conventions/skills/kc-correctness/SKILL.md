---
name: kc-correctness
description: "Correctness conventions for source files in any language: logic errors, unhandled edge cases (empty, null, zero, timezone), data not matching its type at a boundary, regressions of fixed bugs. Use when writing or reviewing conditions, loops, state, hooks or boundary data, or hunting bugs."
user-invocable: false
paths:
  - "**/*.{ts,tsx,js,jsx,mjs,cjs,rb,py,swift,go,java,kt,php,cs,rs}"
---

# Correctness

## Contents

- Review checklist
- Sweeps

## Review checklist

Tick every box for each construct you add or change. Report each: PASS, FAIL (file:line) or N/A (why).

- [ ] §B1 Logic is right: no off-by-one, wrong operator, inverted condition, stale closure or state, or wrong dependency array.
- [ ] §B2 Every added path handles empty, null, zero and boundary values and each record lifecycle state (archived, deleted, expired), content-shape edge cases, and the configured timezone (see §B2).
- [ ] §B3 Values crossing a boundary match their declared type at runtime; a new caller of an existing unit is checked against its other callers' defaults and normalization (see §B3).
- [ ] §B4 The diff does not reintroduce a fixed bug (changelog, dev logs, `git log -S <symbol>` checked), and a merge, rebase or squash keeps every side's changes (see §B4).
- [ ] §B5 Every submitted field is traced from input through transform and payload to the receiver's handling, for each state (set, changed, cleared, untouched, invalid); no trace FAILS.
- [ ] §B6 A new reference between modules closes no load cycle through definition-time work (inheritance, registry, decorator) unless it is lazy; the evidence follows the back references.
- [ ] §B7 Every count, total or summary uses the same filter as its list (soft-deleted, archived, other-tenant alike); the evidence names both queries. (N/A: no count or summary added or changed)
- [ ] §B8 Every use of a changed function, hook, component, field, prop, route or column gets a verdict from `trace-uses.sh`, receipt `uses: <n> listed, <n> judged`; a breaking use FAILS.
- [ ] §B9 A claim about what a value holds (comment, commit message, test reasoning) was checked against every writer: class body, concerns, callbacks, factories, seeds. (N/A: no such claim)
- [ ] §B10 A bug fix names its cause as a searchable pattern, the grep run across code and tests, and a verdict per hit (fixed, safe and why, follow-up). (N/A: the diff fixes no bug)
- [ ] §B11 A client mirroring a server calculation reads each input from the record the server reads; the evidence puts both side by side. (N/A: no mirrored server calculation)
- [ ] §B12 A list shows only what the viewer can open: it applies each item's own access check server-side; the evidence names both. (N/A: no list of individually gated items)
- [ ] §B13 After a one-to-one becomes one-to-many, every accessor that picks "the" one (`first`, lowest id, `default_*`) and every fallback to it is listed with its readers.
- [ ] §B14 A guard that refuses a delete counts only related records the delete would harm; each state of the related record gets a verdict (blocks, goes with it). (N/A: no delete guard)
- [ ] §B15 A change moves only the states it is for: every state reaching a changed condition, fallback, default or validation is listed with its result before and after (see §B15).
- [ ] §B16 Every stored value (cookie, cache, URL parameter, file, row, flag) is handled in each state it can be read in: a table of states and events with `file:line` or "unhandled" (see §B16).
- [ ] §B17 A sibling or parallel path has the original's rules and guards, or a recorded decision per rule (same, differs on purpose, missing); a difference noted only in help text FAILS.
- [ ] §B18 A reliance on another unit's internal behaviour (`super`, a yielded block, a callback, a template method) names its seam or pinning test; none FAILS (see §B18). (N/A: no such reliance)

**Point, do not double-report.** A removed export or a changed shared prop shape is structure §S10. A cast asserting a type the value does not have, as syntax, is clarity §C17. Duplicated markup, dead imports, or props threaded through and never read after a refactor are simplicity §P9. A locale formatter with no explicit time zone is datetime §D7. When a bug and one of those boxes describe the same line, report it once, under the closer fit, and name the other box in the evidence.

Examples and edge cases per box: references/detail.md (read when a box is unclear).

## Sweeps

Save the diff under review to a file and run the script over it; `-` reads the diff from stdin. No other sweep is bundled for this topic.

- `added-lines.sh` (citation map): every added line as `path:line: text`, with the source line number at the head SHA. Cite every finding's line from this output or from a sweep hit, never from a position in the diff file.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/added-lines.sh" <diff-file>
  ```
