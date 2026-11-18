---
type: regex
target: last_message
pattern: "(^|\\n)(- (🔴|🟠|🟡)[^\\n]*payments_controller\\.rb|[^\\n]*payments_controller\\.rb[^\\n]*(\\n- (?![^\\n]*\\w\\.(rb|ts|js|py|go)\\b)[^\\n]*)*\\n- (🔴|🟠|🟡)(?![^\\n]*\\w\\.(rb|ts|js|py|go)\\b))[^\\n]*((amount|paid_cents)[^\\n]*(client|param|request|browser|trust|tamper|sent|caller)|(client|param|request|browser|trust|tamper|sent|caller)[^\\n]*(amount|paid_cents))"
flags: i
---
