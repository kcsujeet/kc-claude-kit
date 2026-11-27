---
name: kc-shape-the-change
description: Use after kc-assess and before code that stores something new, adds a unit or mode, or moves behaviour or data: write the shape, compare two, get approval.
---

# Shape the change

Between "assess" and "build" in `kc-conventions:kc-do-a-task`. Code can be right line by line and the wrong shape. Write the design and compare it with another before any code, so the person approves a shape and not a diff. Examples and full wording: `references/detail.md`.

## Steps

1. Write the shape file at `$(git rev-parse --git-path kc-shape)/<branch>.md` in the checkout the work happens in (nothing is committed). Copy the template below and fill each box.
2. Facts first: a fact the product needs (a mode, a setting, a preference) is stored once, as itself, where it is decided. Deriving it at read time is a second shape to compare, not the default.
3. Owners: name the unit that owns each job (store, validate, show). Two units that decide the same thing is a finding to fix now.
4. Compare at least two shapes on fewer mechanisms, fewer places that know the same fact, less code. Pick one and say why; a shape the person would not choose is not a comparison.
5. Existing behaviour and data: what moves (migration, backfill) and how live callers keep working meanwhile (old and new side by side, removal last).
6. Rollout, one line per change: flag yes or no, the reason, who decided. A flag is a product rollout decision; never cover for a data or deploy gap (fix those with compatibility and order).
7. Failure modes: each way it breaks and the signal that shows it (an error, a count, a log line).
8. Show the person the shape and quote their approval words. Run `bash "${CLAUDE_PLUGIN_ROOT}/skills/kc-shape-the-change/scripts/check-shape.sh" <file>`, then build.
9. Reopen it when fixes stack: a second finding or fix for the same unit for the same reason means the shape is wrong. Update the file, compare again, get approval, then change code.
10. A change with no new storage, no new unit and no behaviour move (a typo, a copy change, a fix inside one unit) needs no shape. Declare it as the file's first line:

```
trivial: no new storage, no new unit, no behaviour move: fixes the rounding of one displayed total
```

- `guard-shape.sh` denies an edit or write (Edit, Write, MultiEdit, a shell redirect, `sed -i`, `tee`, `cp`, `mv`, a REPL `write(` or `edit(` call) to a non-test source file on a branch whose shape file is missing or fails `check-shape.sh`. The default branch, a detached head, test files and non-source files are never blocked.

## The shape file

```markdown
# Fulfilment mode on orders

- [x] §SH1 requirement: staff choose pickup or delivery per order, and reports and emails must follow that choice.
- [x] §SH2 facts: the fulfilment mode is decided at checkout and stored on the order as its own field; the delivery address is only read when the mode is delivery.
- [x] §SH3 owners: the order model owns the mode and its allowed values; the checkout form only sets it; reports, emails and the API read it.
- [x] §SH4 shapes:
  - shape A: derive the mode at read time from the old is-delivery boolean plus the options blob.
  - shape B: add a mode column defaulting to the old behaviour and have every reader ask it.
  - pick: B, because every reader asks one field, while A copies the same rule into reports, emails and the API.
- [x] §SH5 existing behaviour and data: existing orders get the mode from the boolean in a backfill; readers treat an empty mode as the boolean's value until the backfill finishes; the boolean is removed in the last phase.
- [x] §SH6 rollout:
  - flag: the mode field, its readers and the backfill | no | reason: readers tolerate empty rows, so there is no data gap to hide | decided-by: shop owner
  - flag: the new pickup option shown at checkout | yes | reason: customers get it gradually, starting with one pilot storefront | decided-by: shop owner
- [x] §SH7 failure modes:
  - failure: an order saved with no mode after the backfill | noticed-by: a count of orders with an empty mode, alerted daily
  - failure: a reader still using the boolean | noticed-by: the report totals differ from the order list in the tests
- [x] §SH8 approval: "shape B, ship it behind the pilot flag" (shop owner, in chat)
```

## Gate checklist

- The shape file's boxes, in order; `check-shape.sh` grades them and `guard-shape.sh` holds source edits until the file passes. (N/A for all: the change adds no source code)

- [ ] §SH1 Requirement: what the change must do, in the person's terms.
- [ ] §SH2 Facts: where each fact lives, its source of truth, stored as itself or derived, and why.
- [ ] §SH3 Owners: which unit owns which job; no two units decide the same thing.
- [ ] §SH4 Shapes: at least two compared on fewer mechanisms, fewer places that know the same fact and less code, with the pick and why.
- [ ] §SH5 Existing behaviour and data: how they move (migration, backfill) and how live callers keep working meanwhile.
- [ ] §SH6 Rollout: a flag line per change (yes or no, the reason, who decided); a reason that only covers a data or deploy gap fails.
- [ ] §SH7 Failure modes: each way it breaks and the signal that shows it.
- [ ] §SH8 Approval: the person's words, quoted.

## Approach checklist

- Asked before writing or reviewing any code, with or without a shape file. (N/A: the change adds no source code)

- [ ] §SH9 Asked whether this is the best and simplest way, assuming a simpler one exists: one mechanism instead of two, an existing tool, doing less.
- [ ] §SH10 Sketched one other shape and compared it first: better in a way the person would care about, tell them with its cost; changes the ask, the choice is theirs.
- [ ] §SH11 Doubted the first idea, yours included: right line by line can be the wrong shape; in a review a materially simpler design is the first finding.
- [ ] §SH12 Used the access already had: before work somewhere new (a folder, permission, sign-in, second tool), checked whether what is permitted does it, reaching files by path.
