---
type: regex
target: last_message
pattern: "(^|\\n)- (🔴|🟠|🟡)[^\\n]*subject\\.ts"
flags: i
match: not_contains
arm: with-only
---
