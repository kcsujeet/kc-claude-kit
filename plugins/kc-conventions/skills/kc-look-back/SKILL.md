---
name: kc-look-back
description: Use when a task is handed off (your pull request merged or with its reviewer, or a review you did closed): list all feedback from the record, give each a verdict, write the lessons as one batch. Also for where a lesson belongs.
---

# Look back, then write the lessons

Step 6 of the working agreement's "Order of work on a task".

## Procedure

1. **Check the previous batch is live.** An agreed lesson is not done until it is live, so first check that the previous batch's lesson pull requests merged. One closed unmerged put its rules in front of no one.
2. **Note feedback as it arrives, write no rule yet.** Act on each correction, review comment and QA finding in the work. A lesson written mid-task is often widened, merged or contradicted by the next piece of feedback, and writing it pulls the task off course.
3. **Start once the task is handed off** (your own pull request merged or with its reviewer), without being asked. Until the look-back is done it is the first thing listed whenever the person asks what is next. kc-gates reminds after a command that merges or approves a pull request.
4. **Reviewing someone else's work ends the same way,** once the review closes (approved, merged or dropped). Your own misses across its rounds are the feedback: a finding the author fixed in the one place it named, a suggestion that caused a later round's finding, a gap a later round found that an earlier one could have.
5. **Start from a list, not from memory.** Recall keeps the corrections that stood out and drops the rest, the same miss as a review that never lists its units. Run kc-gates' `feedback-ledger.sh list` over the session's transcript (`~/.claude/projects/<working directory, / as ->/<session id>.jsonl`), with the review comments and QA rows as `--extra` files, one per line. It lists every message the person typed, every answer they gave, every call they rejected or interrupted and every message another session relayed.
6. **Give each item one verdict in a ledger:** a lesson and the rule id it became; already covered, with why it was still missed and what catches it now; a one-off call; or not feedback. Run `feedback-ledger.sh check`, which fails on an item with no verdict and on a lesson whose rule the lesson pull request does not add. An item covered by a rule that was still missed usually means the rule needs a box or a trigger, which is itself a lesson.
7. **The bar for a lesson** (and for any follow-up work the work produced: fail-safe findings a review pass left open, a fix for what a fix introduced, friction with your own tools): it came from the person, a human reviewer or real harm (not from your own gates or tools on your own change), happened twice or once at real cost, is smaller than the problem, and no rule already says it (when one does, widen that one). The rest gets its verdict and stops there.
8. **Loop-stop rule.** When the thing to fix came from your last fix, or findings stop shrinking between rounds, stop and say so: every round on new code finds something in it.
9. **Write the lessons as one batch,** after the list is judged, not one pull request per comment.

## Placing a lesson by layer

Put a lesson at the first layer that holds it:

1. **A check:** a lint rule, type, test or script with a helpful error. It fails without the lesson, so nothing relies on being remembered.
2. **A guard:** a hook or script that runs at the moment of action. It holds only where every way in passes it: a CI check the default branch requires before merge, and a local hook for commits made straight to that branch. Examples: a size budget in CI on a branch that merges with red checks; a clone that commits to the main branch and never runs CI.
3. **A path-scoped rule:** loads only when the files it covers are opened.
4. **A skill:** a procedure or recipe, loaded when its description matches.
5. **An always-on line:** only a short must or trigger that names its skill. Always-on text is paid for by every session.

## Examples

- The loop: a lesson pull request whose review left fail-safe findings, fixed in a second pull request whose review found defects in those fixes, then a third built from friction met while running the second's checks.
- A look-back that listed the agent's own slips and none of the QA report's rows.
- A look-back that kept the two corrections that came with an explanation and dropped the one-word ones ("no", "why?").
- A look-back that missed a rejected tool call that redirected the whole approach.
