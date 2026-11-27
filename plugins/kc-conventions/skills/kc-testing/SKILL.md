---
name: kc-testing
description: "Testing conventions for test files and the code they cover: tests first, a test for every behavior and bug fix at its owning unit, exact assertions, no class-name assertions, gates tested both ways. Use when writing or reviewing tests, or any change that adds behavior or fixes a bug."
user-invocable: false
paths:
  - "**/*.{ts,tsx,js,jsx,mjs,cjs,rb,py,swift,go,java,kt,php,cs,rs}"
---

# Testing discipline

## Contents

- Review checklist
- Sweeps

## Review checklist

- [ ] Tick every box for each construct you add or change. Report each: PASS, FAIL (file:line) or N/A (why).

- [ ] §T1 Every new behaviour or fix has a test at its owning unit that fails if it breaks; list each case added and each test deleted with what covers it now (see §T1).
- [ ] §T2 No assertion on a class name as evidence of state; assert what a user or consumer observes (role, text, accessible state, emitted value); `class-assertions.sh` swept. (N/A: 0 hits)
- [ ] §T3 Every gate (a condition that mounts, enables or routes) is tested both ways so deleting it fails a test; each surviving mutant of `surviving-mutants.sh` gets a verdict (see §T3).
- [ ] §T4 Setup repeated across 2+ tests (render, fixtures, datetimes) is a local helper with overrides; a helper or `describe` only one test uses FAILS; `repeated-render.sh` swept, a verdict per hit.
- [ ] §T5 A new or moved test sits beside the unit that owns the behaviour and is named after it; a caller's test asserts only the caller's wiring. (N/A: no test file added or moved)
- [ ] §T6 Assertions are exact when the value is known (`toBe(3)`, `toEqual([0, 25])`), not `toBeTruthy()`/`toBeGreaterThan(0)`; `toBeCloseTo` for inexact values; `loose-assertions.sh` swept.
- [ ] §T7 A submit is tested per field state that behaves differently (at least clearing a saved value, §B5), asserting the request body sent, not only success.
- [ ] §T8 Every test of an added or changed output (response, page, export, message) asserts a value the change is responsible for; status-code-only or "rendered" assertions FAIL.
- [ ] §T9 Expected records in a test are named, not re-derived: no `first`/`last`/`take`/`[0]` over an order that can tie; list each hit with the ordering columns.
- [ ] §T10 Time-dependent behaviour is tested at a frozen time, and code reads now from that clock, not `CURRENT_TIMESTAMP`/`NOW()`/`CURRENT_DATE`; one verdict per grep hit.
- [ ] §T11 Records built in a test set every attribute the code branches on (named factory, confirmed set or fixed); data from older code or another client is built in its real shape.
- [ ] §T12 In UI tests every `await` between first action and last assertion is the testing library's (`user.`, `findBy*`, `waitFor`); bare awaits and leftover hover/focus FAIL; one verdict per hit.
- [ ] §T13 When a value (enum member, type, status, config key, constant) is moved or renamed, every test, factory and setup hard-coding the old one is updated; grep each removed literal.
- [ ] §T14 Assertions compare the records found to the set expected, and none dereferences a lookup that can return nothing (`find_by(...).attr`, `rows[0].field`); one verdict per hit.
- [ ] §T15 The failing test came first (seen failing for the right reason); checks ran after each edit, lint and formatter after mechanical edits, and every dependent suite after a shared-unit change.
- [ ] §T16 No test is disabled, skipped or narrowed to reach green; a wrong test is changed as its own stated decision. (N/A: no test removed or weakened)
- [ ] §T17 No long-running process (dev server, watcher) was started to verify; the one-shot check and test commands were used. (N/A: nothing verified)
- [ ] §T18 Unhappy paths are covered on purpose: the empty collection, the expired token, the duplicate submit, the interrupted write. (N/A: no new behavior)
- [ ] §T19 A test that fails only in CI was reproduced locally (slow the suspected gap until it fails the way CI does) and the fix passes under the same delay. (N/A: no CI-only failure)
- [ ] §T20 Where e2e runs in a harness or fixture app, each headline feature also has one test driving the shipped app with default configuration and seed data. (N/A: no such suite or feature)

- Examples and edge cases per box: references/detail.md (read when a box is unclear).

## Sweeps

- [ ] Save the diff under review to a file (`gh pr diff <num> > /tmp/review.diff`, or `git diff <default-branch>...HEAD > /tmp/review.diff`) and run each script over it; `-` reads the diff from stdin for the three test sweeps. Those three scan only added lines in test files (`KC_TEST_PATHS` in `scripts/lib/diff-lines.sh`: `*.test.*`, `*.spec.*`, `*_test.*`, `*_spec.*`, `test_*.py`, and anything under `test/`, `tests/`, `spec/`, `__tests__/` or `e2e/`). Each prints one `path:line: text` hit per line, where `line` is the new-side line number, and nothing else. Give every hit its own verdict, and state each receipt with its count, `0 hits` included.

- `added-lines.sh` (citation map): every added line as `path:line: text`, with the source line number at the head SHA. Cite every finding's line from this output or from a sweep hit, never from a position in the diff file.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/added-lines.sh" <diff-file>
  ```

- `class-assertions.sh` (§T2): added test lines referencing `toHaveClass`, `className` or `classList`. Receipt: `grepped class assertions: N hits`.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/skills/kc-testing/scripts/class-assertions.sh" <diff-file>
  ```

- `loose-assertions.sh` (§T6): added test lines holding a bound or truthiness matcher. Receipt: `grepped loose assertions: N hits`.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/skills/kc-testing/scripts/loose-assertions.sh" <diff-file>
  ```

- `repeated-render.sh` (§T4): inline `render(<X …/>)` or `mount(<X …/>)` lines of a component that appears on 2+ added lines of one test file, a helper's own render left out. Receipt: `grepped repeated renders: N hits`.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/skills/kc-testing/scripts/repeated-render.sh" <diff-file>
  ```

- `surviving-mutants.sh` (§T3), run by the review's caller, never by a gate: the dispatch gives its output, and the gate grades it. In a throwaway checkout of HEAD, it breaks each condition and early exit on the diff's added code lines one at a time (and swaps the two sides of a value fallback, `a?.b || c.d` or `??`, which a fixture that leaves one side empty never tells apart), runs the tests, and prints each break no test noticed, after a summary line. The caller runs it from the repo root, with the install command as `--setup` when a fresh checkout needs one, once per area with `--paths` set to its paths, before dispatching the gates. In a fix check it runs on the whole diff, so a test added for an earlier survivor is shown to catch it. It takes minutes, inside its `--max-minutes` budget (default 8), and lists every line the budget did not reach. Receipt: its summary line, then a verdict per survivor and per line not reached; `not run: <reason>` is stated as the receipt, and §T3 is then walked by hand.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/skills/kc-testing/scripts/surviving-mutants.sh" <diff-file> --test '<command>' [--setup '<command>'] [--paths '<regex>']
  ```
