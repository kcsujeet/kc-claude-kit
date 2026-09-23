---
name: datetime-ms-arithmetic
description: A review request for TypeScript that shifts and diffs dates with millisecond arithmetic fires the datetime skill, and the reply flags the arithmetic.
tags: [datetime, review, positive]
max_turns: 6
allowed_tools: [Skill, Read, Grep, Glob]
---

Can you review these two helpers? They are used for the booking calendar.

```ts
const DAY_MS = 24 * 60 * 60 * 1000

export const getNextWeekStart = (weekStart: Date): Date => new Date(weekStart.getTime() + 7 * DAY_MS)

export const getHoursBetween = (start: Date, end: Date): number =>
  (end.getTime() - start.getTime()) / 3_600_000
```
