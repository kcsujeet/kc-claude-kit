---
name: kc-ready-for-human-review
description: "Is this change ready for a human reviewer? Confirms the self-correct record matches the content, grades the hand-off and PR body, runs CI's commands, writes the receipt the guards check. Use on \"ready for review\" or when a guard blocks a hand-off."
---

# Ready for human review

Answers one question: is this change ready for a human reviewer? It does not review the code (`kc-gates:kc-self-correct` does, and records the content it reviewed); it confirms that record matches the content being handed over, grades the hand-off and writes the receipt `guard-hand-off.sh` and `guard-merge.sh` check. A PR merges only on a clean receipt. Full wording of each step: `${CLAUDE_PLUGIN_ROOT}/skills/kc-ready-for-human-review/references/detail.md` (read the matching `### ` section when a line here is unclear).

## Size

1. `change-class.sh` classes the change `prose_small` or `code_small` (`pass-size.sh` small, no `risk:` line): no record, no receipt.

## Confirm the review

1. Hash the content being handed over: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/tree-hash.sh" HEAD`.
2. `bash "${CLAUDE_PLUGIN_ROOT}/scripts/self-correct-record.sh" check <tree>` prints the record: rounds, open, size, pass folder. No record, or an unclean one: run `kc-gates:kc-self-correct` on the content (on the delta, when it changed since a record), then come back.
3. Open findings in the record go to the person with the fix, as decisions.

## Hand-off

1. Write the PR title (first line), a blank line and the body to `.git/kc-pr/<branch>.md`.
2. Grade each box of `.claude/hand-off-checklist.md` against the PR as it will be read (body file, ticket, paired PRs). Save `checklist.md` in the pass folder: the boxes with `[PASS]`, `[FAIL]` or `[N/A: reason]`. No such file: check against the repo's PR template and say so. A FAIL is fixed or goes to the person.
3. Add a **Risk** section to the description: Impact (from the `risk:` lines), Rollback (two-way or one-way door), Detection (how a failure shows). High impact with a one-way door, or a failure nothing reports, goes to the person with the fix.
4. Run CI's commands locally (`.claude/ci-commands`, else the test command plus lint and typecheck); fix a failure like a finding, through `kc-self-correct`.

## Receipt

1. `ready-receipt.sh write <sha> --preflight --rounds <k> --open <n> --pass <pass>` first; it lists every missing item and writes nothing (`ready-receipt.sh help` prints the line formats).
2. Write the receipt, from the repo root:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/ready-receipt.sh" write <full-sha> --rounds <1-3> --open <count> --size <small|full> --pass <pass-folder> [--scope-approved "<the person's words>"] [--verdicts <pass-folder>/checklist.md] [--task <ticket key>]
```

3. Open the PR from the body file (`--title` its first line, `--body-file` the rest); check `gh pr view --json headRefOid` is the commit. A stuck PR head: `gh api -X PATCH repos/<owner>/<repo>/pulls/<n> -f base=<base>`. Retry a server-side push error once.
4. Never write a block yourself to get past the receipt; run what is missing.
5. Content changed since the receipt (a fix, a reviewer's change): `kc-self-correct` on the delta, then `ready-receipt.sh write <new-sha> --rounds <k>`. `--after <receipt-sha>` only keeps the PR in review. Answer every PR comment, bot reviewers included.
6. The person says skip: prefix the command with `KC_READY_SKIP=1`. Never on your own.
7. A guard still needs the person's words: `approvals-needed.sh` lists them; ask in one message.

## After the reviewer comments

1. Sort each comment: covered (a rule said it: fix the check that missed it), new (a lesson with a box), disagreement (settled once into `.claude/review-conventions.md`).
2. Check a requested change like your own before writing it.
3. Record the round: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/review-tally.sh" add <pr-url> <covered> <new> <disagreement>`; `review-tally.sh report` totals per month; `review-tally.sh reverts <repo-dir> [<since>]` lists reverts.

## Report

```
### Ready for human review: <PR title>
**Head:** `<short-sha>` · **Content:** `<short tree hash>` · **Size:** <small|full> · **Rounds:** <k> · **Open:** <n>
**Risk:** <impact> · <two-way|one-way door> · <how a failure shows>

| Check | Result |
|-------|--------|
| Self-correct record | <clean | open findings> for this content |
| Hand-off checklist | <n> PASS · <n> N/A · <n> FAIL |
| CI's commands | <which ran, passing or not> |
| Receipt | <written | refused: why> |
```

## Checklist

- [ ] Tick each box, then say PASS, FAIL (file:line) or N/A (why). Detail per box: `references/detail.md`.

- [ ] §H11 A `kc-self-correct` record matches the content being handed over (its tree hash), and the receipt names that tree. Held by `ready-receipt.sh`, `guard-hand-off.sh`. (N/A: a small change needing no receipt)
- [ ] §H5 Changes since the receipt went through `kc-self-correct` on the delta; a reviewer's change was checked like your own; every PR comment has a reply (`ready-receipt.sh`). (N/A: nothing changed since the receipt)
- [ ] §H7 Every hand-off box has a verdict (`--verdicts`); no hand-off action ran while one was FAIL or unrecorded. Held by `guard-hand-off.sh`, `guard-tracker-transition.sh`. (N/A: no hand-off checklist)
- [ ] §H10 The PR description is short and readable: what changed and why, how to test, evidence; no process notes, no word counts, no restating the diff. (N/A: never)
- [ ] §H9 Screenshots and any video are in the PR description, uploaded with `gh pr create --attach <file>` or `gh pr edit <n> --attach <file>`; `gh --version` checked first. (N/A: no visual change)
