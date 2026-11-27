# kc-shape-the-change detail

### Full wording before the steps rewrite

The whole `SKILL.md` body as it was, moved verbatim (headings two levels down). Read the part a step or box points to.

### Shape the change

Between "assess" and "build" in `kc-conventions:kc-do-a-task`. Code can be right line by line and be the wrong shape; review rounds then fix lines and the shape stays. Write the design and compare it with another one before any code, so the person approves a shape and not a diff.

#### Procedure

1. **Write the shape file** at `$(git rev-parse --git-path kc-shape)/<branch>.md` in the checkout the work happens in (nothing is committed). Copy the template below and fill each box.
2. **Facts first.** A fact the product needs (a mode, a setting, a preference) is stored once, as itself, where it is decided. Deriving it at read time from other fields is a second shape to compare, not the default: every reader then repeats the rule. Examples: an order's fulfilment mode inferred from a boolean plus an options blob, instead of its own field; a storefront's tax setting inferred from which rates exist; a notification preference inferred from three unsubscribe flags; a screen's mode inferred from the URL and a cached value.
3. **Owners.** Name the unit that owns each job (store it, validate it, show it). Two units that both decide the same thing is a finding to fix now.
4. **Compare at least two shapes** on fewer mechanisms, fewer places that know the same fact, less code. Pick one and say why. A shape the person would not choose is not a comparison.
5. **Existing behaviour and data:** what moves (migration, backfill) and how live callers keep working while it does (compatibility, old and new side by side, removal last).
6. **Rollout, one line per change:** flag yes or no, the reason, who decided. A flag is a product rollout decision (who sees it, when, with what announcement) and the person's to make. Changes to existing behaviour may go behind one for that reason. A flag is never cover for a data or deploy gap (rows not yet backfilled, code that must ship before the migration): fix those with compatibility and order. Examples: a flag so a new notification default reaches customers gradually (product reason); a flag that hides a new column's readers until a backfill finishes (gap, so no flag: make the readers tolerate empty rows).
7. **Failure modes:** each way it breaks and the signal that would show it (an error, a count, a log line).
8. **Approval.** Show the person the shape and quote their approval words. Then run `bash "${CLAUDE_PLUGIN_ROOT}/skills/kc-shape-the-change/scripts/check-shape.sh" <file>` and build.
9. **Reopen it when fixes stack.** A second review finding or fix for the same unit for the same reason means the shape is wrong: update the file, compare again, get approval, then change code.

#### A trivial change

A change with no new storage, no new unit and no behaviour move (a typo, a copy change, a bug fix inside one unit) needs no shape. Declare it as the shape file's first line; the guard and the check accept the file and a reviewer reads the line:

```
trivial: no new storage, no new unit, no behaviour move: fixes the rounding of one displayed total
```

#### Guard

kc-conventions' `guard-shape.sh` denies an edit or write (Edit, Write, MultiEdit, a shell redirect, `sed -i`, `tee`, `cp`, `mv`, a REPL `write(` or `edit(` call) to a non-test source file on a branch whose shape file is missing or fails `check-shape.sh`, with the problems in the reason. The default branch, a detached head, test files and files that are not source code are never blocked. Shell and REPL detection is best effort: it reads the command text, not what a script it starts will write.

#### The shape file

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

#### Gate checklist

The shape file's boxes, in order; `check-shape.sh` grades them and `guard-shape.sh` holds source edits until the file passes (or declares the change trivial). (N/A for all: the change adds no source code)

- [ ] §SH1 Requirement: what the change must do, in the person's terms.
- [ ] §SH2 Facts: where each fact lives, its source of truth, stored as itself or derived, and why.
- [ ] §SH3 Owners: which unit owns which job; no two units decide the same thing.
- [ ] §SH4 Shapes: at least two compared on fewer mechanisms, fewer places that know the same fact and less code, with the pick and why.
- [ ] §SH5 Existing behaviour and data: how they move (migration, backfill) and how live callers keep working meanwhile.
- [ ] §SH6 Rollout: a flag line per change (yes or no, the reason, who decided); a reason that only covers a data or deploy gap fails.
- [ ] §SH7 Failure modes: each way it breaks and the signal that shows it.
- [ ] §SH8 Approval: the person's words, quoted.

#### Approach checklist

Asked before writing or reviewing any code, with or without a shape file; not boxes of the shape file. (N/A: the change adds no source code)

- [ ] §SH9 Asked whether this is the best and simplest way, assuming a simpler one exists: one mechanism instead of two, an existing tool, doing less.
- [ ] §SH10 Sketched one other shape and compared it before going line by line: better in a way the person would care about, tell them with its cost; still delivers the ask, take it and say so; changes the ask, the choice is theirs.
- [ ] §SH11 The first idea, yours included, was doubted: code can be right line by line and the wrong shape. In a review, a materially simpler design is the first finding and the line findings it deletes go under it.
- [ ] §SH12 Used the access already had: before starting work somewhere new (a folder, permission, sign-in, second tool), checked whether what is permitted does it, reaching files by path.