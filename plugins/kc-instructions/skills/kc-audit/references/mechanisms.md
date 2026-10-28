# The four mechanisms

Claude Code has four places project instructions can live. They differ in **when they load**, and that is the only axis that matters when deciding where something belongs. Topic is not the axis: "naming" is not inherently a rule and "testing" is not inherently a skill.

| Mechanism | Loads | Context cost | Belongs there |
|---|---|---|---|
| `CLAUDE.md` | Session start, full content | Every request, forever | Build and test commands, core conventions, "always do X" |
| `.claude/rules/*.md` | Session start, **or** only when a file matching its `paths:` frontmatter is read | Every request if unscoped; near-zero until matched if scoped | Language-specific or directory-specific guidelines |
| Skill | Description at session start; body only when invoked or matched | Low until used | Multi-step procedures, reference material |
| Hook | On a lifecycle event | Zero unless it returns output | Anything that must happen every time |

Nested `CLAUDE.md` files in subdirectories are a fifth option, loading on demand when Claude reads files in that directory. They do the same job as a path-scoped rule; prefer whichever the repo already uses rather than mixing both for the same purpose.

## Hard numbers

- **Target under 200 lines per `CLAUDE.md`.** Longer files consume more context and measurably reduce adherence.
- A `CLAUDE.md` up to 4 MiB is loaded in full; a larger one is skipped **silently**.
- `@path` imports are expanded into context **at launch**. Splitting a long file into imports organizes it but saves nothing.
- Rules **without** `paths:` frontmatter load at launch with the same priority as `.claude/CLAUDE.md`. Only `paths:` buys deferral.
- Auto memory's `MEMORY.md` index loads at session start, capped at the first 200 lines or 25 KB.

## Load order

Managed policy, then user (`~/.claude/CLAUDE.md`), then project (`./CLAUDE.md` or `./.claude/CLAUDE.md`), then local (`./CLAUDE.local.md`). Files are **concatenated, not overridden**, walking up from the working directory, so the more specific file is read last. Two files that contradict each other do not resolve to the more specific one reliably; Claude may pick either.

## Choosing

Four questions, in order. The first "yes" wins.

1. **Must this happen every time, without Claude choosing to?** → hook. An instruction is a request, not a guarantee: "the model choosing to run a formatter is different from the formatter running automatically." Anything phrased "never edit X" or "always run Y before Z" is a guardrail, and prose guardrails fail under pressure.
2. **Is it a multi-step procedure, or reference material only needed sometimes?** → skill. Roughly: a numbered sequence, or content you would not want resident all session.
3. **Does it only apply to some files or directories?** → rule with `paths:`. A rule that applies to `api/**` should not load while Claude edits an iOS view.
4. **Otherwise** → `CLAUDE.md`, phrased concretely.

## Delete rather than move

Content Claude can derive from the codebase earns nothing and costs every request. The official trim check "cuts content Claude can derive from the codebase, such as directory layouts, dependency lists, and architecture overviews, and keeps pitfalls, rationale, and conventions that differ from tool defaults."

So a directory tree, a dependency inventory, or a prose architecture tour is a deletion, not a migration. What survives from those sections is the **rules** they were wrapped around: "routes never talk to the DB directly", "nothing new at the repo root without asking". Those are not derivable, because they describe intent rather than layout.

A "where things live" table is the judgment call. It is derivable, so the trim check targets it, but it can still pay for itself in a large or unusually-organized repo by preventing repeated searching. Keep it only if the repo's layout genuinely surprises, and keep it short.

## Anti-patterns

- Storing a guardrail as prose instead of a hook.
- A 30-line procedure sitting in `CLAUDE.md`.
- A rule file with no `paths:` that only applies to some paths.
- Personal preferences in a team-shared file; those belong in `CLAUDE.local.md` or user scope.
- Instructions vague enough to be unverifiable. "Use 2-space indentation" works; "format code properly" does not.
- Treating any instruction as a security control. Enforcement is hooks and managed settings.
- Duplicating what auto memory already records. Auto memory writes its own notes for corrections and preferences, and skips what `CLAUDE.md` already says.
- An `AGENTS.md` with no `CLAUDE.md`. Claude Code reads `CLAUDE.md` only; a repo with just `AGENTS.md` needs a `CLAUDE.md` that imports it (`@AGENTS.md`) or a symlink.

## Sources

- Memory and `CLAUDE.md`: https://code.claude.com/docs/en/memory
- Mechanism comparison and context costs: https://code.claude.com/docs/en/features-overview
- Skills: https://code.claude.com/docs/en/skills
- Hooks: https://code.claude.com/docs/en/hooks-guide
- Decision framework: https://claude.com/blog/steering-claude-code-skills-hooks-rules-subagents-and-more

Re-read these before citing a number. The numbers above were current when this file was written and the product moves; a stale limit quoted with confidence is worse than looking it up.
