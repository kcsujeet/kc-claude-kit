---
name: kc-self-correct
description: "Review and QA your own change, committed or not, and fix every finding until clean; records the content reviewed. Use on \"self-review\", \"fix what the review finds\", or when kc-do-a-task reaches it."
---

# Self-correct

Reviews your own change with `kc-gates:kc-code-review` (its gates and its QA walk) and fixes every finding, code review and QA alike, in rounds until clean. The change may be committed or still in the working tree. The reviewer after it should find nothing the project's rules already say. Round 1 reviews the whole change, each later round only the fixes since the round before plus every use of what they changed, each round's fixes smaller than the last, at most three rounds; what is left goes to the person as decisions. The record it writes is keyed on the content it reviewed (its git tree hash), so a later commit of the same content matches it. When this runs is `kc-conventions:kc-do-a-task`'s to say. Full wording of each step: `${CLAUDE_PLUGIN_ROOT}/skills/kc-self-correct/references/detail.md` (read the matching `### ` section when a line here is unclear).

## Before round 1

1. `git fetch origin`, then gather the working tree against the base, untracked files included: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/gather-review.sh" --worktree origin/<base> --out-dir <pass>/round-1`. Never a local base. A `BASE_STALE=` line means gather again against the ref it names.
2. Size it: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/pass-size.sh" <dir>/review.diff <dir>/changed-files.txt`. Follow `MUTATION=`; copy `SIZE=`, its reasons and its `risk:` lines into the report and the record (`--size`). Never override them.
3. The pass folder lives outside any checkout (`${TMPDIR:-/tmp}/kc-pass-<tree>`). Do not rebase or reset while rounds run.
4. Pick the test command: the specs covering the changed files, narrowed to seconds, plus the install command when a fresh checkout needs one.
5. When `MUTATION=run`, start `surviving-mutants.sh` on the whole diff (one run per area) with that command; give its output to the testing gate.

## Round 1

1. Run `kc-gates:kc-code-review` on the whole diff: its gates and its QA walk (every changed behaviour, no separate QA), with fixes and mutation output as optional inputs (its Step 3). Save every returned block verbatim to `round-1/verdicts/<gate>.txt` and your `SCOPE:` block to `verdicts/scope.txt`.
2. A finding that changes the shape of the change (§G5, simplicity §P16) is the person's call; if taken, drop other edits and run round 1 once more on the new code.
3. Write one line per kind of mistake the findings show (a do or don't); check every fix against it.
4. Write the fixes yourself. Sort first: fix only what lets something wrong through; `(fails safe)` and pre-existing findings go on the open list with a reason. QA findings are fixed like code-review findings.
5. Prove dead code dead (every input state: null, undefined, empty, zero) before removing it.
6. Fix a duplication finding by consolidating to one copy.
7. Apply a gate's edits only if `bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-gate-fixes.sh" <pass>/round-1/verdicts` prints `apply`; each `write` is yours to write from its `FIX:` line.
8. Before each fix run `trace-uses.sh --symbols <names>` and give every use a verdict (breaks, changes, fine).
9. Add a test per behaviour-changing fix; put the old line back, see it fail, restore.
10. Record every finding in `<pass>/fixes.txt`: `fixed<TAB>finding<TAB>test file`, `mechanical<TAB>finding`, or `open<TAB>finding<TAB>fails safe | needs a decision | pre-existing`.
11. Ask the person only a product, scope or irreversible call, worded as `Product:`, `Scope:`, `Irreversible:` or `Intent:` (`guard-ask-product-only.sh`); keep a wider-fix approval word for word (`--scope-approved`). Settle code-style conflicts yourself and record them in `.claude/review-conventions.md`.
12. Run typecheck, lint, each fix's test and its uses' tests. The fixes stay in the working tree: this skill commits nothing.

## Later rounds

1. `gather-review.sh --worktree origin/<base> --since-tree <previous round's TREE> --out-dir <pass>/round-<k>`, then `kc-code-review` on that delta with `select-gates.sh --later-round`, walking again what the fixes touched. No verification agent.
2. `verify-gate-blocks.sh --later-round <pass>/round-<k> <repo>` is the verification record: save it to `verdicts/verification.txt`; put `<n> fixes re-checked`, `<n> rewrites checked`, `<n> rename-only lines kept` and a `Walk:` line per walk-item in `verdicts/checklist.txt`.
3. Save `trace-uses.sh` output as `uses.txt`, a verdict per use in `uses-verdicts.txt` (`<use line><TAB><fine|breaks|changes>`); run those tests; fix as in round 1.
4. Round 3 still finding something: no round 4. Settle each in `final.txt` (`fixed`, `dismissed`, or `asked` with the person's words), then tell the person the approach.

## Record

1. `bash "${CLAUDE_PLUGIN_ROOT}/scripts/self-correct-record.sh" write --rounds <1-3> --open <n> --size <small|full> --pass <pass>`. It keys the record on the working tree's content and refuses when the content changed after the last round.
2. Content changed since the record (a fix, a reviewer's change, a squash that alters it): run this skill again on the delta, as a later round.
3. Leftovers go to the person: each open finding with its reason and a one-line fix.

## Report

```
### Self-correct: <change title>
**Content:** `<short tree hash>` · **Size:** <small|full> · **Rounds:** <k> · **Open:** <n>

| Check | Round 1 | Fixes |
|-------|---------|-------|
| Code review | <n> found · <n> fails safe · <n> asked | <n> mechanical · <n> written · <n> open |
| QA walk | <what was walked> | <what the fixes changed> |
| Proof | — | <n> tests, each failed with its fix broken · lint · types |
| Lessons | <n> kinds | <n> fixes rewritten |
| Mutation | <n> mutants · <n> survived, or "no new branch" | — |

**Open (your call):**
- `<file>:L<n>` <finding> (<fails safe | needs a decision | pre-existing>). Fix: <one line>.
```

## Checklist

- [ ] Tick each box, then say PASS, FAIL (file:line) or N/A (why). Detail per box: `references/detail.md`.

- [ ] §SC1 Rounds converge: round 1 whole diff, later rounds the fixes and their uses, each smaller, at most 3, last found nothing or an open list. Held by `self-correct-record.sh`, `ready-receipt.sh`. (N/A: never)
- [ ] §SC2 One writer: only mechanical edits (`check-gate-fixes.sh` `apply`) applied as written; every `write` was written by you. (N/A: no gate edits)
- [ ] §SC3 Only what lets something wrong through was fixed, QA findings included; the rest is an `open` line with its reason; "pre-existing" names the check run on the base. (N/A: round 1 found nothing)
- [ ] §SC4 Each behaviour fix has a test that fails when it is broken; dead code was run through every input state (null, undefined, empty) first; duplication fixed by consolidating to one copy. (N/A: no fixes)
- [ ] §SC5 The record names the content reviewed (the tree hash), not a commit, and the last round read that content. Held by `self-correct-record.sh`. (N/A: never)
