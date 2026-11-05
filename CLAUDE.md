# CLAUDE.md

This repo is public. Anyone can install and read these plugins.

## Examples stay neutral

Rules here are often learned while working on other projects. Write the lesson, never the project:

- No names, ticket ids, people, repo or file paths, class or component names, or domain details from the project a rule came from. That covers files, commit messages, PR titles and PR descriptions.
- Examples use a neutral domain (a shop, its storefronts and orders) and placeholder ids (`ABC-1`).
- Before committing or editing a PR, read the diff and the PR text for anything that names where a lesson came from, and rewrite it.

## Rules stay general

A lesson arrives as one case; the rule is the habit that catches the whole class. Before writing it, strip what the case brought with it:

- No one API shape (query params, includes, REST verbs), library (`lodash`), framework name or UI element (a picker, when the habit covers every read).
- State the principle at the widest scope it holds, and keep the case as one example among several ("a list, table, picker, search or count").
- Examples show the idea in plain code a reader of any stack can follow.

## Lessons

Lessons arrive from the maintainer's other work: a correction, a review comment or a QA finding that would have been caught by a habit. Each becomes its own PR here, written to the two sections above, and is merged once its checks pass, so installs get it on their next update. Installs update only with auto-update on for this marketplace and, where `DISABLE_AUTOUPDATER=1` is set (desktop app sessions have been seen with it set), `FORCE_AUTOUPDATE_PLUGINS=1` in `~/.claude/settings.json`; the README's "Staying up to date" says how. kc-gates also updates installs during a session, and each plugin tells Claude when the session runs an older version of it than is installed, so Claude asks the person to type `/reload-plugins`. When a lesson still doesn't show up, check `claude plugin list` before assuming it loaded.

Before writing a lesson:

1. Write the class of mistake in one sentence, then two or three other cases it would catch, from areas other than the one it came from. The rule is written for the class; the case that taught it is one example among those.
2. Treat wording the request suggests, from the user or from another session, as a starting point, not the rule: it was written about the case.
3. Grade the draft against `.claude/hand-off-checklist.md` before the first commit, not at hand-off, and fix what fails. The PR description states the class and the other cases.
4. When the lesson changes what a review or QA skill catches, add one eval case that proves it: under the plugin's `evals/`, a scaffold with a small diff showing the case (in the neutral domain) and a grader for the finding, shaped like `plugins/kc-gates/evals/seeded-violations/`. Run that case alone, once, before merging (`claude plugin eval . --eval-dir plugins/<plugin>/evals --case <name> --runs 1 --ablation none --scaffold --allow-tools Bash Agent`; `--runs 1` and `--ablation none` keep it to one run, where the defaults would make three runs and add a no-plugin arm), and say in the PR whether it passed. A case costs model calls, so it is one per lesson, never a suite per lesson, and CI runs the suites only on demand. A wording-only change adds none.

The checklist applies to draft PRs too (`drafts: true` in its front matter), so kc-gates' hand-off guard won't open even a draft PR here until its head commit has a checklist receipt (`ready-receipt.sh write <sha> --checklist`).

## Versions

Raise a changed plugin's `plugin.json` version by the smallest step that fits. Semver's "new behavior is a minor" doesn't apply here: a new rule is the everyday change, and a minor for each one says more changed than did.

- **Patch:** a rule, checklist box, example or wording added to or changed in an existing skill, agent or script, and any fix. Almost every PR, every lesson included.
- **Minor:** a new skill, agent, hook or command in the plugin.
- **Major:** renaming or removing something an install relies on (a plugin, skill, agent or installed rule file), so users must reinstall or rerun something.

When unsure, it is a patch; ask before going higher.

## Before a PR

Run `/kc-gates:kc-ready-for-review`: it walks `.claude/hand-off-checklist.md`, which checks the rules above and the version bump.

## Developing

Layout, conventions and release steps are in the README's "Developing" section and in `docs/architecture.md`.
