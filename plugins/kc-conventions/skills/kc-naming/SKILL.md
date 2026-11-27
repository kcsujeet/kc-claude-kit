---
name: kc-naming
description: "Naming conventions for identifiers and file names in any language: role-not-type names, verb-led functions, named booleans, honest unambiguous names, consistent file names. Use when writing or reviewing code that adds or renames a variable, function, parameter, export or file, or choosing a name."
user-invocable: false
paths:
  - "**/*.{ts,tsx,js,jsx,mjs,cjs,rb,py,swift,go,java,kt,php,cs,rs}"
---

# Naming

## Contents

- Review checklist
- Sweeps

## Review checklist

Tick every box for each construct you add or change. Report each: PASS, FAIL (file:line) or N/A (why).

- [ ] §N1 Role-not-type names: new variables/functions describe the role, not the type (no `data`/`result`/`value`/`temp`/`item`/`obj` for behavior-bearing values); function names describe the effect, not just the trigger. (N/A: no new identifiers)
- [ ] §N2 Inline boolean chains — evaluate the OPERANDS, not just the outer name: any `&&`/`||` chain with 2+ non-obvious operands (raw comparisons, enum (in)equalities, negations, `?.` field access) has EACH non-obvious operand extracted to its own named boolean. Assigning the whole chain to a named boolean does NOT satisfy this. A parenthesized sub-expression in a mixed `&&`/`||` chain (e.g. `(a || b) && c`) also gets its own name — parentheses alone don't pass. Enumerate with the `and-or-chains.sh` sweep, do not eyeball. (N/A: only when `and-or-chains.sh` returns 0 hits, stated as `grepped &&/||: 0 hits`)
- [ ] §N3 Repeated domain check: an expression that answers a domain question by combining fields or hiding a rule the line does not show, and that appears 3+ times in the repo counting the diff's copy, is a named `isX` (a type guard when narrowing helps) returned by the hook or util that owns the data, and the diff uses it instead of adding another copy. One field compared to one enum value (`status === Status.DONE`) and a plain mechanic (a `find` by id) are exempt at any count, and proposing an `isX` for one is itself a miss (simplicity §P11). **Enumerate**: list each domain check the diff adds with its repo-wide count. (N/A: no domain check added)
- [ ] §N4 Honest names: each new or touched name reads as a sentence that matches the actual behavior/subject — no surface-word gluing, no subject elision, no context-as-subject (a helper used by more than one caller, or written to be, named for the first caller's field instead of what it handles: `plainTextToHtml`, not `noteToHtml`), no stale-after-refactor names, no familiar-shaped name hiding a different behavior or constraint, no dropped qualifier (a unit doing the public, archived, cached or admin version of a job named for the plain one, while the rest of its family carries the qualifier), and no qualifier that adds nothing (a prefix or suffix that repeats the owner, type or context the name already sits in: `footerEmail` on a footer-only model, `userUserId`, `orderOrderStatus`). (N/A: no new or touched names)
- [ ] §N5 Unambiguous where READ, not where declared: every new identifier (local, destructured value, parameter, closure, returned key, export) is qualified enough to read at its use site without scrolling back to the declaration. A bare generic verb/noun naming the mechanism rather than the subject (`check`, `run`, `wrap`, `guard`, `handle`, `process`, `filter`, `format`, `validate`, and any other single word of that shape) FAILS even though it is accurate, and so does a boolean prefix on a bare state word (`isOn`, `isOpen`, `isActive`, `isValid`, `hasData`), and a collision with an unrelated declaration elsewhere FAILS on its own. Enumerate with the `bare-word-declarations.sh` sweep, do not eyeball. (N/A: only when the diff adds no identifiers, stated as `grepped bare-word declarations: 0 hits`)
- [ ] §N6 Verb-led functions: every new function (declaration, arrow-function const, or object method) starts with a verb that says what calling it does: predicates `is`/`has`/`can`/`should`, value getters `get`/`to`, mutators and handlers `set`/`toggle`/`handle`. A noun-phrase name (`sameOwner`, `itemLabel`, `widgetKey`) reads like a value, not a callable, and FAILS. PascalCase components and `use*` hooks are exempt. Enumerate with the `unverbed-functions.sh` sweep, do not eyeball. (N/A: only when `unverbed-functions.sh` returns 0 hits, stated as `grepped unverbed functions: 0 hits`)
- [ ] §N7 Unique file names: every new file name identifies the file without its path, since tabs, search results, and stack traces show it bare. A basename that already exists elsewhere in the repo FAILS, and so does a generic one (`header.tsx`, `helpers.ts`) deep in a folder whose path carries the only meaning. Framework-mandated names (`index`, `page`, `layout`, `route` and equivalents) are exempt, and a test file is judged by its unit's name. Check collisions with the `file-name-collisions.sh` sweep. (N/A: no new files in diff)
- [ ] §N8 Sibling comparison recorded: for every new file, the evidence names 2-3 existing files of the same kind (a hook, a component, a types file, a test) and the new file follows their naming pattern (casing, suffix, how the subject is carried) and sits where files of its kind sit, or the evidence says why it cannot. A new file with no named siblings FAILS by default. Siblings with generic basenames do not excuse §N7. (N/A: no new file)
- [ ] §N9 Kind and owner read at the import site: every new or renamed export, read with no folder path, lets a reader guess both what kind of thing it is (data hook, form-state hook, component, util, constant, type) and what it belongs to (which form, table, feature). A wrong guess on either FAILS: a hook that only fills one form's fields named like a data hook, a co-located hook carrying the name of a shared data layer, a one-table helper named like an app-wide util. **Enumerate**: every new or renamed export gets a verdict. (N/A: no new or renamed export)
- [ ] §N10 Parts of one unit keep its prefix AND end with their kind: sibling pieces of `WidgetPanel` are `WidgetPanelSyncSection`, `WidgetPanelRow`. Keeping the prefix but dropping the kind (`WidgetPanelSync`) FAILS, and so does keeping the kind but dropping the prefix (`WidgetSyncSection`). (N/A: no new file or export in a family of sibling parts)
- [ ] §N11 A name follows what its subject became: when the diff changes what an existing thing is or holds (one becomes many, a single settings page becomes a list with a page per record, a per-account setting becomes per-item), the evidence lists every name that still describes the old shape (route segments, folders, files, exports, API paths, query keys, translation keys, including ones the diff does not touch) and compares each with 2-3 siblings that already have the new shape. A name that no longer matches FAILS unless the diff renames it or states why the rename has to wait (for example a public URL that needs a redirect first). (N/A: the diff changes no existing thing's cardinality or kind)
- [ ] §N12 One word per concept: a new name for a thing the codebase already names (`reservation` where it says `booking`) reuses the existing word. (N/A: no new names)
- [ ] §N13 Casing follows the language and the siblings: `snake_case` SQL columns and plural tables, `UpperCamelCase` types, `kebab-case` plural route nouns and file names. (N/A: nothing new named)

Examples and edge cases per box: references/detail.md (read when a box is unclear).

## Sweeps

Save the diff under review to a file (`gh pr diff <num> > /tmp/review.diff`, or `git diff <default-branch>...HEAD > /tmp/review.diff`) and run each script over it; `-` reads the diff from stdin. Each prints one `path:line: text` hit per line, where `line` is the new-side line number, and nothing else. Give every hit its own verdict, and state the receipt with its count, `0 hits` included.

- `added-lines.sh` (citation map): every added line as `path:line: text`, with the source line number at the head SHA. Cite every finding's line from this output or from a sweep hit, never from a position in the diff file.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/added-lines.sh" <diff-file>
  ```

- `and-or-chains.sh` (§N2): added lines holding `&&` or `||`. Receipt: `grepped &&/||: N hits`.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/skills/kc-naming/scripts/and-or-chains.sh" <diff-file>
  ```

- `bare-word-declarations.sh` (§N5): added declarations whose name starts lowercase, with a shell script's assignments, `local`s, functions and loop variables; the bare-word ones are then grepped across the repo. Receipt: `grepped bare-word declarations: N hits`.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/skills/kc-naming/scripts/bare-word-declarations.sh" <diff-file>
  ```

- `name-collisions.sh` (§N5, a lookup rather than a diff sweep): takes one name, not a diff, and prints every whole-word hit in the repo's tracked files as `path:line: text`. Run it once per bare-word hit from the sweep above; the collision count in the receipt comes from it.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/skills/kc-naming/scripts/name-collisions.sh" <name> [<repo-root>]
  ```

- `unverbed-functions.sh` (§N6): added function declarations whose name does not start with a known verb, a shell script's snake_case functions included. Receipt: `grepped unverbed functions: N hits`.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/skills/kc-naming/scripts/unverbed-functions.sh" <diff-file>
  ```

- `file-name-collisions.sh` (§N7): new and untracked files whose basename another file in the repo already has. It reads repository state, so run it from the repo root, or pass the root as a second argument. Receipt: `checked new file names: N files, M collisions`.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/skills/kc-naming/scripts/file-name-collisions.sh" <diff-file>
  ```
