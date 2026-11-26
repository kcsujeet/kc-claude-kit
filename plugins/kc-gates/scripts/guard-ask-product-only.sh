#!/usr/bin/env bash
# PreToolUse hook (AskUserQuestion): a question to the person is only for what is theirs to decide
# (a product, scope or irreversible call, or which of two readings they meant). A code-level choice
# is the agent's: the working agreement says "Any other choice of approach is yours". It denies a
# question that
#   - holds code or review words (the regex below: backtick, path, file name, section id, kc- name,
#     a gate's name), since it then does not stand alone for someone who has not read the review; or
#   - does not begin "Product:", "Scope:", "Irreversible:" or "Intent:", naming its kind.
# The question, header and every option label and description are checked.
#
# Input: the PreToolUse payload on stdin (matcher AskUserQuestion). Output: the deny JSON, nothing
# otherwise. Always exits 0, and allows without jq.
# Hook schema: https://code.claude.com/docs/en/hooks
set -u

command -v jq >/dev/null 2>&1 || exit 0
payload=$(cat)

deny_question() {
  jq -cn --arg reason "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
  exit 0
}

questions=$(printf '%s' "$payload" | jq -c '.tool_input.questions[]? | {q: (.question // ""), all: ([.header, .question, (.options[]? | .label, .description)] | map(select(. != null)) | join("\n"))}')
[ -n "$questions" ] || exit 0

code_or_review_word_pattern='`|§|[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\.[A-Za-z]{1,5}\b|\.(rb|tsx?|jsx?|sh|md|json|ya?ml|py|go|rs)\b|(^|[[:space:]])(~|\.{1,2})?/[A-Za-z]|\bkc-[a-z]|review-conventions|\b(naming|clarity|structure|simplicity|testing|correctness|security|verification|project-conventions)[ -]gate\b'
kind='^[[:space:]]*(product|scope|irreversible|intent):'

shopt -s nocasematch
while IFS= read -r record; do
  matched_word=$(printf '%s' "$record" | jq -r '.all' | grep -Eio "$code_or_review_word_pattern" | head -1)
  if [ -n "$matched_word" ]; then
    deny_question "Blocked by the kc-gates plugin: this question uses code or review words (\"$matched_word\"). A code-level choice (a constant, where a helper lives, what to do about a finding) is yours: settle it with the fewest moving parts, record it, and go on. Ask only a product, scope or irreversible call, in plain words the person can answer without having read the review: what they will see or what changes for them."
  fi
  [[ $(printf '%s' "$record" | jq -r '.q') =~ $kind ]] \
    || deny_question "Blocked by the kc-gates plugin: the question does not say which decision of the person's it is. Begin it with \"Product:\" (what users see), \"Scope:\" (past the request), \"Irreversible:\" or \"Intent:\" (two readings of what they want). If it is none of these, it is yours to settle: choose the option with the fewest moving parts, say so in a line, and go on."
done <<< "$questions"
exit 0
