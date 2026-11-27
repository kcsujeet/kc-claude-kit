---
name: kc-init
description: "Install the portable convention rules into this project, copying them into .claude/rules/ (the home copy installs itself). Trigger on \"install the conventions\", \"set up my rules here\", \"add my coding rules to this project\", \"/kc-conventions:kc-init\", or when a session reports the conventions are not installed."
---

# Installing the conventions into a project

Each convention lives in one topic skill (`skills/kc-<topic>/SKILL.md`), and the plugin's `rules/` holds two hand-written files: `kc-conventions.md`, a pointer list naming the skill to load for each kind of work, and `kc-always.md`, a short always-loaded rule of reply habits with pointers to the process skills (`kc-do-a-task`, `kc-check-claims`, `kc-delegate`, `kc-look-back`).

The skills alone are not enough, because rules and skills load differently. A rule in `.claude/rules/` loads when a file matching its `paths:` is read; a skill loads only when the model invokes it, even with `paths:` set (measured on Claude Code 2.1.280, see the kit's `docs/architecture.md`). And plugins cannot ship rules: a plugin contributes context "through skills, agents, and hooks", and a `CLAUDE.md` at the plugin root "is not loaded as project context". So the rule files sit on disk, read by nobody, until something copies them where Claude Code looks.

The plugin's hook installs and refreshes the machine-wide copy in `~/.claude/rules/` by itself, on a session's first prompt, so nobody has to decide that step. A project copy it never writes, because it may be committed and shared. This skill is that project copy, on request. It copies the rules into `.claude/rules/`, which is where they load with their `paths:` frontmatter respected, so each one arrives only when a matching file is touched, and it writes a version stamp so a later plugin update can report the copy as stale.

## Install them

Run the bundled installer and report its output:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/install-rules.sh"
```

It finds the rules relative to itself, so there is no path to guess, copies every `rules/*.md` into `.claude/rules/`, writes the plugin version to `.claude/rules/.kc-conventions-version`, and prints one line per rule (`new`, `unchanged` or `replaced`) followed by the version. The plugin's hook compares that stamp with the installed plugin on a session's first prompt and reports a stale project copy; it does not rewrite it. `--dest <dir>` installs somewhere else.

Copy rather than symlink, which is what the script does. A symlink into the plugin's install directory breaks when the plugin updates or is removed, and it will not survive being cloned by anyone else.

If the script exits non-zero, relay its message and stop: missing rules or an unreadable version mean the plugin needs a reinstall, not a hand-built path or a guessed stamp.

## Report

- Which files were installed, the version stamped, and the always-loaded cost: `kc-always.md` is unscoped and loads every session; the rest carry `paths:` and stay out of context until a matching file is read.
- That `/context` in a **new** session is how to verify it, since rules load at session start.
- Whether `.claude/rules/` should be committed. It usually should, so the project carries its own conventions and anyone else cloning it gets them. Ask rather than deciding: a repo shared with people who have their own conventions is a different call from a personal project.

## Updating later

Re-run this skill after the plugin updates; the plugin's hook says, on a session's first prompt, when the project copy's stamp and the plugin disagree. The installer overwrites, so a rule edited upstream propagates on the next run, and it rewrites the stamp. When rules are already installed, run it with `--dry-run` first: every `would replace:` line is a file whose installed copy differs from the plugin's, which is either an upstream change or a local edit. Name those files to the user before the real run rather than silently discarding local changes.

## What this does not do

It does not touch `CLAUDE.md`. An `@import` would work, but imports expand into context at launch, which throws away the `paths:` scoping and puts every file in every session. `.claude/rules/` keeps them deferred.

The machine-wide copy is not this skill's job: the hook runs `install-rules.sh --dest ~/.claude/rules` when that copy is missing (and no project copy exists) or stale, and prints one line saying so. Set `KC_CONVENTIONS_AUTO_INSTALL=0` in the environment or in `~/.claude/settings.json` `env` to turn that off; the hook then only reports, with the command to run.
