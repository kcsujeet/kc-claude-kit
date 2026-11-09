---
type: regex
target: last_message
pattern: "(^|\\n)- (🔴|🟠|🟡)[^\\n]*footers\\.ts"
flags: i
match: not_contains
arm: with-only
---
