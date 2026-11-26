#!/usr/bin/env bash
# PreToolUse hook (AskUserQuestion): a question to the person is for what is theirs to decide: a
# product call (what users see), behaviour the task didn't ask for, scope past the request, an
# irreversible action, or which of two readings they meant. A code-level choice (a constant to
# keep, where a helper lives, what to do about a finding) is the agent's: it settles it with the
# fewest-moving-parts rule, records it and goes on (the working agreement's "Any other choice of
# approach is yours"). Two deterministic signs a question is the second kind, either denies it:
#   1. Review jargon or code in it: a backtick, a file path or file name, a section id (§X1), a
#      gate or skill name (kc-...), "gate", "finding", "round 2", "verdict", "checklist". The person
#      did not read the review, so such a question does not stand alone.
#   2. No stated kind: the question text must begin "Product:", "Scope:", "Irreversible:" or
#      "Intent:", naming which decision of theirs it is.
# The question text, its header and every option label and description are checked.
#
# Input: the PreToolUse payload on stdin. Output: the deny JSON, nothing otherwise. Always exits 0,
# and allows without jq.
# Hook schema: https://code.claude.com/docs/en/hooks
set -u

command -v jq >/dev/null 2>&1 || exit 0
payload=$(cat)
[ "$(printf '%s' "$payload" | jq -r '.tool_name // empty')" = AskUserQuestion ] || exit 0

deny() {
  jq -cn --arg reason "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
  exit 0
}

# One record per question: the text that must start with a kind, then all words shown to the person.
questions=$(printf '%s' "$payload" | jq -c '.tool_input.questions[]? | {q: (.question // ""), all: ([.header, .question, (.options[]? | .label, .description)] | map(select(. != null)) | join("\n"))}')
[ -n "$questions" ] || exit 0

jargon='`|§|[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\.[A-Za-z]{1,5}\b|\.(rb|tsx?|jsx?|sh|md|json|ya?ml|py|go|rs)\b|(^|[[:space:]])(~|\.{1,2})?/[A-Za-z]|\bkc-[a-z]|\bgates?\b|\bfindings?\b|\bnitpicks?\b|\bround [0-9]|\bverdicts?\b|\bchecklists?\b|review-conventions'

while IFS= read -r record; do
  text=$(printf '%s' "$record" | jq -r '.all')
  question=$(printf '%s' "$record" | jq -r '.q')
  hit=$(printf '%s' "$text" | grep -Eio "$jargon" | head -1)
  if [ -n "$hit" ]; then
    deny "Blocked by the kc-gates plugin: this question uses code or review words (\"$hit\"). A code-level choice (a constant, where a helper lives, what to do about a finding) is yours: settle it with the fewest moving parts, record it, and go on. Ask only a product, scope or irreversible call, in plain words the person can answer without having read the review: what they will see or what changes for them."
  fi
  printf '%s' "$question" | grep -Eiq '^[[:space:]]*(product|scope|irreversible|intent):' \
    || deny "Blocked by the kc-gates plugin: the question does not say which decision of the person's it is. Begin it with \"Product:\" (what users see), \"Scope:\" (past the request), \"Irreversible:\" or \"Intent:\" (two readings of what they want). If it is none of these, it is yours to settle: choose the option with the fewest moving parts, say so in a line, and go on."
done <<< "$questions"
exit 0
