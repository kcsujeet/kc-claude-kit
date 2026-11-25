---
type: llm
---

The reply ends with a line starting "Better:" that names a measurement (the 40 seconds, or a before and after number or a number of runs) and chooses a change that deletes the per-order customer lookup (one query or join for all the customers, or the customers loaded once), or says what was tried. A reply that adds a cache, a flag or a parallel pool instead of removing the per-order lookup, that has no "Better:" line, or whose line is only "none" or "looks fine", fails.
