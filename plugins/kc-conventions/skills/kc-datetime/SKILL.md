---
name: kc-datetime
description: "Date and time conventions for source files: no hand-rolled date math, ISO 8601 with offset, `new Date()` in render, timezone, week start, hour format, locale formatters. Use when writing or reviewing code that parses, formats, compares, shifts, serializes or stores a date, time or timezone."
user-invocable: false
paths:
  - "**/*.{ts,tsx,js,jsx,mjs,cjs,rb,py,swift,go,java,kt,php,cs,rs}"
---

# Dates and times

## Contents

- Review checklist
- Sweeps

## Review checklist

- [ ] Tick every box for each construct you add or change. Report each: PASS, FAIL (file:line) or N/A (why).

- [ ] §D1 No hand-rolled date/time math (`split(':')` parsing, `new Date(str)`, `getTime()` arithmetic, `+86_400_000`, `padStart` formatting); use the project's date library. (N/A: no date/time logic)
- [ ] §D2 (soft) A start+end range uses the repo's shared range-formatting helper, not a hand-composed `${format(start)} - ${format(end)}`. (N/A: no range rendered, or no such helper)
- [ ] §D3 An instant sent to a backend, URL or storage is full ISO 8601 with offset, not `yyyy-MM-dd` or an offsetless local string; date-only is fine for genuinely date-only fields.
- [ ] §D4 Every date/time truncated from an instant is classified as serialized value (§D3), round-trip key (parse matches locality) or comparison (same form both sides). (N/A: no instant truncated)
- [ ] §D5 A `new Date()` in render or a memo is genuinely per-render or has a stable, coarse dependency; it is not frozen for the mount or a dependency that changes every render.
- [ ] §D6 Timezone, week start and 12/24-hour format come from user/app settings, never hardcoded or inferred from locale alone; earliest/latest uses the library's `max`/`min`.
- [ ] §D7 No locale formatter (`Intl.DateTimeFormat`, `toLocaleString`, `toLocaleDateString`) runs without an explicit time zone when the app has one configured.

- Examples and edge cases per box: references/detail.md (read when a box is unclear).

## Sweeps

- [ ] Save the diff under review to a file and run the script over it; `-` reads the diff from stdin. No other sweep is bundled for this topic.

- `added-lines.sh` (citation map): every added line as `path:line: text`, with the source line number at the head SHA. Cite every finding's line from this output or from a sweep hit, never from a position in the diff file.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/added-lines.sh" <diff-file>
  ```
