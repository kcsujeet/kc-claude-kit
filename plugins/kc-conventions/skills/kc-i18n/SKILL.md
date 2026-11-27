---
name: kc-i18n
description: "Translation conventions for locale JSON files and the code that calls them: source-locale-only edits, duplicate keys, key names, shared namespace, ICU plurals, no concatenation. Use when writing or reviewing code that adds or changes a translation key, a locale file, or a `t()` call."
user-invocable: false
paths:
  - "**/*.{ts,tsx,js,jsx}"
  - "**/locales/**/*.json"
  - "**/messages/**/*.json"
  - "**/i18n/**/*.{json,ts}"
---

# Translations

## Contents

- Review checklist
- Sweeps

## Review checklist

Tick every box for each construct you add or change. Report each: PASS, FAIL (file:line) or N/A (why).

- [ ] §I1 Per-key audit table produced: one row per NEW key in the diff, in the required shape (below). Absence of the table is an automatic gate FAIL — an aggregate report ("N keys, all unique ✓") does not satisfy this box. (N/A: no locale files changed)
- [ ] §I2 Only the source locale was edited. If the project machine-generates non-source locales, any edit to a generated locale file is a FAIL. (N/A: no locale files changed, or every locale in the project is hand-maintained — state which)
- [ ] §I3 No duplicates: for EVERY new key, and every pre-existing key in a file the diff touches, both the value grep and the unscoped leaf-key grep were run across the whole source-locale tree, plus semantic-equivalent reasoning. Any hit outside the file being added to is a FAIL, no exemptions. (N/A: no new or touched keys)
- [ ] §I4 Key name matches its value in camelCase, or an established short-form suffix (grepped, not assumed); no generic leaf under a nested object. (N/A: no new or touched keys)
- [ ] §I5 Generic nouns/labels/headings live in the project's shared namespace, not a feature file — judged independently of the §I3 grep result. (N/A: no new keys in the diff)
- [ ] §I6 A fixed label, heading, column or nav item is a plain string key (`addOn`, `addOns`); an ICU plural message is only for a real count, uses `#`, and is read with the actual count variable. A literal count (`count: 0`, `1`, `2`) passed to get a word form FAILS, as does a message that shows a count with no plural and an `x`/`xs` key pair picked by `count === 1`. A finding on this carries its short why (§I6 detail). **Enumerate with the `literal-plural-count.sh` sweep** (see Sweeps). (N/A: no label, count message or translation call added in the diff — state which; the receipt `grepped literal plural counts: N hits` is stated either way)
- [ ] §I7 No translation concatenation: no `t(a) + t(b)` or template-joined translatable fragments; verb+noun values decompose into an action template plus a noun key; label+data is interpolation and is not flagged, and no redundant composite key was invented in its place. (N/A: no new key values or call sites in diff)
- [ ] §I8 Text shown to people is never an identifier: every string the diff adds that a user sees and that is also stored, compared, put in a link or used as a key FAILS; the stored side holds a key and the screen renders its translation. **Enumerate** constants and literals that reach both a screen and a value. (N/A: none added)
- [ ] §I9 No grammar attached to a placeholder: a message with `{name}'s`, `{count}th` or another suffix, article or agreement written against a placeholder FAILS; the placeholder stands alone (`The plan for {name}`), or an ordinal is a `selectordinal` message. **Enumerate with the `placeholder-grammar.sh` sweep** (see Sweeps). (N/A: no message value added in the diff, stated as `grepped placeholder grammar: 0 hits`)
- [ ] §I10 One term, one spelling: when the diff adds, renames or respells a term in a message value, every other message in the source locale writes it the same way. A second spelling of it that differs only by a hyphen (`Addons` beside `Add-ons`, `e-mail` beside `email`) FAILS, whether or not the diff touched that line: a renamed term left in its old spelling on another screen is the miss. **Enumerate with the `term-spellings.sh` lookup** over the whole source-locale tree (see Sweeps), and give each listed word a verdict (respell, or two meanings such as `checkout` and `check-out`). (N/A: no message value added or changed in the diff, stated as `term spellings: N words` either way)

Examples and edge cases per box: references/detail.md (read when a box is unclear).

## Sweeps

Save the diff under review to a file and run `added-lines.sh` over it; `-` reads the diff from stdin. Two diff sweeps and the §I3 lookup. The diff sweeps print one `path:line: text` hit per line; give every hit its own verdict and state each receipt with its count, `0 hits` included.

- `locale-duplicates.sh` (§I3, a lookup rather than a diff sweep): takes a locale directory, a value and a leaf key, and runs the two §I3 greps. Run it once per new or touched key.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/skills/kc-i18n/scripts/locale-duplicates.sh" <locale-dir> <value> <leaf-key>
  ```

- `term-spellings.sh` (§I10, a lookup over the whole tree, not a diff sweep): takes the source-locale directory and prints `<word>: <most used spelling> x<count> (first <path>:<line>); <other spelling> (<path>:<line>, ...)` for each word with more than one spelling. Run it once whenever the diff adds or changes a message value. Receipt: `term spellings: N words`.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/skills/kc-i18n/scripts/term-spellings.sh" <locale-dir>
  ```

- `literal-plural-count.sh` (§I6): added lines in code files that pass a numeric literal as `count` to a translation call (`t('addOn', { count: 1 })`, `formatMessage(message, { count: 0 })`), across a call's lines. The fix is a plain label key. Receipt: `grepped literal plural counts: N hits`.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/skills/kc-i18n/scripts/literal-plural-count.sh" <diff-file>
  ```

- `placeholder-grammar.sh` (§I9): added lines in locale JSON files with a possessive or ordinal suffix on a placeholder (`{name}'s`, `{count}th`). Receipt: `grepped placeholder grammar: N hits`.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/skills/kc-i18n/scripts/placeholder-grammar.sh" <diff-file>
  ```

- `added-lines.sh` (citation map): every added line as `path:line: text`, with the source line number at the head SHA. Cite every finding's line from this output or from a sweep hit, never from a position in the diff file.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/added-lines.sh" <diff-file>
  ```
