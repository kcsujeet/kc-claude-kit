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

## Plugins stand alone

A plugin here works in any repo that installs it, with nothing added to that repo. What a skill, agent, hook or script runs ships inside the plugin; a file it reads from the repo is optional configuration with a default that works when the file is missing; and a project's own rules live in that project's plugin or repo, never here. So before a plugin change calls, sources or requires anything outside its own folder, ship it in the plugin or make it optional config. Examples: a hook that ran a check script only when the repo had one at a fixed path, so it did nothing anywhere else; a skill whose steps call a `make lint` target few repos have; an agent told to read a docs folder by a path one project uses.

## Lessons

Lessons arrive from the maintainer's other work: a correction, a review comment or a QA finding that would have been caught by a habit. Each becomes its own PR here, written to the two sections above, and is merged once its checks pass, so installs get it on their next update. Installs update only with auto-update on for this marketplace and, where `DISABLE_AUTOUPDATER=1` is set (desktop app sessions have been seen with it set), `FORCE_AUTOUPDATE_PLUGINS=1` in `~/.claude/settings.json`; the README's "Staying up to date" says how. kc-gates also updates installs during a session, and each plugin tells Claude when the session runs an older version of it than is installed, so Claude asks the person to type `/reload-plugins`. When a lesson still doesn't show up, check `claude plugin list` before assuming it loaded.

Before writing a lesson:

1. Write the class of mistake in one sentence, then two or three other cases it would catch, from areas other than the one it came from. The rule is written for the class; the case that taught it is one example among those.
2. Treat wording the request suggests, from the user or from another session, as a starting point, not the rule: it was written about the case.
3. Grade the draft against `.claude/hand-off-checklist.md` before the first commit, not at hand-off, and fix what fails. The PR description states the class and the other cases.
4. When the lesson changes what a review gate catches, prove it in that gate's fixture under `plugins/kc-gates/evals/<gate>-boxes/` (`general-boxes` holds naming, clarity, structure and simplicity; `datetime-i18n-boxes` holds both of those): add one file to its `setup.sh` showing the case, realistic and in the neutral domain, and one grader for the finding. A grader matches a finding bullet (`- 🔴|🟠|🟡`) naming that file plus a keyword, never a § id or a line format, since reports carry neither reliably. Keep each fixture's clean unit clean: a review finding on it means the fixture is wrong or the rule is, and both are worth fixing. CI runs every case a pull request adds or changes, once with the kit and once in the runner's baseline arm without it, and fails unless the case passes every grader with the kit and fails every scored grader without it, so each grader shows something the kit adds (`scripts/run-changed-evals.sh`; a case tagged `negative` needs only the first). Run it before pushing with `bash scripts/run-changed-evals.sh main`, about $2 a run for a gate case. When a grader misses, rerun the case with `--keep-temp` (`claude plugin eval . --eval-dir plugins/kc-gates/evals --case <gate>-boxes --runs 1 --ablation none --trust-plugin --scaffold --allow-tools Bash Agent --keep-temp`) and read the review in `out/trace.jsonl` before touching either. A lesson for a QA skill adds its own case under that plugin's `evals/`. Whole suites run only on demand. A wording-only change adds none. CI holds this: `scripts/check-lesson-proof.sh` fails a pull request that edits a skill, a skill reference, an agent or the working agreement with no eval case or script test changed beside it, or that adds or rewrites a checklist box (`§X1`) whose id no changed eval or test names, unless the description has a line `wording-only: <why>`. So name each box's id in the case that proves it (its grader, `setup.sh` or `case.yaml`) or the test that does; the run of that case is the proof. A rule file that gains lines with no box added or rewritten in it gained prose no gate walks, and needs that line too, whatever test changed beside it; an agent or the working agreement has no boxes, so a change that adds to one always does. Before calling a lesson wording-only, look for the check a script could make (a draft check, a sweep, a mutant, a hook) and make it: a habit a script can hold is held by the script, with its test.

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
