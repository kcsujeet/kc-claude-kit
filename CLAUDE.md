# CLAUDE.md

This repo is public. Anyone can install and read these plugins.

## Examples stay neutral

- Rules here are often learned on other projects. Write the lesson, never the project.

- No names, ticket ids, people, repo or file paths, class or component names, or domain details from the project a rule came from. That covers files, commit messages, PR titles and PR descriptions.
- Examples use a neutral domain (a shop, its storefronts and orders) and placeholder ids (`ABC-1`).
- Before committing or editing a PR, read the diff and the PR text for anything that names where a lesson came from, and rewrite it.

## Rules stay general

- A lesson arrives as one case. The rule is the habit that catches the whole class. Before writing it, strip what the case brought with it.

- No one API shape (query params, includes, REST verbs), library (`lodash`), framework name or UI element (a picker, when the habit covers every read).
- State the principle at the widest scope it holds. Keep the case as one example among several ("a list, table, picker, search or count").
- Examples show the idea in plain code a reader of any stack can follow.

## Plugins stand alone

- A plugin works in any repo that installs it, with nothing added to that repo.

- What a skill, agent, hook or script runs ships inside the plugin.
- A file it reads from the repo is optional configuration with a default that works when the file is missing.
- A project's own rules live in that project's plugin or repo, never here.

- Before a plugin change calls, sources or requires anything outside its own folder, ship it in the plugin or make it optional config. Examples: a hook that ran a check script only when the repo had one at a fixed path; a skill whose steps call a `make lint` target few repos have; an agent told to read a docs folder by a path one project uses.

## Lessons

- A lesson comes from the maintainer's other work: a correction, a review comment or a QA finding that a habit would have caught, and that passes the bar in `kc-do-a-task` step 6. What this kit's own review pass finds on a kit PR is fixed in that PR or left open, never the reason for the next one. Each lesson is its own PR, written to the two sections above, and merged once its checks pass.

- Installs update only with auto-update on for this marketplace. Where `DISABLE_AUTOUPDATER=1` is set (desktop app sessions have been seen with it), `FORCE_AUTOUPDATE_PLUGINS=1` in `~/.claude/settings.json` is also needed; the README's "Install" section says how. kc-gates also updates installs during a session, and each plugin tells Claude when the session runs an older version than is installed, so Claude asks for `/reload-plugins`. When a lesson does not show up, check `claude plugin list` before assuming it loaded.

- Future rules are a check that blocks the mistake. A lint rule, test, script or hook is the lesson; prose alone is not accepted. `plugins/kc-gates/scripts/feedback-ledger.sh check` fails a lesson whose PR adds or changes no script, hook, test, eval, CI workflow or lint-rule file. Existing prose rules stay as they are.

- Before writing a lesson:

1. Write the class of mistake in one sentence, then two or three other cases it would catch, from other areas. The case that taught it is one example among those.
2. Treat wording the request suggests (from the user or another session) as a starting point. It was written about the case.
3. Place it by layer before writing prose. Can a lint rule, type, test or script hold it, with an error that says what to do? Then that is the lesson. Otherwise a guard, a path-scoped rule or a skill. Always-on text (`kc-always.md`, hook-printed text) is only for a short must or trigger naming its skill.
   - Run `bash scripts/check-always-on.sh` before and after; put both numbers in the description.
   - No kit change may add a token cost CI does not measure. If it adds a kind of cost the script cannot see, extend the script in the same PR.
   - Raising or removing a budget flag in `ci.yml` needs a `budget-raised: <why>` line in the description (`scripts/check-budget-change.sh`).
4. Grade the draft against `.claude/hand-off-checklist.md` before the first commit, not at hand-off. The PR description states the class and the other cases.
5. Prove it. When the lesson changes what a review gate catches, prove it in that gate's fixture under `plugins/kc-gates/evals/<gate>-boxes/` (`general-boxes` holds naming, clarity, structure and simplicity; `datetime-i18n-boxes` holds both). A lesson for a QA skill adds its own case under that plugin's `evals/`.
   - Add one file to the fixture's `setup.sh` showing the case (realistic, neutral domain) and one grader for the finding. A grader matches a finding bullet (`- 🔴|🟠|🟡`) naming that file plus a keyword, never a § id or a line format. Keep each fixture's clean unit clean.
   - Run every case the change adds or changes with `bash scripts/run-changed-evals.sh main` once the change is committed, on your own login: once with the kit and once without it, about $2 to $4 a gate case. A case passes when it passes every grader with the kit and fails every scored grader without it (a case tagged `negative` needs only the first).
   - When the change also edits a rule in a plugin the case loads, the case runs a third time with those edits taken out and must fail there. A case that only holds existing behaviour is tagged `guard`, skips that run, and cannot prove a box.
   - Commit the case's `proof.json`. CI runs no model and holds no key. Its `changed-evals` job fails a PR whose changed case has no `proof.json`, a failed run, or a run made from other files, so an edit after the run means running it again.
   - When a grader misses, rerun with `--keep-temp` (`claude plugin eval . --eval-dir plugins/kc-gates/evals --case <gate>-boxes --runs 1 --ablation none --trust-plugin --scaffold --allow-tools Bash Agent --keep-temp`) and read the review in `out/trace.jsonl` before touching either.
   - A wording-only change adds no case. `scripts/check-lesson-proof.sh` fails a PR that edits a skill, a skill reference, an agent or `kc-always.md` with no eval case or script test changed beside it, or that adds or rewrites a box (`§X1`) whose id no changed eval or test names, unless the description has a line `wording-only: <why>`.
   - That line alone covers a reword or a removal. When the rule files gain more lines than they lose, the description also names `held-by: <path>`, a test script or eval file the change adds lines to.
   - Name each box's id in the case or test that proves it. A rule file that gains lines with no box added or rewritten gained prose no gate walks, and needs the `held-by:` line too. An agent or `kc-always.md` has no boxes, so a change that adds to one always does.
   - Before calling a lesson wording-only, look for the check a script could make (a draft check, a sweep, a mutant, a hook) and make it.

- The checklist applies to draft PRs too (`drafts: true` in its front matter). The hand-off guard will not open even a draft PR here until its head commit has a checklist receipt (`ready-receipt.sh write <sha> --checklist`).

## Versions

- Raise a changed plugin's `plugin.json` version by the smallest step that fits. Semver's "new behavior is a minor" does not apply: a new rule is the everyday change, and a minor for each says more changed than did.

- **Patch:** a rule, box, example or wording added to or changed in an existing skill, agent or script, and any fix. Almost every PR, every lesson included.
- **Minor:** a new skill, agent, hook or command in the plugin.
- **Major:** renaming or removing something an install relies on (a plugin, skill, agent or installed rule file), so users must reinstall or rerun something.

- When unsure, it is a patch; ask before going higher. `CHANGELOG.md` gets one line per plugin version, newest first.

## Before a PR

- [ ] Run `/kc-gates:kc-self-correct` on the change, then `/kc-gates:kc-ready-for-human-review`. It walks `.claude/hand-off-checklist.md`, which checks the rules above and the version bump.

## Developing

- Layout, conventions and release steps are in `docs/architecture.md`. The README stays short: what each plugin and skill is for and how they connect. Detail goes in `docs/architecture.md`.
