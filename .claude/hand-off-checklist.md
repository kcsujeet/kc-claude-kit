---
drafts: true
ledger: true
---

# Hand-off checklist

Read by `kc-gates:kc-ready-for-review` before a pull request here is opened or merged. This repo is public and its rules apply to any codebase, so most kit PRs carry a lesson learned on some other project: these boxes check the lesson left that project behind. The rules behind them are in `CLAUDE.md`.

## The lesson is general

- [ ] The rule names the habit that catches the whole class of mistake, not the fix for the case that taught it. Test: a reader on a different stack and domain can apply it.
- [ ] Nothing the case brought with it narrows the rule: no single API shape, library, framework, UI element or data type in the rule itself. A stack skill (rails, react) gets a lesson only when it truly is about that stack.
- [ ] The case appears as one example among several, labelled as an example.
- [ ] An existing rule that should have caught it was widened instead of adding a narrower one beside it.
- [ ] Every skill, agent, hook and script the PR adds or changes works in a repo with nothing added for the kit: what it runs ships in the plugin, and a repo file it reads is optional, with a default when it is missing (`CLAUDE.md`, "Plugins stand alone").
- [ ] The PR description names the class of mistake in one sentence and two or three other cases the rule catches, from areas other than the one it came from; wording the request suggested was rewritten for the class, not kept because it was given.

## It comes from the whole look-back

- [ ] The lessons come from a listed look-back: `feedback-ledger.sh list` was run over the session transcript, with the review comments and QA rows as `--extra` files, every item has a verdict in the ledger, and `feedback-ledger.sh check` passes against this PR's diff (and a sibling repo's lesson diff where the lesson went there). The checklist receipt needs it: `ready-receipt.sh write <sha> --checklist --ledger <dir>`, since this file has `ledger: true`. The PR description gives the counts: items listed, and how many a first look-back from memory had missed.

## Nothing names where it came from

- [ ] No company, product, repo, ticket id, person, file path, class or component name, or domain term from the source project, in the files, commit messages, PR title or PR description.
- [ ] Examples use a neutral domain (a shop, its storefronts and orders) and placeholder ids (`ABC-1`).

## It reaches people

- [ ] Each changed plugin's `plugin.json` version is raised by the level `CLAUDE.md`'s Versions section gives: a patch for a new or changed rule, box, example or fix; a minor only for a new skill, agent, hook or command; a major only for a rename or removal. CI's `version-bumps` job checks that it went up, not the level.
- [ ] `CHANGELOG.md` has the entry, with the same version.
- [ ] A rule added to a topic skill has a box on that skill's review checklist, and `rules/` was regenerated.

## It is proven

- [ ] A lesson that changes what a review gate catches adds a seeded file and a grader to that gate's `<gate>-boxes` fixture (a QA-skill lesson, its own case) per `CLAUDE.md` Lessons step 4, run once before merging, and the PR says whether it passed. A wording-only change adds none.
- [ ] Each part of the lesson a script can decide (a draft check, a sweep, a mutant, a hook) is a script with a test, every new branch broken once to see a test fail. A PR whose rule edits have no box carries `wording-only: <why>` in its description, and when the rule files grow, a `held-by: <path>` line for each test or eval file that holds the new text (CI's `check-lesson-proof.sh` checks the lines and that each file gains lines in the PR, not that the why is true).
- [ ] A lesson's eval case fails with the lesson's rule edits taken out (`run-changed-evals.sh` runs it a third time and records it); a case that passes there is rewritten until it shows what the lesson adds, or tagged `guard` and not used as the lesson's proof.
