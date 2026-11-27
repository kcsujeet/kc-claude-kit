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

Tick every box for each construct you add or change. Report each: PASS, FAIL (file:line) or N/A (why).

- [ ] §T1 Every new behavior (a feature, prop, option, branch, or bug fix) has a test that exercises it, and a bug fix's test fails without the fix. Each case puts the code in a situation it really meets and fails when the behaviour it names breaks: a case that asserts what its own setup put there (a mock's stub, a constant), covers a state nothing real reaches, or still passes with its line broken FAILS. Each is tested once, at the unit that owns it: a test case the diff adds FAILS when it pins behaviour the diff didn't change, re-tests a shared unit's behaviour through a caller (the caller's test covers only its own wiring), or repeats a case the owning unit's tests already have. **Enumerate**: one line per test case the diff adds, naming the changed behaviour it pins and why this file owns it. Every test, assertion, check or guard the diff deletes, however it arrives (by hand, a restore of an older file, a revert, a merge, a regeneration, a refactor), is listed with the test or check that covers its behaviour now, or the removal is named as intended with its reason; a deletion with neither FAILS, and the behaviour it pinned counts as untested again. **Enumerate** these too: one line per removed test case or assertion in the diff. Code that nothing the repo runs can reach (no runner loads it, shown by a search of the test setup) passes when the pull request records the before and after it was checked with and names the gap; with neither recorded it FAILS. (N/A: no behavior change, no test case added and no test or check removed in the diff)
- [ ] §T2 No assertion on a class name as the evidence that a state is correct; assert what the user or a consumer observes (role, text, accessible state, a data attribute, an emitted value). A class that is itself the contract (a `className`-style prop the component forwards) is exempt. **Enumerate with the `class-assertions.sh` sweep** (see below). (N/A: only when `class-assertions.sh` returns 0 hits, stated as `grepped class assertions: 0 hits`)
- [ ] §T3 Every gate (a condition that mounts, enables, or routes something) is tested both ways: once with the condition met and once without, so deleting the gate fails a test. **Enumerate with the `surviving-mutants.sh` sweep's output** when the dispatch gives it: every surviving mutant, gate or not, gets its own verdict, the test that would fail on it, or no behaviour (the code changes nothing) and its deletion. Without it, or when it printed `not run`, each gate is named with the test covering each side. Two sides need no new case, and their verdict says which applies: the off side of an opt-in the change adds (existing callers' unchanged default), and a guard that only keeps an absent optional input from crashing (`onChange?.(value)`). Neither is a reason to ask for a test. (N/A: no gating logic, condition or early exit added or changed)
- [ ] §T4 Setup repeated across 2+ tests (the same render-plus-provider boilerplate, fixture literals, or datetime construction) is a local helper, not copy-paste. Setup means more than one plain expression: a repeated one-expression read stays inline at each test (simplicity §P11). A render or mount of the same component (`render(<X …/>)`, `mount(<X …/>)`) in 2+ tests is setup even when each is one call: it gets a local render helper with overrides. **Enumerate with the `repeated-render.sh` sweep** (see below), one verdict per hit. The converse also FAILS: a helper, locator or lazy fixture the diff adds that only one test uses, and a nested `describe` whose group shares no setup its siblings lack. (N/A: no setup, helper or `describe` added in the diff's tests, and `repeated-render.sh` returns 0 hits, stated as `grepped repeated renders: 0 hits`)
- [ ] §T5 A new or moved test sits beside the unit that owns the behaviour it asserts and is named after it; a caller's test file asserts only the caller's own wiring, never the cases of a unit it calls. Where the diff or a reviewer puts a test ("next to the existing case") is checked against this before it is followed. (N/A: no test file added or moved)
- [ ] §T6 Assertions are exact when the value is known (`toBe(3)`, `toEqual([0, 25, 50])`), not bounds or truthiness that a wrong value also satisfies (`toBeGreaterThan(0)`, `toBeTruthy()`, `toBeDefined()`). A tolerance is fine where the value is genuinely inexact (floating point, measured geometry), stated as `toBeCloseTo`. **Enumerate with the `loose-assertions.sh` sweep** (see below). (N/A: only when `loose-assertions.sh` returns 0 hits, stated as `grepped loose assertions: 0 hits`)
- [ ] §T7 A submit is tested per state: each form or request that saves user input has a test for every field state that behaves differently (at least clearing a saved value; see correctness §B5), and each test asserts the request body sent, not only the success path. (N/A: the diff adds or changes no submit of user input)
- [ ] §T8 Every test of an output the diff adds or changes (a response, a rendered page, an export, a message) asserts at least one value inside it that the change is responsible for, so an empty or field-less output fails the test. A test that asserts only a status code, that something rendered, or that no error was raised FAILS. A shared helper or example that checks responses counts as the test, and is held to the same rule. (N/A: the diff adds or changes no output and no test of one)
- [ ] §T9 Every expected record in a test is named, not re-derived: it is a record the test created and holds, or a lookup whose order ends on a unique key. A `first`/`last`/`take` (or `[0]` on a query result) over an order that can tie FAILS; the evidence names the ordering columns and why they cannot tie. **Enumerate**: grep the test diff for `.first`, `.last`, `.take` and `[0]` on query results, one verdict per hit. (N/A: `grepped first/last/take: 0 hits`)
- [ ] §T10 Time-dependent behaviour is tested at a frozen time: each test of code that compares against now (due, overdue, today, expiry, local hour) freezes the clock, and the code reads now from that clock, not from the database. A query the diff adds or changes that uses `CURRENT_TIMESTAMP`, `NOW()` or `CURRENT_DATE` for a comparison a test covers FAILS. **Enumerate**: grep the diff for those three, one verdict per hit. (N/A: `grepped database clock: 0 hits` and no time comparison added)
- [ ] §T11 Every record a new or changed test builds sets each attribute the code under test branches on; the evidence names the factory and confirms each such attribute is either set in the test or fixed (not sampled) in the factory. A branch-deciding attribute left to a factory that samples it FAILS. When the change handles data saved by older code or another client, a test builds that shape (the key missing, the null, the string), and the evidence names the real record or schema it was taken from. (N/A: the diff adds or changes no test that builds records, and handles no data saved by older code or another client)
- [ ] §T12 In every UI test the diff adds or changes, each `await` between the first user action and the last assertion is the testing library's own (a user event, `findBy*`, `waitFor`); a bare `await` on anything else (`navigator.clipboard.readText()`, a sleep, a direct fetch) FAILS, and so does hover or focus state an action leaves behind without an `unhover`/`blur` or a wait for its effect. A fix for a CI-only failure in such a test names the delay that reproduced it locally. **Enumerate**: grep the test diff for `await ` lines that are not `user.`, `findBy`, `findAllBy` or `waitFor`, one verdict per hit. (N/A: the diff adds or changes no UI test)
- [ ] §T13 When the diff moves or renames a value (an enum member, a type, a category, a status, a config key, a constant), every test file, factory and setup in the repo that hard-codes the old value is updated in the diff, not only the tests the change broke. A fixture still holding the old value FAILS even when the suite passes, and so does one the author listed and left because it passed. **Enumerate**: list the literals the diff's non-test lines remove or replace, grep every test and factory file for each, one verdict per hit. (N/A: the diff moves or renames no value, stated as `removed literals: none`)
- [ ] §T14 Every assertion the diff adds or changes compares the records found to the set expected (the whole collection to the expected one, or presence asserted first), and none dereferences a lookup that can return nothing (`find_by(...).attr`, `list.find(...)!.x`, `rows[0].field`), so a missing or wrong record fails with a message that names it, not a crash on nil or undefined. A sibling test's loop of per-item lookups is not a reason to keep that shape (simplicity §P13 defers to this box). **Enumerate**: grep the test diff for a member access, `!` or `[0]` directly on a lookup result, one verdict per hit. (N/A: the diff adds or changes no assertion on looked-up records)
- [ ] §T15 The failing test came first: it was seen to fail for the right reason, then pass; the project's check and test commands ran after each meaningful edit; after a mechanical edit across files (a rename, a scripted replace, a merge), run lint and the formatter on every file it touched before committing; after changing a shared unit's behaviour, run the full suites of every package that uses it. (N/A: no code change)
- [ ] §T16 No test is disabled, skipped or narrowed to reach green; a wrong test is changed as its own stated decision. (N/A: no test removed or weakened)
- [ ] §T17 No long-running process (dev server, watcher) was started to verify; the one-shot check and test commands were used. (N/A: nothing verified)
- [ ] §T18 Unhappy paths are covered on purpose: the empty collection, the expired token, the duplicate submit, the interrupted write. (N/A: no new behavior)
- [ ] §T19 A test that fails only in CI was reproduced locally (slow the suspected gap until it fails the way CI does) and the fix passes under the same delay. (N/A: no CI-only failure)
- [ ] §T20 When the end-to-end suite runs in a harness or fixture app, each headline user-facing feature also has one test driving the shipped app with its default configuration and seed data. (N/A: no such suite or feature)

Examples and edge cases per box: references/detail.md (read when a box is unclear).

## Sweeps

Save the diff under review to a file (`gh pr diff <num> > /tmp/review.diff`, or `git diff <default-branch>...HEAD > /tmp/review.diff`) and run each script over it; `-` reads the diff from stdin for the three test sweeps. Those three scan only added lines in test files (`KC_TEST_PATHS` in `scripts/lib/diff-lines.sh`: `*.test.*`, `*.spec.*`, `*_test.*`, `*_spec.*`, `test_*.py`, and anything under `test/`, `tests/`, `spec/`, `__tests__/` or `e2e/`). Each prints one `path:line: text` hit per line, where `line` is the new-side line number, and nothing else. Give every hit its own verdict, and state each receipt with its count, `0 hits` included.

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
