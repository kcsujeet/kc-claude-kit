---
type: regex
target: last_message
pattern: "(^|\\n)(- (🔴|🟠|🟡)[^\\n]*payments_controller\\.rb|[^\\n]*payments_controller\\.rb[^\\n]*(\\n- (?![^\\n]*\\w\\.(rb|ts|js|py|go)\\b)[^\\n]*)*\\n- (🔴|🟠|🟡)(?![^\\n]*\\w\\.(rb|ts|js|py|go)\\b))[^\\n]*(belong|another|other order|different order|any order|tied|link|match|table-wide|whole table|all payments|every payment|unscoped|not scoped|order\\.payments)"
flags: i
---
