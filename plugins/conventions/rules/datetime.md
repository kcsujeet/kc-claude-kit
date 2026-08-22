---
paths:
  - "**/*.{ts,tsx,js,jsx,mjs,cjs,rb,py,swift,go,java,kt,php,cs,rs}"
---

# Dates and times

Date code that looks locally correct is where boundary bugs hide: midnight, a DST change, a user in another timezone, a week that starts on a different day.

- No hand-rolled date math. No `split(':')` parsing, no `getTime()` arithmetic, no `+86_400_000` day shifts, no manual `padStart` formatting, no reimplemented `addDays`/`startOfDay`/`isBefore`. Use the project's date library, or its wrapper if it has one.
- Serialize an instant as full ISO 8601 with offset. Date-only is fine only when the field is genuinely date-only in the domain.
- Account for every truncation. Know whether the truncated value is being serialized, used as a round-trip key, or compared, and keep both sides of a comparison in the same form and locality.
- `new Date()` in a render or a memo is either frozen or never memoized. Key off a day-granularity timestamp instead.
- Timezone, week start, and 12-versus-24-hour are **inputs** from user or org settings. They are never constants, and a customer's explicit setting always wins over anything inferred.
- Locale drives both text and ordering. Formatting is separate from language: a date can be German-ordered while the page is read in French, and the org's setting decides.
- Earliest and latest come from the date library's `max`/`min`, not a hand-rolled reduce.

Detection criteria and per-box review failure modes live in the code-review plugin's `references/datetime.md`. This file is the statement of the convention; that file is how a diff gets graded against it.
