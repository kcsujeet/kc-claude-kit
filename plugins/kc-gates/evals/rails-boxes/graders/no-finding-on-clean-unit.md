---
type: regex
target: last_message
pattern: "(^|\\n)- (🔴|🟠|🟡) `[^`\\n]*archive\\.rb"
flags: i
match: not_contains
---
