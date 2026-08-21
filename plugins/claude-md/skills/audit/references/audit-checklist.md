# Audit checklist

Every box is walked against the repo's actual files, one verdict each: PASS, FAIL, or N/A with its reason. A box is FAIL if **any** file trips it. Findings are reported, never silently fixed; the proposal comes first.

Cite `file:line` for every finding. A box with no receipt is FAIL by default, because "I looked and it was fine" is indistinguishable from not looking.

## Size and shape

- [ ] §A1 Every `CLAUDE.md` in the repo is under 200 lines **and** its size in bytes is consistent with that. Report both per file, measured, not estimated. Lines alone are a bad proxy: a 141-line file of long bullet paragraphs can be 15 KB, roughly 3,800 tokens, and passes a line check while costing more than a 300-line file of short lines. Treat anything over about 8 KB as failing regardless of line count, and quote the byte size when you do. (Never N/A: a repo with no `CLAUDE.md` fails §A12 instead.)
- [ ] §A2 No multi-step procedure in `CLAUDE.md`. A numbered sequence of actions, a checklist someone follows start to finish, or a release/deploy/migration walkthrough belongs in a skill. Quote the first and last line of each one found. (N/A: no procedural content)
- [ ] §A3 No guardrail left as prose. Any "never <do X>", "always <do Y> before <Z>", or "must not <touch path>" that a script could enforce belongs in a hook; prose guardrails are advisory. List each one and name the hook event that would enforce it. (N/A: no mechanically-enforceable absolutes)
- [ ] §A4 No path-specific content loading unconditionally. Content that only applies to one language, one app, one directory, or one framework belongs in `.claude/rules/` with `paths:` frontmatter, or a nested `CLAUDE.md`. Name the glob each one should carry. (N/A: repo is single-language and single-app)
- [ ] §A5 No derivable content. Directory trees, file inventories, dependency lists, and prose architecture tours cost every request and can be read from the code. Separate the wrapper from the rules inside it: the tree goes, "routes never talk to the DB" stays. (N/A: no derivable content)

## Correctness

- [ ] §A6 No two instructions contradict each other, across `CLAUDE.md`, nested `CLAUDE.md` files, `.claude/rules/`, and user scope. Files are concatenated rather than overridden, so a contradiction resolves arbitrarily. Report both sides with paths. (N/A: single instruction file)
- [ ] §A7 Every instruction is concrete enough to verify. "Use 2-space indentation" passes; "format code properly", "write clean code", "follow best practices" fail. Quote each vague instruction. (N/A: all instructions concrete)
- [ ] §A8 Every command, path, script, and file reference in the instructions still exists. Check them: glob the paths, grep the package manifest for the scripts. A `CLAUDE.md` that names a deleted command teaches a wrong fact every session. (N/A: no commands or paths referenced)
- [ ] §A9 No personal preference in a team-shared file. Sandbox URLs, preferred test data, individual tooling habits belong in `CLAUDE.local.md` (gitignored) or user scope. (N/A: none found)

## Mechanism fit

- [ ] §A10 Every file in `.claude/rules/` that applies to only part of the repo carries `paths:` frontmatter. An unscoped rule loads at launch, so an unscoped narrow rule is a silent context leak. (N/A: no `.claude/rules/` directory, or all rules are genuinely global)
- [ ] §A11 `@path` imports are not being used as a size fix. Imports expand into context at launch, so an import chain has the same cost as pasting the content. Splitting for organization is fine; splitting to "save context" is a misunderstanding worth flagging. (N/A: no imports)
- [ ] §A12 A `CLAUDE.md` exists and is discoverable. If the repo has `AGENTS.md`, `.cursorrules`, `.cursor/rules/`, or `.github/copilot-instructions.md` but no `CLAUDE.md`, Claude Code reads none of it; the fix is a `CLAUDE.md` importing `@AGENTS.md`, or a symlink. (N/A: `CLAUDE.md` present)
- [ ] §A13 No content duplicated between mechanisms: the same rule in both `CLAUDE.md` and a rule file, or in both a rule file and a skill. Duplication doubles the cost and is how contradictions start. (N/A: single instruction file)
- [ ] §A14 Skill descriptions are specific enough to match on. Claude picks skills by matching the task against descriptions, so two skills with overlapping vague descriptions means the wrong one loads. Flag any description that does not name concrete trigger phrases. (N/A: no skills in repo)
- [ ] §A15 The instructions say how they get updated. A file with no convention for adding to it goes stale; the repo should say where a new correction lands. Note that auto memory now records corrections and preferences on its own, so a hand-maintained log of those is partly redundant. (N/A: convention documented)

## Reporting

Lead with a table, one row per section of each instruction file, because the value of this audit is the mapping and everything else is supporting detail:

| File | Section | Lines | Verdict | Destination |
|---|---|---|---|---|
| `CLAUDE.md` | Testing loop | 12-31 | move | skill `e2e-testing` |
| `CLAUDE.md` | Directory layout | 44-70 | delete | derivable from the tree |
| `CLAUDE.md` | Type checking | 72-95 | move | rule, `paths: **/*.ts` |
| `CLAUDE.md` | Naming | 97-120 | keep | — |

Verdicts are exactly: **keep**, **move** (with destination and, for a rule, the glob), **delete** (with why it is derivable), **split** (which part stays, which part moves), or **enforce** (which hook event).

Then: the current always-loaded size versus the projected one, in both lines and bytes, since that number is the whole point. Give bytes as well as lines, because a file of long paragraphs hides its true cost behind a small line count. Then the findings from the correctness boxes, which are bugs rather than restructuring.

Finish with the file plan: every file to create, edit, or delete, with its `paths:` frontmatter where applicable. **Write nothing until the plan is approved.** Restructuring someone's instructions without consent is the one unrecoverable mistake here: the content is often hand-tuned over months, and a bad split degrades every future session quietly.
