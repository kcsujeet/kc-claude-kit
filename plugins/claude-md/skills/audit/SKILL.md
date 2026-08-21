---
name: audit
description: Audit a repository's Claude Code instruction setup and propose a restructure. Trigger on "audit my CLAUDE.md", "review my CLAUDE.md", "is my CLAUDE.md any good", "my CLAUDE.md is too long", "Claude keeps ignoring my instructions", "should this be a skill or a rule", "set up CLAUDE.md for this repo", or a request to reorganize claude rules, skills, and hooks. Inventories every instruction file, classifies each section by where it belongs (CLAUDE.md, path-scoped rule, skill, hook, or deletion), reports the always-loaded token cost before and after, and proposes a file plan. Never rewrites instruction files without explicit approval.
---

# Auditing a repo's instruction setup

Instructions rot in a specific way. A `CLAUDE.md` starts as ten useful lines, and every correction adds three more, until it is four hundred lines loaded into every session, most of it irrelevant to whatever the current task is. Adherence goes **down** as the file grows, so the file that was supposed to make Claude more reliable makes it less so.

This skill fixes that by sorting content by **when it needs to load**, not by topic.

Read `references/mechanisms.md` for the four mechanisms and the decision order, and `references/audit-checklist.md` for the boxes to walk. Both, in full, before reporting anything.

## Hard rules

- **Read the repo's actual files. Never audit from assumption.** Every finding cites `file:line`. If you did not open the file, you have no finding.
- **Verify claims the instructions make.** A `CLAUDE.md` naming an `npm run check` that no longer exists is teaching a wrong fact every session. Glob the paths, grep the manifest for the scripts, and report the dead ones.
- **Propose, then stop.** Show the mapping table and file plan, and write nothing until the user approves. These files are usually hand-tuned over months; silently restructuring them degrades every future session in a way nobody notices for weeks.
- **Sort by load timing, not by topic.** "Naming" is not inherently a rule and "testing" is not inherently a skill. A naming convention that applies to every file belongs in `CLAUDE.md`; per-language naming belongs in a path-scoped rule. Ask when it needs to be resident, never what it is about.
- **Deleting beats moving.** Content Claude can read off the codebase (directory trees, dependency lists, architecture tours) should go, not relocate. Keep the non-derivable rules that were wrapped around it.
- **Do not invent conventions.** If the repo has no opinion on something, that is not a gap for this audit to fill. Report what is there, misplaced, contradictory, or stale. A proposal that adds rules nobody asked for is scope creep in the one file where scope creep is most expensive.
- **Every box gets an explicit verdict.** PASS, FAIL, or N/A with a reason. A silently skipped box reads identically to a passing one, which is how an audit becomes theatre.

## Workflow

### Step 1 — inventory

Find every file that contributes instructions, and measure it. Do not skip the measuring; line counts are the spine of the report.

```bash
# project scope
ls -la CLAUDE.md .claude/CLAUDE.md CLAUDE.local.md 2>/dev/null || true
find . -name CLAUDE.md -not -path './.git/*' -not -path '*/node_modules/*'
find .claude/rules -name '*.md' 2>/dev/null
find .claude/skills -name 'SKILL.md' 2>/dev/null
# lines AND bytes: a short-looking file of long paragraphs still costs a fortune
wc -lc $(find . -name 'CLAUDE.md' -not -path './.git/*' -not -path '*/node_modules/*') 2>/dev/null

# other agents' instruction files, which Claude Code does not read on its own
ls -la AGENTS.md .cursorrules .cursor/rules .github/copilot-instructions.md 2>/dev/null

# hooks already in place
cat .claude/settings.json .claude/settings.local.json 2>/dev/null
```

Note which files load at launch and which load on demand: root and ancestor `CLAUDE.md` at launch, subdirectory `CLAUDE.md` on demand, rules at launch unless they carry `paths:`, skill bodies on invocation.

### Step 2 — classify every section

Walk each instruction file section by section. For each, apply the decision order from `references/mechanisms.md`: hook, then skill, then path-scoped rule, then `CLAUDE.md`. Record the line range, the verdict, and the destination.

Two things to get right here:

- **A section can split.** "Testing" is often one paragraph of always-true rules plus a twenty-line procedure. The paragraph stays; the procedure becomes a skill. Do not force a whole section into one bucket.
- **The glob matters.** A rule destined for `paths:` is only worth moving if you can name the pattern. "Some backend thing" is not a destination; `paths: api/**/*.ts` is.

### Step 3 — walk the checklist

Every box in `references/audit-checklist.md`, with a receipt each. The size and shape boxes drive the restructure; the correctness boxes (contradictions, vague instructions, dead commands, duplication) are bugs that are worth fixing whether or not the user takes the restructure.

### Step 4 — report

Follow the reporting format in `references/audit-checklist.md`: the mapping table first, then the always-loaded line count now versus projected, then correctness findings, then the file plan.

Give the user the number that matters in one line, for example: "15 KB across 141 lines loads on every session today; 6 KB after this, with the rest arriving when it is relevant." Quote bytes alongside lines, since a file of long paragraphs understates its cost by line count alone.

### Step 5 — apply, once approved

Only after explicit approval, and then:

- Create rule files with their `paths:` frontmatter. Move content verbatim where possible; rewriting while relocating makes the diff unreviewable.
- Create skills with a `name` and a `description` carrying real trigger phrases, since a vague description means the skill never loads.
- Write hooks into settings for the guardrails, and say plainly that this is the only change of the set that actually enforces anything.
- Trim the `CLAUDE.md` last, so nothing is deleted before its replacement exists.
- Report the final line count, and tell the user to run `/context` to confirm what actually loaded. Your projection is arithmetic; `/context` is the observation.

## Scope

This skill audits how instructions are **organized**. It does not judge whether a convention is a good convention: if a repo wants tabs, that is not a finding. The exceptions are the correctness boxes, where an instruction is contradictory, unverifiable, or references something that no longer exists.

It also does not write the conventions themselves. A repo with a two-line `CLAUDE.md` and no rules is not failing this audit; it just has little to reorganize. Say so and stop, rather than inventing a setup it never asked for.
