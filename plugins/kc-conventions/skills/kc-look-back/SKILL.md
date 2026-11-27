---
name: kc-look-back
description: Use when a task is handed off (your pull request merged or with its reviewer, or a review you did closed): list all feedback from the record, give each a verdict, write the lessons as one batch. Also for where a lesson belongs.
---

# Look back, then write the lessons

Step 6 of `kc-conventions:kc-do-a-task`. Full wording, layers and examples: `references/detail.md`.

## Steps

1. Check the previous batch's lesson pull requests merged; one closed unmerged put its rules in front of no one.
2. During the task, note feedback and act on it in the work; write no rule yet.
3. Start once the task is handed off (PR merged or with its reviewer), unasked. It stays on the visible task list until `feedback-ledger.sh check` passes. A look-back at an earlier hand-off does not cover later feedback: run it again.
4. A review of someone else's work ends the same way once it closes; your own misses across its rounds are the feedback.
5. List, don't recall: `feedback-ledger.sh list` over the session transcript (`~/.claude/projects/<working directory, / as ->/<session id>.jsonl`), with review comments and QA rows as `--extra` files, one per line.
6. Give each item one verdict in a ledger: a lesson (and the rule id it became; a check, never prose only), covered (why it was still missed, what catches it now), a one-off call, or not feedback.
7. Give each lesson line tab-separated fields: `class:<one sentence>`, `examples:<a>; <b>` (two or more unlike), `mechanism:<check|guard|path-rule|skill|always-on>`, `why-not-higher:<why>` (unless `check`), `proof:<test, eval, script or box id>`, `held-by:<test file>[::<case>]`.
8. Run `feedback-ledger.sh check --repo <checkout> --base <ref>` on every lesson PR. It fails on an item with no verdict, a lesson whose rule the PR does not add, a PR that changes no check file, and a test that still passes with the lesson's non-test changes reverted. A public repo (`public: true`) names no private client term from `~/.claude/kc-client-terms.txt`.
9. Place each lesson at the first layer that holds it: check, guard, path-scoped rule, skill, always-on line (last, short, names its skill).
10. Apply the bar: it came from the person, a human reviewer or real harm; twice, or once at real cost; smaller than the problem; no rule already says it (widen that one).
11. When the thing to fix came from your last fix, or findings stop shrinking, stop and say so.
12. Write the lessons as one batch, not one pull request per comment.
13. Tick the Gate checklist in the ledger folder's `checklist.md` (`- [x] §LBn ...`). `guard-lesson-ledger.sh` blocks `git push`, `gh pr create` and `gh pr merge` on a lesson PR until the check passes and every box is ticked.

## Gate checklist

- [ ] §LB1 The lesson's class is named without the instance's code tokens: no backticked word, identifier, unit or file name from the feedback or the fix. Held by `feedback-ledger.sh check`.
- [ ] §LB2 The ledger line climbs a ladder: `ladder:<instance> -> <mechanism> -> <class>`, asking at each step what else it would catch. Held by `feedback-ledger.sh check`.
- [ ] §LB3 Three or more unlike examples, from different areas, none sharing a token with the instance, each held as a test fixture.
- [ ] §LB4 An existing rule, script or box was widened before a new one was added (named in the PR description), or the description says why none could be.
- [ ] §LB5 The check catches the class, not only the token that bit: fixtures from unlike areas pass and fail it, and the instance's own case is one of them.
- [ ] §LB6 A correction became one imperative line in the repo file that acts on it: `CLAUDE.md` (write, run, test), `.claude/review-conventions.md` (review flags), `.claude/hand-off-checklist.md` (PR carries).
- [ ] §LB7 The line is specific to that repo; general advice goes in the portable rules, and a procedure goes in a skill the project file links to.
- [ ] §LB8 Those lines were written in the look-back with the task's other lessons and mentioned in the summary; only what auto memory would not derive is written down.
