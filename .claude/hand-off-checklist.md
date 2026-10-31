# Hand-off checklist

Read by `kc-gates:kc-ready-for-review` before a pull request here is opened or merged. This repo is public and its rules apply to any codebase, so most kit PRs carry a lesson learned on some other project: these boxes check the lesson left that project behind. The rules behind them are in `CLAUDE.md`.

## The lesson is general

- [ ] The rule names the habit that catches the whole class of mistake, not the fix for the case that taught it. Test: a reader on a different stack and domain can apply it.
- [ ] Nothing the case brought with it narrows the rule: no single API shape, library, framework, UI element or data type in the rule itself. A stack skill (rails, react) gets a lesson only when it truly is about that stack.
- [ ] The case appears as one example among several, labelled as an example.
- [ ] An existing rule that should have caught it was widened instead of adding a narrower one beside it.

## Nothing names where it came from

- [ ] No company, product, repo, ticket id, person, file path, class or component name, or domain term from the source project, in the files, commit messages, PR title or PR description.
- [ ] Examples use a neutral domain (a shop, its storefronts and orders) and placeholder ids (`ABC-1`).

## It reaches people

- [ ] Each changed plugin's `plugin.json` version is raised by the level `CLAUDE.md`'s Versions section gives: a patch for a new or changed rule, box, example or fix; a minor only for a new skill, agent, hook or command; a major only for a rename or removal. CI's `version-bumps` job checks that it went up, not the level.
- [ ] `CHANGELOG.md` has the entry, with the same version.
- [ ] A rule added to a topic skill has a box on that skill's review checklist, and `rules/` was regenerated.
