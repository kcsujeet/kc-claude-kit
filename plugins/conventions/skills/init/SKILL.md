---
name: init
description: Install the portable convention rules into this project. Trigger on "install the conventions", "set up my rules here", "add my coding rules to this project", "/conventions:init", or when a session reports that the conventions are not installed yet. Copies the bundled rule files into .claude/rules/ so they load with their path scoping intact, stamps the plugin version beside them, and reports what landed where.
---

# Installing the conventions into a project

Each convention lives in one topic skill (`skills/<topic>/SKILL.md`), and the plugin's `rules/` files are generated from those skills' `## Rules` sections by `scripts/build-rules.sh`. The one exception is `working-agreement.md`, which is hand-written and has no skill.

The skills alone are not enough, because rules and skills load differently. A rule in `.claude/rules/` loads when a file matching its `paths:` is read; a skill loads only when the model invokes it, even with `paths:` set (measured on Claude Code 2.1.280, see the kit's `docs/architecture.md`). And plugins cannot ship rules: a plugin contributes context "through skills, agents, and hooks", and a `CLAUDE.md` at the plugin root "is not loaded as project context". So the generated rule files sit on disk, read by nobody, until something copies them where Claude Code looks.

This skill is that something. It copies the rules into `.claude/rules/`, which is where they load with their `paths:` frontmatter respected, so each one arrives only when a matching file is touched, and it writes a version stamp so a later plugin update can report the copy as stale.

## Find the bundled rules

Try these in order and use the first that exists:

```bash
ls "${CLAUDE_PLUGIN_ROOT}/rules"/*.md 2>/dev/null
ls ~/.claude/plugins/*/conventions/rules/*.md 2>/dev/null
ls ~/.claude/plugins/*/*/plugins/conventions/rules/*.md 2>/dev/null
```

`${CLAUDE_PLUGIN_ROOT}` expands to this plugin's directory in skill content and is the reliable path when present. If none of them resolve, stop and say so rather than guessing: the fix is a reinstall, not a hand-built path.

## Install them

```bash
mkdir -p .claude/rules
cp "$SOURCE"/*.md .claude/rules/
```

Copy rather than symlink. A symlink into the plugin's install directory breaks when the plugin updates or is removed, and it will not survive being cloned by anyone else.

Then stamp the plugin version beside the copy. The SessionStart hook compares this stamp with the installed plugin's version and says so when they differ, so stale rules are reported instead of silently kept:

```bash
plugin_json="${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json"
[ -f "$plugin_json" ] || plugin_json="$SOURCE/../.claude-plugin/plugin.json"
sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$plugin_json" | head -n 1 > .claude/rules/.kc-conventions-version
cat .claude/rules/.kc-conventions-version
```

If the stamp comes out empty, say so rather than writing a guessed version.

Then confirm what actually landed, and read one file back to check the frontmatter survived the copy:

```bash
ls -la .claude/rules/
head -6 .claude/rules/naming.md
```

## Report

- Which files were installed, the version stamped, and the always-loaded cost: `working-agreement.md` is unscoped and loads every session; the rest carry `paths:` and stay out of context until a matching file is read.
- That `/context` in a **new** session is how to verify it, since rules load at session start.
- Whether `.claude/rules/` should be committed. It usually should, so the project carries its own conventions and anyone else cloning it gets them. Ask rather than deciding: a repo shared with people who have their own conventions is a different call from a personal project.

## Updating later

Re-run this skill after the plugin updates; the SessionStart hook says when the stamp and the plugin disagree. It overwrites, so a rule edited upstream propagates on the next run, and it rewrites the stamp. If the project has edited a rule locally, say which files differ before overwriting rather than silently discarding local changes:

```bash
for f in .claude/rules/*.md; do diff -q "$f" "$SOURCE/$(basename "$f")" >/dev/null 2>&1 || echo "differs: $f"; done
```

## What this does not do

It does not touch `CLAUDE.md`. An `@import` would work, but imports expand into context at launch, which throws away the `paths:` scoping and puts all thirteen files in every session. `.claude/rules/` keeps them deferred.

It also does not install machine-wide. For conventions on every project on a machine, the files go in `~/.claude/rules/` instead, which is a one-time symlink or copy outside this skill's scope.
