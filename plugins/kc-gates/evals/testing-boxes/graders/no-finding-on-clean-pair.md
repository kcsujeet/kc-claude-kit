---
type: regex
target: last_message
pattern: "memberPrice(\\.test)?\\.ts[^\\n]*(test|assert|expect)"
flags: i
match: not_contains
arm: with-only
---
