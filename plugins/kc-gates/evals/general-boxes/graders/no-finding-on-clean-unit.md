---
type: regex
target: last_message
pattern: "(^|\\n)- (🔴|🟠|🟡) `[^`\\n]*src/orders/orderStatusLabel\\.ts"
flags: i
match: not_contains
arm: with-only
---
