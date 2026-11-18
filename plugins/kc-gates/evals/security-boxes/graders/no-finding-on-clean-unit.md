---
type: regex
target: last_message
pattern: "(^|\\n)- (🔴|🟠|🟡)[^\\n]*receipts_controller\\.rb"
flags: i
match: not_contains
arm: with-only
---
