---
type: regex
target: last_message
pattern: "(^|\\n)- (🔴|🟠|🟡)[^\\n]*OrderTotal\\.tsx"
flags: i
match: not_contains
---
