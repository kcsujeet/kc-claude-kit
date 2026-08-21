# Datetime gate

> The conventions themselves are stated canonically in the kit's `rules/datetime.md`, which loads at authoring time. This file is the review side: the detection criteria and failure modes for grading a diff. Each box stays self-contained so a gate agent needs nothing but this file; when a convention changes, change `rules/datetime.md` first and update the affected boxes here to match.

Date/time is where generic correctness rules pay off the most, and where a change that "looks locally correct" most often hides a boundary bug: midnight, a DST transition, a user in another timezone, a week that starts on a different day than the reviewer's. Treat any diff that touches a date, a time, or a timezone as high risk and walk every box below, even when the change is two lines.

## Gate checklist

The datetime gate agent ticks every box against the diff. A box is FAIL if any matching construct violates it; the gate is FAIL if any box is FAIL. The whole gate is N/A only when the diff contains no date/time handling at all — the agent must state that explicitly rather than leaving the gate unaddressed.

- [ ] §D1 No hand-rolled date/time math: no `split(':')` time parsing, `new Date(str)` ad-hoc parsing, `getTime()` arithmetic, `+86_400_000`/`+7*24*60*60*1000` day-or-week shifts, manual `padStart` formatting, or reimplemented `addDays`/`startOfDay`/`endOfDay`/`isBefore`/`isAfter`/`isValid`; uses the project's date library (or its wrapper hook/util, if one exists). (N/A: no date/time logic)
- [ ] §D2 (soft) If the repo has a shared start/end range-formatting helper, a start+end range rendered together uses it rather than hand-composing `${format(start)} - ${format(end)}` with its own same-day/all-day branching. (N/A: no start+end range rendered, or repo has no such helper)
- [ ] §D3 An instant sent to a backend, a URL, or persisted state is serialized as full ISO 8601 with offset, not truncated to `yyyy-MM-dd` or sent as a local-time string with no offset. Date-only/time-only is fine when the field is genuinely date-only or time-only in the domain. (N/A: nothing serialized)
- [ ] §D4 Every truncated date/time derived from an instant is accounted for: the diff makes clear whether it is a **serialized value** (§D3 applies), a **round-trip key** (parse must match the format's locality), or a **comparison** (both sides same form and locality) — truncation is the trigger, not serialization. (N/A: no instant truncated to a date or time)
- [ ] §D5 A `new Date()` (or equivalent "now") evaluated in render or inside a memo is either genuinely per-render or has a stable, granularity-appropriate primitive in its dependency list — it is not frozen for the life of the mount, and the dependency is not a full ISO string or object identity that changes every render. (N/A: no "now" captured in render or memo)
- [ ] §D6 Timezone, week-start, and 12/24-hour formatting are treated as inputs from user/app settings, never hardcoded or inferred from locale/browser alone; server-rendered artifacts use stored settings, not browser context; the earliest/latest of several dates uses the date library's `max`/`min`, not `new Date(Math.max(...))`. (N/A: no timezone/week-start/hour-format/min-max logic)

## §D1. Never hand-roll date/time math

This is the single most common reinvention: a helper that parses `"HH:mm"` with `split(':')` and `Number()`, or computes hours from `(end.getTime() - start.getTime()) / 3_600_000`, when one import from the project's date library does the same work more readably and more correctly.

**Where to source it.** Grep the repo's imports to find which date library it uses (date-fns, dayjs, luxon, Temporal, or something else) — don't assume. If the project wraps that library in its own hook or util, grep for that wrapper and use it rather than importing the raw library directly; a wrapper usually exists to add locale, timezone, or formatting-convention awareness that a raw import would skip.

**Anti-patterns to flag and rewrite:**
- `time.split(':').map(Number)` to parse `"HH:mm"` — use the library's `parse`.
- `new Date(dateString)` for ad-hoc parsing — use the library's `parse`/`parseISO` with an explicit format.
- `(end - start) / 1000 / 60` or other `getTime()` arithmetic — use `differenceInMinutes` / `differenceInHours` / `differenceInDays` (or the equivalent in the library actually used).
- Adding or subtracting `86_400_000` (or `7 * 24 * 60 * 60 * 1000`) to shift a day or week — this is wrong across a DST boundary, where a calendar day is 23 or 25 hours, not always 24. Use `addDays`/`subDays`/`addWeeks`, which move wall-clock time correctly.
- Manual `padStart('0')` to format hours/minutes — use the library's `format`.
- Reimplementing `addDays`, `startOfDay`, `endOfDay`, `isBefore`, `isAfter`, `isValid` — these exist as named exports in every mainstream date library.

**Canonical replacement pattern** (parsing `"HH:mm"` and computing fractional hours between two times — a classic place people hand-roll):

```ts
import { differenceInMinutes } from 'date-fns/differenceInMinutes'
import { isValid } from 'date-fns/isValid'
import { parse } from 'date-fns/parse'

const hoursBetween = (start: string | undefined, end: string | undefined): number => {
  if (!start || !end) return 0
  const reference = new Date()
  const startDate = parse(start, 'HH:mm', reference)
  const endDate = parse(end, 'HH:mm', reference)
  if (!isValid(startDate) || !isValid(endDate)) return 0
  const diff = differenceInMinutes(endDate, startDate)
  return diff > 0 ? diff / 60 : 0
}
```

When you see manual splitting, coercion, or arithmetic doing time math, flag it and suggest the equivalent library call inline — the hand-rolled function's name almost always describes the intent the library helper already encodes.

**Comparison is the exception.** Comparing two `Date` objects with `<` / `>` / `>=` is fine, not a finding. What *is* a finding: comparing a `Date` to a string, or comparing two formatted strings, where the ordering only accidentally works.

## §D2. (Soft) A start+end range is its own helper

If the repo already has a shared helper for rendering a start+end range together, hand-composing `${format(start)} - ${format(end)}` with its own same-day/all-day branching is a finding even when it "looks right" — a purpose-built helper typically already encodes same-day vs multi-day collapsing, an all-day case, the separator, and time rendering, and a hand-rolled version tends to silently drop one of those cases. Grep the repo for such a helper before raising this; if none exists, this box is N/A rather than a mandate to build one.

## §D3. Serialize an instant as full ISO 8601 with offset

When sending a date/time to a backend, putting it in a URL/query string, or persisting it anywhere outside the render tree, default to a full ISO 8601 string with the offset — e.g. `'2026-05-27T19:17:20.548Z'` (or `+02:00` form). `.toISOString()` is the easy path; `format(date, "yyyy-MM-dd'T'HH:mm:ssXXX")` (or the equivalent in whatever date library the project uses) is the alternative when you need to control precision.

**The two failure modes this prevents:**
- **Truncating an instant to `yyyy-MM-dd`.** Most backends coerce a bare date to midnight in the *server's* timezone, so a "now"-relative window like "last 7 days" silently becomes a midnight-to-midnight window in the wrong zone, and a now-relative filter or dashboard count ends up off by up to a day right at the boundary.
- **Sending a local-time string with no offset.** Two clients in different timezones submitting the same wall-clock time end up storing two different instants — or, worse, the server assumes UTC and every time shifts silently.

**Date-only or time-only is legitimate** for fields that are genuinely date-only or time-only in the domain — a due-date that is just a calendar date, or a recurring time-of-day. The finding is specifically when an instant gets serialized as if it were a bare date.

**Canonical pattern:**
```ts
// Going to the backend / URL / persisted state — use full ISO with offset.
const startIso = new Date().toISOString()             // '2026-05-27T19:17:20.548Z'
const endIso = format(end, "yyyy-MM-dd'T'HH:mm:ssXXX") // '2026-05-27T19:17:20+00:00'
```

## §D4. Truncating an instant: account for what the string is for

A date-only string carries no offset, so what it means depends entirely on who reads it, and different readers disagree:

```ts
// TZ=America/Vancouver, now = 2026-07-29
const key = format(new Date(), 'yyyy-MM-dd')  // '2026-07-29'
parseISO(key)      // Wed Jul 29 2026 00:00:00 GMT-0700  ← local midnight
new Date(key)      // Tue Jul 28 2026 17:00:00 GMT-0700  ← UTC midnight, a day earlier locally
```

`format` writes the local date and `parseISO` reads a date-only string as local midnight, so that pair round-trips losslessly. `new Date(string)` reads a bare date as UTC. Mixing the two shifts every derived bound by a day for anyone west of UTC, and by nothing at all for anyone east of it — which is exactly why the bug survives local testing done from a UTC-or-east timezone and only surfaces for users west of it.

**Every truncated date derived from an instant gets examined, whether or not it leaves the render tree.** Serialization (§D3) is only one of three things such a string can be, and the other two are where the subtler bugs live:

| Purpose | What to check |
|---|---|
| **Serialized value** — sent to a backend, URL, or persisted state | §D3: an instant needs full ISO with offset; date-only only if the field genuinely is date-only |
| **Round-trip key** — formatted, then parsed back | The parse must match the format's locality (local `format` + local `parseISO`, or consistently UTC). Prefer deleting the round trip: a plain timestamp (§D5) needs no parse and has no locality |
| **Comparison** — string compared to string, or to a `Date` | Both sides must be the same form and locality. Comparing a formatted string to a `Date`, or two strings built by different code paths, only works by accident |

Flag any diff that:
- pairs `format(d, 'yyyy-MM-dd')` with `new Date(str)`, or relies on `parseISO` without the diff making that pairing obvious;
- round-trips a value through a string when a `Date` or a timestamp would do;
- truncates an instant for any purpose without the diff making that purpose clear.

The fix is usually to delete the round trip, not to document it.

## §D5. `new Date()` captured in render or inside a memo

`new Date()` evaluated during render is a fresh object every time, so it can never be a stable memo dependency on its own. Two ways this goes wrong:

- **Frozen.** A `new Date()` inside a memo whose other dependencies are all non-clock values gets computed once and never refreshes. A "yesterday" bound captured that way is wrong for anyone whose page stays open past midnight.
- **Never memoized.** Using the date itself (or a full ISO string of it) as a dependency defeats the memo, because it changes on every render — even `toISOString()` differs by milliseconds between calls.

When the value should refresh on a schedule, depend on a **primitive at that granularity** instead of the `Date` object or a full-precision string:

```ts
// Refreshes when the day rolls over, not on every render.
const todayStart = startOfDay(new Date()).getTime()

const config = useMemo(
  () => ({ maxDate: endOfDay(subDays(todayStart, 1)) }),
  [todayStart]
)
```

A timestamp needs no parse and has no locality, so most date libraries accept it anywhere they accept a `Date`. A formatted `yyyy-MM-dd` string can work as a key too, but only paired with a matching parse, which puts you back in §D4 — prefer the timestamp.

## §D6. Timezone, week-start, and hour-format are inputs, not constants

Three different clocks exist in any system with a browser, a configurable user/org, and a server, and they are not interchangeable: the browser's local clock, the user or organization's configured timezone, and the server's clock. Anything user-visible or query-bound must say which of the three it means — don't let a value silently cross from one to another.

- **Week boundaries** (`startOfWeek`, `endOfWeek`, and anything resolving a relative range like "this week") depend on the user or app's configured first-day-of-week setting. Hardcoding Sunday- or Monday-start silently gives the other convention's users the wrong seven days. Read the setting the way the rest of the app does; don't infer it from locale.
- **12-hour vs. 24-hour formatting** comes from a stored user/app setting, never from the display locale alone. A page in one language can still be set to the other hour format — locale controls wording (am/pm marker, month names), not the hour convention.
- **Server-rendered artifacts** — emails, PDFs, background jobs — have no browser context at all. Anything relying on "the viewer's timezone" or "the viewer's locale" is simply wrong there; only stored settings (the user's or org's configured timezone/format) are available to that code path.
- **Earliest/latest of several dates** should use the date library's `max`/`min`, not `new Date(Math.max(...dates.map(d => d.getTime())))`. The hand-rolled version is not wrong, but it is unnecessary reinvention of a one-line library call and is worth flagging alongside §D1.
