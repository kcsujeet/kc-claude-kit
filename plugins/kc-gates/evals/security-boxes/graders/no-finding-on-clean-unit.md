---
type: regex
target: last_message
pattern: "(^|\\n)(- (🔴|🟠|🟡)[^\\n]*receipts_controller\\.rb|[^\\n]*receipts_controller\\.rb[^\\n]*(\\n- (?![^\\n]*\\w\\.(rb|ts|js|py|go)\\b)[^\\n]*)*\\n- (🔴|🟠|🟡)(?![^\\n]*\\w\\.(rb|ts|js|py|go)\\b))[^\\n]*"
flags: i
match: not_contains
arm: with-only
---
