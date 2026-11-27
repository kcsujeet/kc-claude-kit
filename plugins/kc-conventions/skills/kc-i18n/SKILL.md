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

- [ ] Tick every box for each construct you add or change. Report each: PASS, FAIL (file:line) or N/A (why).

- [ ] §I1 Per-key audit table produced: one row per NEW key in the required shape (see §I1); a missing table, or an aggregate ("N keys, all unique"), FAILS. (N/A: no locale files changed)
- [ ] §I2 Only the source locale was edited; an edit to a machine-generated non-source locale FAILS. (N/A: no locale files changed, or all locales hand-maintained: say which)
- [ ] §I3 No duplicates: for every new key and every existing key in a touched file, the value grep and unscoped leaf-key grep ran across the source-locale tree; a hit outside the file FAILS.
- [ ] §I4 Key name matches its value in camelCase, or an established short-form suffix (grepped, not assumed); no generic leaf under a nested object. (N/A: no new or touched keys)
- [ ] §I5 Generic nouns/labels/headings live in the project's shared namespace, not a feature file — judged independently of the §I3 grep result. (N/A: no new keys in the diff)
- [ ] §I6 A fixed label is a plain string key; ICU plural only for a real count (`#`, real count variable), never `count: 1` or an `x`/`xs` key pair; `literal-plural-count.sh` swept.
- [ ] §I7 No translation concatenation (`t(a) + t(b)`, joined fragments); verb+noun decomposes into an action template plus a noun key; label+data is interpolation.
- [ ] §I8 Text a user sees is never also an identifier (stored, compared, linked, keyed): the stored side holds a key, the screen renders its translation; enumerate literals reaching both.
- [ ] §I9 No grammar attached to a placeholder (`{name}'s`, `{count}th`); the placeholder stands alone or an ordinal is `selectordinal`; swept by `placeholder-grammar.sh`.
- [ ] §I10 One term, one spelling across the source locale (no `Addons` beside `Add-ons`), touched or not; each word from `term-spellings.sh` gets a verdict. (N/A: no message value added or changed)
- [ ] §I11 A value placed inside a translated message (a relative time, date, number, list, currency) is formatted in that message's language; one formatted with no locale or another one FAILS, since it reads as English inside a translated sentence (see §I11). (N/A: no translated message takes a formatted value)

- Examples and edge cases per box: references/detail.md (read when a box is unclear).

## Sweeps

- [ ] Save the diff under review to a file and run `added-lines.sh` over it; `-` reads the diff from stdin. Two diff sweeps and the §I3 lookup. The diff sweeps print one `path:line: text` hit per line; give every hit its own verdict and state each receipt with its count, `0 hits` included.

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
