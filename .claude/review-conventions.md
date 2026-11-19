# Review conventions

Calls the owner settled for this repo. They win over the built-in rules when the two disagree.

## Rules

### R1. A one-use, one-expression shell check stays inline

Write a check used once and made of one expression (a `grep`, a string or file test) inline, in an `if ...; then ...; fi`, not behind a one-line predicate function. The `if` shape already reads as the question, so the naming rule for multi-operand conditions is met without a helper.

Fails: `meta_names_pr() { grep -qx "PR=$2" "$1"; }` with one caller. Passes: `if [ -n "$number" ] && ! grep -qx "PR=$number" "$meta"; then continue; fi`.

## Gate checklist

- [ ] R1 No shell function wraps a single expression that has one caller; such checks are inline in an `if`. (N/A: no shell script in the diff)
