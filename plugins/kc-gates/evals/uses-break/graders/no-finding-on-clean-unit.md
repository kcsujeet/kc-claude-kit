---
type: regex
target: last_message
pattern: "(^|\\n)- (🔴|🟠|🟡)[^\\n]*summary\\.ts"
flags: i
match: not_contains
---
