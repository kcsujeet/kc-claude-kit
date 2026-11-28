---
name: kc-do-a-task
description: Use when starting a task (a ticket, a bug, a feature, a review): the order of work from assess to look-back, and the skill that holds each step.
---

# Do a task

An expensive check whose result later work will throw away runs once, on the finished work. This skill is the only place that states the order of work; every other skill says what it does, not when. Each step names the skill that holds it; load it before doing the step.

## Order of work

1. **Assess** (`kc-conventions:kc-assess`): is the task or its code someone else's, the cause from the failing run, then cause, fix and the rules it follows.
2. **Shape** (`kc-conventions:kc-shape-the-change`): only for code that stores something new, adds a unit or moves behaviour or data.
3. **Build:** the change and its tests (lint, types, affected tests); no review fan-out or app walk yet.
4. **Self-correct** (`kc-gates:kc-self-correct`): review and QA of your own change, committed or not, with every finding fixed until clean; then the person looks at the result, and **commit locally** once they approve committing. Nothing is pushed and no pull request exists yet.
5. **Ready for human review** (`kc-gates:kc-ready-for-human-review`): confirms the review matches the committed content, grades the hand-off and writes the receipt.
6. **Push and open the pull request** from the body file, then hand it to the reviewer; then **look back** (`kc-conventions:kc-look-back`) and write the lessons as one batch, then **clean up** (`kc-conventions:kc-clean-up`).

- Delegating any of it: `kc-conventions:kc-delegate`. Stating what code or a tool does: `kc-conventions:kc-check-claims`.

## Gate checklist

- [ ] §DT1 Assessed first (`kc-assess` §AS1): the task and its code are not someone else's (`task-claims.sh <key> --repo <owner/name> --path <file>...`), cause and fix presented before any build.
- [ ] §DT2 Shaped when the change stores something new, adds a unit or moves behaviour or data (`kc-shape-the-change`). (N/A: no new storage, unit or behaviour move)
- [ ] §DT3 Build ran lint, types and affected tests only; the mistake a fix is for is named and what the fix adds is checked against it.
- [ ] §DT4 Committed locally only after the person looked at the self-corrected change and approved committing; nothing pushed before the receipt.
- [ ] §DT5 Self-correct ran once on the finished change, without asking, and left no finding open that the person did not decide (`kc-self-correct`).
- [ ] §DT6 The code-overlap check ran again before the push (`task-claims.sh ... --since <start commit>`); when the default branch or another open pull request changed that code, the person was asked first.
- [ ] §DT7 The pull request was opened ready (or as the repo wants) from the body file the hand-off wrote.
- [ ] §DT11 Ready for human review confirmed the self-correct record matches the committed content and wrote its receipt before the push (`kc-ready-for-human-review`).
- [ ] §DT8 Look-back started once handed off: previous lesson PRs checked merged, feedback listed with `feedback-ledger.sh list`, lessons written as one batch, unasked (`kc-look-back`).
- [ ] §DT9 Every step the workflow owes (look-back, cleanup, follow-up, reply, re-check) is on the visible task list until done or deferred; open steps re-read and the skill each names loaded before a hand-off.
- [ ] §DT10 Cleanup done: session-started background work stopped; files made only to hand on (a video, an export, a scratch copy) removed once the copy that matters is confirmed; files the person asked for stay.
