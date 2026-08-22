---
paths:
  - "**/*.{ts,tsx,js,jsx,mjs,cjs,rb,py,swift,go,java,kt,php,cs,rs}"
---

# Testing discipline

The loop is not a formality at the end. A change is not done until it is green.

- Write the failing test first. Watch it fail for the right reason, then make it pass. A test that passed the moment you wrote it proved nothing.
- Run the project's check and test commands after each meaningful edit, not once at the very end when the cause of a failure is buried under ten changes.
- Never disable, skip, or narrow a test to reach green. If a test is wrong, say why before changing it, and change it as its own visible decision.
- Do not start a long-running process to "verify" a change. A dev server or watcher never exits; use the one-shot check and test commands.
- Tests live beside the code they cover, named after it.
- Cover the unhappy paths deliberately: the empty collection, the expired token, the duplicate submit, the interrupted write. The happy path is the one that already works.
- When a bug is fixed, the regression test comes with it in the same change, and it must fail without the fix.
