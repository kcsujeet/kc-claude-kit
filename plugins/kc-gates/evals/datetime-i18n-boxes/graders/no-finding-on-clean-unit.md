---
type: regex
target: last_message
pattern: "(^|\\n)- (🔴|🟠|🟡) `[^`\\n]*(formatDeliveryDate|deliverySummary)\\.ts"
flags: i
match: not_contains
---
