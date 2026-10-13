---
name: correctness
description: "Correctness conventions for source files in TypeScript, JavaScript, Ruby, Python, Swift, Go, Java, Kotlin, PHP, C# and Rust: logic errors (off-by-one, wrong operator, inverted condition, stale state or closure, wrong dependency array), unhandled edge cases (empty, null, zero, boundary values, timezone), data that does not match its declared type at a boundary, and regressions of bugs the repo already fixed. Use when writing or reviewing a change to conditions, loops, state, hooks or data crossing a boundary, or when hunting for bugs in a diff."
user-invocable: false
paths:
  - "**/*.{ts,tsx,js,jsx,mjs,cjs,rb,py,swift,go,java,kt,php,cs,rs}"
---

# Correctness

## Contents

- Rules
- Review checklist
- Review detail
  - §B1. Logic
  - §B2. Edge cases
  - §B3. Data shape
  - §B4. Regression
  - §B5. Every submitted value lands as intended
- Sweeps

## Rules

Code that reads well and is wrong is still wrong. Walk every change for the bugs a reader skims past.

- Consider the empty, null, zero and boundary input on every path you add or change, not only the value the feature was built for.
- Check every operator and condition for an off-by-one or an inversion: `<` against `<=`, `&&` against `||`, a negation that flips the meaning.
- Keep dependency arrays and closures current: an effect, memo, callback or handler reads the latest value of everything it uses.
- Do not let a cast hide a real type mismatch. When data crossing a boundary (an API response, props, storage) does not match its declared type, fix the type or parse the value.
- Before changing code, check the repo's history for a bug already fixed there (the changelog, dev logs, `git log -S <symbol>`), so the change does not bring it back.
- Trace every submitted field from its input, through any transform and the request payload, to what the receiving end does with it, for each state the user can leave it in: set, changed, cleared, left alone, invalid. Each state must arrive in a shape the receiver accepts and have the effect the user expects.

Detection criteria and per-box review failure modes live in the `## Review checklist` of the `correctness` skill (`conventions:correctness`), with the detail under its `## Review detail`. These rules are the statement of the convention; that checklist is how a diff gets graded against it.

## Review checklist

The correctness gate agent ticks every box against the diff. A box is FAIL if any matching construct violates the rule; the gate is FAIL if any box is FAIL. Each box states its own N/A condition.

- [ ] §B1 Logic: no off-by-one, wrong operator, inverted condition, stale state or closure (an effect, callback or handler reading a value captured before it changed), or wrong dependency array (a value the body reads is missing, or a listed value changes every render). (N/A: the diff adds or changes no condition, loop, index or range arithmetic, state update, closure, or dependency array)
- [ ] §B2 Edge cases: every added or changed path handles empty collections, null/undefined, zero, and boundary values (first, last, exactly at a limit), and every date or time the diff formats or parses uses the configured timezone rather than the machine's. (N/A: the diff changes no path that takes input, and formats or parses no date or time)
- [ ] §B3 Data shape: values crossing a boundary (an API response, props, storage, a URL or form value) match their declared type at runtime. A cast or `any` that lets a real mismatch through is a finding here; the syntax of the escape hatch itself is clarity §C17. (N/A: no value crosses a boundary in the diff)
- [ ] §B4 Regression: the diff does not reintroduce a bug the repo already fixed. The changelog, the dev logs (when the repo keeps them) and `git log -S <symbol>` were checked for every touched symbol, and the receipt names what was searched. (N/A: the diff only adds new files and touches no existing symbol)
- [ ] §B5 Every submitted value lands as intended: for each field the diff sends (a form, a request built from user input), the evidence traces it from the input, through the transform and the payload, to the receiver's handling (its parsing, the keys it accepts, its validations), for each state the user can leave it in: set, changed, cleared, left alone, invalid. Each state arrives in a shape the receiver accepts and has the effect the user expects. A field with no trace FAILS by default. The receiving code was read (in this repo or the backend's), and run when its effect is not plain from the code. (N/A: the diff sends no user-entered value)

**Point, do not double-report.** A removed export or a changed shared prop shape is structure §S10. A cast asserting a type the value does not have, as syntax, is clarity §C17. Duplicated markup, dead imports, or props threaded through and never read after a refactor are simplicity §P9. A locale formatter with no explicit time zone is datetime §D7. When a bug and one of those boxes describe the same line, report it once, under the closer fit, and name the other box in the evidence.

## Review detail

Bug rules for the diff under review. Covers five independent failure modes: logic that computes the wrong thing, inputs the code does not handle, data that is not the shape its type claims, a fix the repo already made being undone, and a submitted value that does not have the effect the user meant.

**Every finding is verified before it is reported.** Open the actual file at the actual line at the head SHA (`git show <sha>:<path>`) and confirm the bug exists there; a finding from a hunk alone, or from another agent's summary, is not verified. **A claim about library or platform behavior** (a date library, a recurrence library, React, `Intl`, a CSS framework, a remote API) **cites the documentation fetched or the installed source read this session**, inline in the finding. Cached knowledge drifts between versions.

### §B1. Logic

Walk each changed condition, loop and state update, and ask what it computes, not what it was meant to compute:

- **Off-by-one:** `<` against `<=`, `length` against `length - 1`, an exclusive end treated as inclusive, a loop that skips the first or last item.
- **Wrong operator:** `&&` where `||` was meant, `=` or `==` where `===` was meant, `??` where `||` was meant (or the reverse, when `0` or `''` is a real value).
- **Inverted condition:** a negation that flips the branch, an early return guarding the wrong case.
- **Stale state or closure:** an effect, callback, timer or event handler that captured a value and keeps reading it after it changed; a state update computed from the previous render's value where the functional form was needed.
- **Wrong dependency array:** a value the body reads is missing, so the effect or memo runs against a stale value; or a listed value is a new object every render, so it runs every time.

### §B2. Edge cases

For each changed path, feed it the inputs the feature was not built around: an empty array or string, `null` and `undefined`, `0`, a negative number, the first and last item, a value exactly at a limit. A path that throws, renders nothing useful, or computes a wrong result for one of them is a finding.

**Timezone.** When the app configures a time zone, a date formatted or parsed without it follows the machine's zone. `Intl.DateTimeFormat` without a `timeZone` option, or a string with no offset parsed by `new Date()`, is the common shape. Grep the repo for how it configures the zone before flagging, and cite it.

### §B3. Data shape

Check the declared type of every value that crosses a boundary against what actually arrives: the API contract, the props a caller passes, what storage returns, what a URL or form field holds (always a string). Drift between the contract and the type, an `as` cast that asserts the expected shape instead of checking it, and `any` carrying a wrong type through are findings here when the runtime value can differ from the type. State the mismatch: what the type says, what arrives, and where.

### §B4. Regression

Do not trust the PR description for this box; check the history. For every symbol the diff changes, search the changelog, the repo's dev logs if it keeps them, and `git log -S <symbol> --oneline` for an earlier fix to the same code. When one exists, read it and confirm the diff does not undo it (a guard removed, a boundary rule reverted, a workaround deleted without the cause being fixed). The receipt names the sources searched and the commits found, or `no prior fix found` with the search stated.

### §B5. Every submitted value lands as intended

A schema that accepts the right inputs is half the job. What matters is what each value becomes by the time the receiver saves it, and whether that is what the user meant. Walk every field the change sends, in every state the user can leave it in (set, changed, cleared, left alone, invalid), through three steps:

1. **The transform.** What does the form or schema output? A helper can quietly turn `''`, `null` or unparseable text into `undefined`.
2. **The payload.** What goes over the wire? `JSON.stringify` drops `undefined` keys, and on a PATCH a missing key usually means "no change".
3. **The receiver.** What does the endpoint do with it? Read its parsing, the keys it accepts, and its validations and callbacks; `''` may become `null`, which a numeric validation then rejects.

Illustrations of values that fail along the way, not a complete list:

- Clearing a field sends nothing on a PATCH, so the old value silently stays.
- `''` or `null` fails a validation, so the save errors instead of clearing.
- A key the receiver does not accept is ignored.
- A number sent as a string, a date without its offset, or a `0` the receiver reads as "unset".

When the effect is not plain from the code, run it: call the receiver's parser and validation with each state and record what comes back. The tests follow the same states (testing §T7).

## Sweeps

Save the diff under review to a file and run the script over it; `-` reads the diff from stdin. No other sweep is bundled for this topic.

- `added-lines.sh` (citation map): every added line as `path:line: text`, with the source line number at the head SHA. Cite every finding's line from this output or from a sweep hit, never from a position in the diff file.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/added-lines.sh" <diff-file>
  ```
