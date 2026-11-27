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

- [ ] Tick every box for each construct you add or change. Report each: PASS, FAIL (file:line) or N/A (why).

- [ ] §N1 Names state the role, not the type (no `data`/`result`/`value`/`temp`/`item`/`obj` for behaviour-bearing values); function names describe the effect, not the trigger.
- [ ] §N2 Each non-obvious operand of a `&&`/`||` chain with 2+ of them, and each parenthesized part, gets its own named boolean; naming the whole chain fails; `and-or-chains.sh` swept.
- [ ] §N3 A domain check combining fields or hiding a rule, repeated 3+ times in the repo, is a named `isX` owned by the hook or util that holds the data; list each with its repo-wide count.
- [ ] §N4 Each new or touched name reads true as a sentence: no subject elision, first-caller naming of a shared helper (`plainTextToHtml`, not `noteToHtml`), stale, hiding or dropped-qualifier names.
- [ ] §N5 Names read unambiguously at the use site: no bare generic verb/noun (`check`, `run`, `handle`) and no `isOn`/`isOpen`-style boolean on a bare state word; `bare-word-declarations.sh` swept.
- [ ] §N6 New functions start with a verb saying what a call does (`is`/`has`, `get`/`to`, `set`/`handle`); noun names (`sameOwner`) FAIL; components and hooks exempt; `unverbed-functions.sh` swept.
- [ ] §N7 A new file name identifies the file without its path: no basename already in the repo, no generic one (`header.tsx`); framework names exempt; `file-name-collisions.sh` swept.
- [ ] §N8 For every new file the evidence names 2-3 sibling files of the same kind and the new one follows their naming and location, or says why not; none named FAILS. (N/A: no new file)
- [ ] §N9 A new or renamed export, read without its folder, shows its kind (data hook, form-state hook, component, util, constant, type) and owner (which form, table, feature); one verdict each.
- [ ] §N10 Parts of one unit keep its prefix and end with their kind (`WidgetPanelSyncSection`, `WidgetPanelRow`); dropping either FAILS. (N/A: no sibling parts added)
- [ ] §N11 When the diff changes what a thing is or holds (one becomes many), every name still describing the old shape (routes, files, exports, API paths, keys) is listed and compared with siblings.
- [ ] §N12 One word per concept: a new name for a thing the codebase already names (`reservation` where it says `booking`) reuses the existing word. (N/A: no new names)
- [ ] §N13 Casing follows the language and the siblings: `snake_case` SQL columns and plural tables, `UpperCamelCase` types, `kebab-case` plural route nouns and file names. (N/A: nothing new named)
- [ ] §N14 Names in one scope sharing a word (`hasFailedPayment`, `hasPaymentError`) each say what they test, so a reader tells them apart; `near-synonym-names.sh`, one verdict per group.

- Examples and edge cases per box: references/detail.md (read when a box is unclear).

## Sweeps

- [ ] Save the diff under review to a file (`gh pr diff <num> > /tmp/review.diff`, or `git diff <default-branch>...HEAD > /tmp/review.diff`) and run each script over it; `-` reads the diff from stdin. Each prints one `path:line: text` hit per line, where `line` is the new-side line number, and nothing else. Give every hit its own verdict, and state the receipt with its count, `0 hits` included.

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

- `near-synonym-names.sh` (§N14): added boolean-shaped names in one file that share a content word; one verdict per group (each name says what it tests, or rename). Receipt: `grepped near-synonym names: N hits`.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/skills/kc-naming/scripts/near-synonym-names.sh" <diff-file>
  ```

- `file-name-collisions.sh` (§N7): new and untracked files whose basename another file in the repo already has. It reads repository state, so run it from the repo root, or pass the root as a second argument. Receipt: `checked new file names: N files, M collisions`.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/skills/kc-naming/scripts/file-name-collisions.sh" <diff-file>
  ```
