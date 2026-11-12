---
type: regex
target: last_message
pattern: "priceRange\\.ts[^\\n]*(empty|bug|wrong|crash|edge)"
flags: i
match: not_contains
arm: with-only
---
