---
type: regex
target: last_message
pattern: "(^|\\n)(- (🔴|🟠|🟡)[^\\n]*payments_controller\\.rb|[^\\n]*payments_controller\\.rb[^\\n]*(\\n- (?![^\\n]*\\w\\.(rb|ts|js|py|go)\\b)[^\\n]*)*\\n- (🔴|🟠|🟡)(?![^\\n]*\\w\\.(rb|ts|js|py|go)\\b))[^\\n]*(twice|again|second|repeat|replay|re-award|idempot|every time|each time|already paid|double|re-?submit)"
flags: i
---
