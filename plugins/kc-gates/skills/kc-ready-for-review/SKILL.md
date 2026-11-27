---
name: kc-ready-for-review
description: "The one review pass on your own PR before a human reviewer: runs kc-code-review (which walks the change), the hand-off checklist and CI's commands, then you fix. Required by the hand-off guard. Use on \"ready for review\", \"send it to review\", \"request a review\", or when the guard blocks a hand-off."
---


# Ready for review

The one review-and-QA pass on your own PR (the QA walk is `kc-code-review`'s; this adds the hand-off checklist, fix rounds and receipt), run once on the committed local branch before its first push and before the PR exists. The reviewer should find nothing the project's rules already say. The pass converges or stops: round 1 reviews the whole change, each later round only the fixes since the round before plus every use of what they changed, each round's fixes smaller than the last, at most three rounds. A PR merges only on a clean receipt (`guard-merge.sh`). Full wording of each step: `${CLAUDE_PLUGIN_ROOT}/skills/kc-ready-for-review/references/detail.md` (read the matching `### ` section when a line here is unclear).

## When it runs

1. `change-class.sh` classes the branch `prose_small` or `code_small` (`pass-size.sh` small, no `risk:` line): no pass, no receipt.
2. Otherwise run it as soon as the work is committed, without asking; once per PR (per PR in a stack, each against its own base).
3. Run nothing while building: no `kc-code-review` fan-out or walk. Tests, lint and types as always. Order of work: `kc-conventions:kc-do-a-task`.

## Before round 1

1. `git fetch origin`, then gather: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/gather-review.sh" --branch origin/<base> --out-dir <pass>/round-1`. Never use a local base. A `BASE_STALE=` line means gather again against the ref it names.
2. Size it: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/pass-size.sh" <dir>/review.diff <dir>/changed-files.txt`. Follow `MUTATION=`; copy `SIZE=`, its reasons and its `risk:` lines into the report and the receipt (`--size`). Never override them.
3. The tree is clean and HEAD is the branch's last commit. The pass folder lives outside any checkout (`${TMPDIR:-/tmp}/kc-pass-<sha>`).
4. Write the PR title (first line), a blank line and the body to `.git/kc-pr/<branch>.md`.
5. Pick the test command: the specs covering the changed files, narrowed to seconds, plus the install command when a fresh checkout needs one.
6. When `MUTATION=run`, start `surviving-mutants.sh` on the whole diff (one run per area) with that command; give its output to the testing gate.

## Round 1

1. Run `kc-gates:kc-code-review` on the whole diff (it walks every changed behaviour; no separate QA), with fixes and mutation output as optional inputs (its Step 3). Save every returned block verbatim to `round-1/verdicts/<gate>.txt` and your `SCOPE:` block to `verdicts/scope.txt`. Note `HEAD_SHA`.
2. Grade each box of `.claude/hand-off-checklist.md` against the PR as it will be read (body file, ticket, paired PRs). Save `checklist.md`: the boxes with `[PASS]`, `[FAIL]` or `[N/A: reason]`. No such file: check against the repo's PR template and say so.
3. Add a **Risk** section to the description: Impact (from the `risk:` lines), Rollback (two-way or one-way door), Detection (how a failure shows). High impact with a one-way door, or a failure nothing reports, goes to the user with the fix.
4. Run CI's commands locally (`.claude/ci-commands`, else the test command plus lint and typecheck); fix a failure like a finding.
5. A finding that changes the shape of the change (§G5, simplicity §P16) is the user's call; if taken, drop other edits and run round 1 once more on the new code.
6. Write one line per kind of mistake the findings show (a do or don't); check every fix against it.
7. Write the fixes yourself. Sort first: fix only what lets something wrong through; `(fails safe)` and pre-existing findings go on the open list with a reason.
8. Prove dead code dead (every input state: null, undefined, empty, zero) before removing it.
9. Fix a duplication finding by consolidating to one copy.
10. Apply a gate's edits only if `bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-gate-fixes.sh" <pass>/round-1/verdicts` prints `apply`; each `write` is yours to write from its `FIX:` line.
11. Before each fix run `trace-uses.sh --symbols <names>` and give every use a verdict (breaks, changes, fine).
12. Add a test per behaviour-changing fix; put the old line back, see it fail, restore.
13. Record every finding in `<pass>/fixes.txt`: `fixed<TAB>finding<TAB>test file`, `mechanical<TAB>finding`, or `open<TAB>finding<TAB>fails safe | needs a decision | pre-existing`.
14. Ask the user only a product, scope or irreversible call, worded as `Product:`, `Scope:`, `Irreversible:` or `Intent:` (`guard-ask-product-only.sh`); keep a wider-fix approval word for word (`--scope-approved`). Settle code-style conflicts yourself and record them in `.claude/review-conventions.md`.
15. Run typecheck, lint, each fix's test and its uses' tests. Commit; HEAD moved, tree clean. Do not rebase or reset during the pass. The next `kc-code-review` round walks the fixes; regrade the checklist if the PR text changed.

## Later rounds

1. `gather-review.sh --branch <last head> --out-dir <pass>/round-<k>`, then `kc-code-review` on that delta with `select-gates.sh --later-round`. No verification agent.
2. `verify-gate-blocks.sh --later-round <pass>/round-<k> <repo>` is the verification record: save it to `verdicts/verification.txt`; put `<n> fixes re-checked`, `<n> rewrites checked`, `<n> rename-only lines kept` and a `Walk:` line per walk-item in `verdicts/checklist.txt`.
3. Save `trace-uses.sh` output as `uses.txt`, a verdict per use in `uses-verdicts.txt` (`<use line><TAB>fine|breaks|changes`); run those tests; fix as in round 1.
4. Round 3 still finding something: no round 4. Settle each in `final.txt` (`fixed`, `dismissed`, or `asked` with the user's words), then tell the user the approach.

## Receipt and push

1. `ready-receipt.sh write <sha> --preflight --rounds <k> --open <n> --pass <pass>` first; it lists every missing item and writes nothing (`ready-receipt.sh help` prints the line formats).
2. Write the receipt, from the repo root:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/ready-receipt.sh" write <full-sha> --rounds <1-3> --open <count> --size <small|full> --pass <pass-folder> [--scope-approved "<the user's words>"] [--verdicts <pass-folder>/checklist.md] [--task <ticket key>]
```

3. Push and open the PR from the body file (`--title` its first line, `--body-file` the rest); check `gh pr view --json headRefOid` is HEAD. A stuck PR head: `gh api -X PATCH repos/<owner>/<repo>/pulls/<n> -f base=<base>`. Retry a server-side push error once.
4. Never write a block yourself to get past the receipt; run what is missing.
5. Fixes after the pass: write each as in round 1, review as the next round, `ready-receipt.sh write <new-sha> --rounds <k>`. `--after <pass-sha>` only keeps the PR in review. Answer every PR comment, bot reviewers included.
6. The user says skip: prefix the command with `KC_READY_SKIP=1`. Never on your own.
7. A guard still needs the user's words: `approvals-needed.sh` lists them; ask in one message.

## After the reviewer comments

1. Sort each comment: covered (a rule said it: fix the check that missed it), new (a lesson with a box), disagreement (settled once into `.claude/review-conventions.md`).
2. Check a requested change like your own before writing it.
3. Record the round: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/review-tally.sh" add <pr-url> <covered> <new> <disagreement>`; `review-tally.sh report` totals per month; `review-tally.sh reverts <repo-dir> [<since>]` lists reverts.

## Report

```
### Ready for review: <PR title>
**Head:** `<short-sha>` · **Size:** <small|full> · **Rounds:** <k> · **Open:** <n>
**Risk:** <impact> · <two-way|one-way door> · <how a failure shows>

| Check | Round 1 | Fixes |
|-------|---------|-------|
| Code review | <n> found · <n> fails safe · <n> asked | <n> mechanical · <n> written · <n> open |
| Proof | — | <n> tests, each failed with its fix broken · lint · types |
| Lessons | <n> kinds | <n> fixes rewritten |
| Mutation | <n> mutants · <n> survived, or "no new branch" | — |
| Hand-off checklist | … | … |
| Walk (kc-code-review) | <what was walked> | <what the fixes changed> |

**Open (your call):**
- `<file>:L<n>` <finding> (<fails safe | needs a decision | pre-existing>). Fix: <one line>.
```

## Checklist

- [ ] Tick each box, then say PASS, FAIL (file:line) or N/A (why). Detail per box: `references/detail.md`.

- [ ] §H1 Rounds converge: round 1 whole diff, later rounds the fixes and their uses, each smaller, at most 3, last found nothing or open list to the user. Held by `ready-receipt.sh`, `guard-merge.sh`. (N/A: never)
- [ ] §H2 One writer: only mechanical edits (`check-gate-fixes.sh` `apply`) applied as written; every `write` was written by you. (N/A: no gate edits)
- [ ] §H3 Only what lets something wrong through was fixed; the rest is an `open` line with its reason; "pre-existing" names the check run on the base. (N/A: round 1 found nothing)
- [ ] §H4 Each behaviour fix has a test that fails when it is broken; dead code was run through every input state (null, undefined, empty) first; duplication fixed by consolidating to one copy. (N/A: no fix commits)
- [ ] §H5 Fixes after the pass were reviewed as the next round; a reviewer's change was checked like your own; every PR comment, bot reviewers included, has a reply (`ready-receipt.sh`). (N/A: nothing after the pass)
- [ ] §H7 Every hand-off box has a verdict (`--verdicts`); no hand-off action ran while one was FAIL or unrecorded. Held by `guard-hand-off.sh`, `guard-tracker-transition.sh`. (N/A: no hand-off checklist)
- [ ] §H10 The PR description is short and readable: what changed and why, how to test, evidence; no process notes, no word counts, no restating the diff. (N/A: never)
- [ ] §H9 Screenshots and any video are in the PR description, uploaded with `gh pr create --attach <file>` or `gh pr edit <n> --attach <file>`; `gh --version` checked first. (N/A: no visual change)
