---
name: kc-ready-for-review
description: The one review-and-QA pass on your own PR before it goes to a human reviewer. Runs kc-code-review, the project's hand-off checklist and QA, fixes what they find, re-reviews once, and hands whatever is still open to the user instead of looping; at most two rounds. Ends in a receipt for the head commit, which the kc-gates hand-off guard requires before `gh pr ready`, a ready `gh pr create` or adding a reviewer. Use when work is about to go to review ("ready for review", "send it to review", "request a review", "move the ticket to review"), or when the guard blocks a hand-off. Not after each commit or push.
---

# Ready for review

The reviewer should find nothing the project's rules already say. This pass is where those rules are applied: once per PR, right before a person reviews it, never per commit or push.

## When it runs

- **Once, at hand-off:** before marking a PR ready, opening it ready, requesting a reviewer, or moving its ticket to review. For a stack, once per PR, each against its own base.
- **Not before:** commits and pushes on the way there run nothing. Run tests and lint as you work, as always.
- **Again only after a reviewer's round** that changed the code, on the new head.

## The pass

### Round 1

1. **Review the code:** run `kc-gates:kc-code-review` on the PR's whole diff. It includes the project-conventions gate, which grades the repo's own `.claude/review-conventions.md`.
2. **Check the hand-off:** grade every box in the repo's `.claude/hand-off-checklist.md` against the PR as it will be read, not the diff: its title and description, the linked ticket, the paired or stacked PRs, the flags and tasks it names. No such file: check the description against the repo's PR template and say so.
3. **QA:** for a change a person sees, walk it in the running app with `kc-verify:kc-ui` and the project's QA rules, every state the change reaches. For one nobody sees, run the specs that cover it and exercise the endpoint, job or admin screen it changed.
4. **Fix everything found** in one go. A finding that needs a decision (two rules disagree, the fix changes behaviour the ticket didn't ask for, the rule looks wrong for this case) is asked, not fixed.

### Round 2

5. **Re-review once:** the fixes are new code, so run steps 1 and 2 again on the whole diff at the new head, and QA again only what the fixes touched.
6. **Stop.** Fix nothing further in this pass. Each finding still open goes to the user as one line with its proposed fix; the user picks.

When round 1 finds nothing, there is no round 2.

### Receipt

7. Push, then write the receipt for the head commit the PR now shows:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/ready-receipt.sh" write <full-sha> --rounds <1|2> --open <count>
   ```

8. **Fixes the user picks** from the open list: apply them, run the specs and lint they touch, push, and write `ready-receipt.sh write <new-sha> --after <pass-sha>`. That is not a third round. Any other change after the pass needs a new pass.

## The guard

`scripts/guard-hand-off.sh` blocks `gh pr ready`, `gh pr create` without `--draft`, `gh pr edit --add-reviewer` and a write to a PR's `requested_reviewers` until the PR's head commit has a receipt.

A repo whose hand-off checklist opens with front matter holding `drafts: true` wants it walked before any PR opens, draft or not. There, a draft `gh pr create` is blocked too until its head commit has a receipt: grade every box of the checklist alone against the PR as it will be read, fix what fails, push, and write `ready-receipt.sh write <full-sha> --checklist`. The full pass still runs before the PR is marked ready. A hand-off done in a browser or through another tool isn't seen; run the pass before those too.

When the user says to skip the pass for a PR, prefix that command with `KC_READY_SKIP=1`. Never add it on your own, and never to get past a pass that found something.

## Report

Chat, short:

```
### Ready for review: <PR title>
**Head:** `<short-sha>` · **Rounds:** <1|2> · **Open:** <n>

| Check | Round 1 | Round 2 |
|-------|---------|---------|
| Code review | <n> found, fixed | PASS · <n> open |
| Hand-off checklist | … | … |
| QA | <what was walked> | … |

**Open (your call):**
- `<file>:L<n>` <finding>. Fix: <one line>.
```

## After the reviewer comments

Sort each comment the reviewer makes:

- **Covered:** a rule already said it. The pass missed it, so fix the check that should have caught it: a vague box, a rule with no box, a checklist item that wasn't walked. Don't add a second rule.
- **New:** no rule said it. It becomes a lesson in the rules, with a box on their checklist.

The goal is that "covered" stays at zero.
