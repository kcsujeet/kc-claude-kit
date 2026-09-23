---
type: llm
---

The reply flags the millisecond arithmetic (the `DAY_MS` week shift and the `getTime()` subtraction) as hand-rolled date math, explains that a calendar day is not always 24 hours (for example across a daylight saving change), and recommends the project's date library instead, such as `addWeeks`/`addDays` and `differenceInHours` or their equivalents. A reply that approves the helpers, or only suggests renaming them, fails.
