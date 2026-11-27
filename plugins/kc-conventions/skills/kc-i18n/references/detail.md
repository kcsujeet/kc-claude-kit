# I18n: examples and edge cases per box

Translation/locale-key rules for the diff under review. Covers nine independent failure modes: mandatory per-key audit evidence, source-locale-only edits, duplicate keys (exact and semantic), key names that don't match their values, generic nouns misplaced outside the shared namespace, labels read through a made-up count, translation concatenation, display text used as an identifier, and grammar attached to a placeholder.

### §I1. The per-key audit table is the mandatory first output

Before evaluating any rule below, the gate agent produces one row per NEW key in the diff. Without this table, no locale finding (or lack of one) is valid evidence — an aggregate dedup report ("greped 7 keys, all unique ✓") hides exactly the violations a direct-value grep cannot see: a generic leaf sitting in the wrong file, a singular-only label that should have been an ICU plural, a key whose name doesn't match its own value. Only walking each key individually surfaces those. This is why the table, not a summary sentence, is the required evidence.

Required row shape:

```
<file>:L<n>: <key> = "<value>" | namespace: <ok / move to shared>, plural: <icu for a real count / plain label / literal count → flag>, dupe: <none / clash with X>, naming: <matches value / mismatch>
```

Example:

```
feature.json:L12: sprocket = "sprocket" | namespace: move to shared (generic noun), plural: n/a (plain label), dupe: none, naming: matches value
feature.json:L44: deleteWidgetMessage = "Are you sure you want to delete this widget?" | namespace: ok (feature-specific), plural: n/a (sentence), dupe: none, naming: matches value (short-form Message suffix)
```

Do not batch rows from memory. For every new key, walk §I2 through §I9 below and fill in the corresponding cell — a row filled in without actually running the grep and the plural/naming checks is the exact glaze-over that ships violations. Output the table first, then let the individual boxes' findings expand on any row marked FLAG.

### §I2. Only the source locale is edited

Determine the project's source locale from the repo (usually `en`) and the set of other locales it ships. If the project machine-generates its non-source locales — a TMS-style pipeline or translation-export process that regenerates those files on deploy — any hand-edit to a generated locale file is pointless: it is overwritten on the next deploy and accomplishes nothing for the user reading the PR. Flag any such edit and tell the author to revert the non-source-locale files; only the source-locale file's edits survive.

If the project's locale files are all hand-maintained (no generation pipeline), this box is N/A — state that explicitly rather than silently skipping it.

### §I3. No duplicates — search before adding, including pre-existing entries

**Mandatory dual grep, for every key in a touched file — not just the newly added lines.** When a diff edits a locale file, every key in that file is in scope, including keys that predate the PR. A pre-existing duplicate is still a finding: removing it is the same size of change as anything else in the file the PR is already touching, so "out of scope, pre-existing" is not a valid excuse.

For each new (or touched) key, run both greps with one call, passing the source-locale directory, the English value, and the unscoped leaf key name (just the leaf, not the dotted path):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/kc-i18n/scripts/locale-duplicates.sh" locales/en "Widget" widget
```

It prints every hit of the value across the whole source-locale tree labelled `value:`, then every `"widget":` leaf-key hit labelled `key:`, each as `path:line: text`. Both greps are the evidence: cite the hits (or `0 hits`) for each key in the audit table.

Any hit outside the file being edited is a duplicate or near-duplicate. This is a real blind spot twice over:

1. **Flat-key collision.** A key added under a feature namespace (`Feature.widget: "Widget"` in `feature.json`) reads as scoped and safe, but i18n lookups are flat — it collides with a top-level `widget` already defined in the shared locale file. The namespace prefix does not protect it.
2. **Semantic-equivalent duplicates that evade the value grep.** A re-phrasing carries the same meaning as an existing key without matching its text. `"Must be at least {min}"` duplicates an existing `"Min: {val}"` message; `"Must be a valid number"` duplicates an existing generic "invalid value" message. The value grep alone cannot catch these — judge every new key by meaning, not just exact text, and grep for the concept as well as the literal string.

**No exemptions.** "It's a validation message," "it's a config label," and "the wording is slightly different" are the three rationalizations that let semantic duplicates through — none of them is valid. This applies equally to nouns, labels, headings, sentences, action phrases, and validation/parametric/interpolated messages.

**Any duplicate surfaced in the audit table is a FINDING, never just a row annotation.** The fix is always the same: delete the new key and reuse the existing one at the call site (e.g. call the shared key directly rather than through the feature namespace). The value grep is necessary but not sufficient — a clean "no hit" result passes only this box; it does not pass §I4 or §I5 below, which are walked per key regardless of the grep outcome.

### §I4. Key name matches the value (or an established short form)

The key should let a reader predict the English value without opening the file. Convention: key matches value in camelCase, unless the value is long, in which case the key is a noun-phrase plus an established short-form suffix.

| Key | Value | Notes |
|-----|-------|-------|
| `widget` | `"Widget"` | direct camelCase match |
| `advanceWidgetWindow` | `"Advance Widget Window"` | direct camelCase match |
| `deleteWidgetMessage` | `"Are you sure you want to delete this widget? …"` | short form: noun + established suffix |
| `cancelGadgetDescription` | `"Cancelling this gadget will…"` | short form: subject + established suffix |

Grep the target repo for which short-form suffixes it already uses (do not hardcode a list from memory or from another project) — cite 2-3 existing examples of a suffix before treating it as established. Flag any suffix invented for this PR when an equivalent already exists in the codebase.

**Anti-patterns to flag:**
- A suffix baked into the key that the value itself doesn't carry — `widgetSection: "Widget"` bakes a "Section" grouping into the key with nothing in the value to justify it. Rename the leaf, or nest it under an object whose own key expresses the grouping.
- Generic container leaves (`title`, `description`, `text`, `label`, `name`) under a nested object: `someFeature: { title: "Some Feature", description: "…" }` — both leaves are generic. Flatten to top-level keys whose names match (or short-form) the value: `someFeature: "Some Feature"` and `someFeatureDescription: "…"`.
- A suffix the repo doesn't already use (invented synonyms) when an established equivalent exists — grep first, per above.

This audit applies to pre-existing entries in any file the diff is touching, not only newly added keys.

### §I5. Generic nouns and labels belong in the shared namespace

A generic noun, status word, short label, or section/card heading that any sibling feature could plausibly reuse belongs in the project's shared/common locale file, not the feature file — **even when it is not yet duplicated anywhere**. Grep the repo to identify which locale file actually plays the shared role (its name varies by project; treat it as "the shared locale file," not a fixed filename).

This box is judged **independently of the §I3 duplicate grep**. A "no match" result from the value grep is not a pass here: a generic noun like "Header," "Notes," or "Total" belongs in the shared file whether or not a matching key exists there today — the question is placement, not present duplication.

Watch for a bare noun added to a feature file sitting next to other feature keys — neighboring precedent is not a pass. Check the key against its real peers: if the other section titles in the same component are read from the shared namespace as plain common-noun labels, a new bare-noun heading dropped into the feature file beside them is a placement finding, not conformance with its neighbors.

Any single common word — noun or verb — that a sibling feature could plausibly want with the same meaning qualifies as "generic": not just `title`/`description`/`text`/`label`, but domain-neutral words like `person`, `member`, `date`, `time`, `image`, `total`. If you can imagine another feature wanting the same word with the same meaning, it belongs in the shared file at the top level, not nested under the feature's namespace.

A key that, after this check, is genuinely feature-specific is a PASS with the reasoning cited — never record it as N/A. This box is N/A only when the diff adds no new keys at all.

### §I6. Labels are plain keys; an ICU plural is for a real count

A fixed label, heading, column title, tab or nav item is a plain string key, one key per form the screen shows:

```json
"addOn": "Add-on",
"addOns": "Add-ons"
```

A message that shows a number is an ICU plural. It uses `#` for the formatted count and is read with the real count variable:

```json
"orderCount": "{count, plural, one {# order} other {# orders}}"
```

```ts
t('orderCount', { count: orders.length })   // never { count: 2 } to get the word "Orders"
```

Never pass a literal count (`count: 0`, `1`, `2`) to get a word form out of a plural message. `literal-plural-count.sh` lists every translation call in the diff that does, including calls written across several lines; each hit gets a verdict, and the usual fix is a plain label key.

**Why, in a line a finding can carry:** ICU, FormatJS and next-intl define `#` as the formatted count and describe plural messages as choosing on a number, and none describes them as a way to pick a label; Mastodon's react-intl locale file keeps labels plain (`"account.posts": "Posts"`) and gives its counts their own plural key (`"account.statuses_counter"`); and a made-up count makes the label depend on how each translator fills every CLDR plural form (Arabic has zero, one, two, few, many and other), branches nobody sees on screen. A review finding on this box says the same short why, not only the rule.

**Flag the opposite too:** a message that shows a real count as two keys chosen at the call site (`count === 1 ? t('widget') : t('widgets')`), or as one string with no plural (`"{count} widgets"`). That is one ICU plural read with the real count. Two label keys (`addOn`, `addOns`) used where each screen position always shows the same form are not this.

**A neighbouring key stored as a plural message and read with a literal count is a pre-existing miss, not precedent.** A new label stays a plain key.

### §I7. Never concatenate translations

Do not join two translatable fragments at the call site: `t('edit') + ' ' + t('widget')` or the template-literal equivalent `${t('edit')} ${t('widget')}`. Word order varies across languages, so concatenation produces grammatically broken output the moment a language reorders verb and noun.

**The same rule applies to a new key whose English value is `[verb] [noun]`.** A key like `enableWidgetCredits: "Enable Widget Credits"` bakes the concatenation into the key itself — it bypasses word-order handling exactly the way runtime string-joining would. Decompose it into an action template plus the noun key: `t('actions.enableSomething', { something: t('widgetCredits') })`, using an existing or newly-added parameterized action key (the file holding these varies by project — call it the action-template file, and grep the repo to find it).

**Mandatory decomposition check, for every new key whose value is `[transitive verb] [domain noun]`:**
1. Is there already a key for the noun (`widget`, `gadget`, `sprocket`)? Usually yes.
2. Is there an existing parameterized action key for the verb (something like `<verb>Something`)? Grep the action-template file. If not, adding one is a one-line addition (`enableSomething: "Enable {something}"`), not a reason to bake the phrase into a one-off key.
3. Drop the concatenated key; the call site becomes `t('actions.<verb>Something', { something: t('<noun>') })`.

```ts
// Good
t('actions.editSomething', { something: t('widget') })
t('actions.addSomething', { something: t('gadget') })

// Bad: flag this
`${t('edit')} ${t('widget')}`
t('edit') + ' ' + t('widget')
```

**Not concatenation: a translated label followed by a runtime data value.** This rule targets gluing two or more *translatable* fragments. A translated label plus a data value — a date, number, currency code, id, name — is ordinary interpolation, not a §I7 violation: `${t('dueDate')}: ${formattedDate}` is fine, do not flag it. The test: is EVERY joined piece a translatable word? If any piece is data, it's interpolation, not concatenation.

**Do not let this carve-out invent a redundant composite key.** A new key of the shape `fooWithBar: "Foo: {bar}"` or `fooWithBar: "Foo ({bar})"` that re-bakes an existing base label (`foo`) back in with a placeholder is a redundant-key smell — it duplicates the base key for no benefit. Flag it and have the author reuse the base label, interpolating the data value at the call site instead.

**Caveat — a verb phrase still uses the action template even when its slot is data.** The label-plus-data carve-out above is for nouns/labels followed by data (`dueDate`, `amountDue`). It does not license a one-off key for a verb phrase whose slot happens to be data. `"Pay {amount}"` starts with the transitive verb "Pay," so it belongs in the action-template file as `actions.paySomething: "Pay {something}"`, called with the formatted amount as `something` — not a standalone `payAmount: "Pay {amount}"` key. The verb decomposition rule applies whether the slot is a noun or a data value; the verb is what forces the action-template path. A single interpolated key outside the action-template file is only correct for a non-verb phrase that is one translatable sentence unit with a data slot and duplicates no existing base label — e.g. a full greeting like `"Welcome back, {name}"`.

### §I8. Text shown to people is never also an identifier

A filter offers "Other" for records with no category and uses the same string as the option's value: the link reads `?category=Other` and the code compares against `"Other"`. It works until the screen is translated. Then the label either stays in the source language, or it changes and every saved link and comparison stops matching. Keep a key for the value (`other`) and translate it only where it is shown.

### §I9. No grammar attached to a placeholder

A placeholder reaches the translator as `{name}`, a value they can't see or inflect. `"{name}'s plan"` assumes the English possessive, `"{count}th"` the English ordinal, `"a {thing}"` the English article: each is wrong in a language that marks the same idea another way (a case ending, a preposition, a different ordinal). Write the sentence so the placeholder stands alone: `"The plan for {name}"`, `"Position: {count}"`. An ordinal that has to be an ordinal is a `selectordinal` message, which carries the suffix in the message where the translator can change it. `placeholder-grammar.sh` lists added possessive and ordinal-suffix shapes in locale files; articles and agreement are judged by reading.

### §I10. One term, one spelling, on every screen

A term the product renames (`Addons` to `Add-ons`) is renamed everywhere people read it, not only in the strings the change was about: a button, a drawer title or an empty state left in the old spelling is what a tester finds next. Diff sweeps read only added lines, and the stale spelling sits in lines the diff never touched, so `term-spellings.sh` reads the whole source-locale tree and lists every word written in more than one spelling once case and hyphens are set aside, with each place of each spelling that is not the most used one. Two spellings with two meanings (`checkout` the purchase, `check-out` the departure) are a verdict, not a change. Spellings that differ by a space (`add ons`) are judged by reading.
