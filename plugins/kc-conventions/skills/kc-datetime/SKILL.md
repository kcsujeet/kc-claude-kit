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

Tick every box for each construct you add or change. Report each: PASS, FAIL (file:line) or N/A (why).

- [ ] §D1 No hand-rolled date/time math: no `split(':')` time parsing, `new Date(str)` ad-hoc parsing, `getTime()` arithmetic, `+86_400_000`/`+7*24*60*60*1000` day-or-week shifts, manual `padStart` formatting, or reimplemented `addDays`/`startOfDay`/`endOfDay`/`isBefore`/`isAfter`/`isValid`; uses the project's date library (or its wrapper hook/util, if one exists). (N/A: no date/time logic)
- [ ] §D2 (soft) If the repo has a shared start/end range-formatting helper, a start+end range rendered together uses it rather than hand-composing `${format(start)} - ${format(end)}` with its own same-day/all-day branching. (N/A: no start+end range rendered, or repo has no such helper)
- [ ] §D3 An instant sent to a backend, a URL, or persisted state is serialized as full ISO 8601 with offset, not truncated to `yyyy-MM-dd` or sent as a local-time string with no offset. Date-only/time-only is fine when the field is genuinely date-only or time-only in the domain. (N/A: nothing serialized)
- [ ] §D4 Every truncated date/time derived from an instant is accounted for: the diff makes clear whether it is a **serialized value** (§D3 applies), a **round-trip key** (parse must match the format's locality), or a **comparison** (both sides same form and locality) — truncation is the trigger, not serialization. (N/A: no instant truncated to a date or time)
- [ ] §D5 A `new Date()` (or equivalent "now") evaluated in render or inside a memo is either genuinely per-render or has a stable, granularity-appropriate primitive in its dependency list — it is not frozen for the life of the mount, and the dependency is not a full ISO string or object identity that changes every render. (N/A: no "now" captured in render or memo)
- [ ] §D6 Timezone, week-start, and 12/24-hour formatting are treated as inputs from user/app settings, never hardcoded or inferred from locale/browser alone; server-rendered artifacts use stored settings, not browser context; the earliest/latest of several dates uses the date library's `max`/`min`, not `new Date(Math.max(...))`. (N/A: no timezone/week-start/hour-format/min-max logic)
- [ ] §D7 No locale formatter (`Intl.DateTimeFormat`, `Date.prototype.toLocaleString`/`toLocaleDateString`/`toLocaleTimeString`, or a library call that delegates to them) runs without an explicit time zone when the app has a configured one; without it the output follows the machine's zone. (N/A: no locale date formatting in diff, or the app has no configured time zone)

Examples and edge cases per box: references/detail.md (read when a box is unclear).

## Sweeps

Save the diff under review to a file and run the script over it; `-` reads the diff from stdin. No other sweep is bundled for this topic.

- `added-lines.sh` (citation map): every added line as `path:line: text`, with the source line number at the head SHA. Cite every finding's line from this output or from a sweep hit, never from a position in the diff file.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/added-lines.sh" <diff-file>
  ```
