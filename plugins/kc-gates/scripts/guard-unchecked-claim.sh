#!/usr/bin/env bash
# PreToolUse guard: blocks text that is about to be published when it states a fact about code,
# data, a setting or a tool and nothing in the turn looked at a source that mentions what the fact
# is about (kc-conventions:kc-claims: "check the source in this turn before stating what code
# does"). Memory of the rule did not hold, so a hook holds it, at the actions that publish text:
#
#   - Bash: a `git commit` (its message), `gh pr create|edit|comment|review`, `gh issue
#     create|edit|comment`, and a `gh api` call that sets a `body`; the command is the text read.
#   - MCP tools whose name is a write on an issue or a comment (save, update, edit, create, add,
#     post; Jira, Linear and the like): every string of the call's input is the text read.
#
# It is not a Stop hook: that fires after the person has read the reply, so it can only repeat it.
#
# A sentence is a claim when it says one of these, about something named in the sentence (a
# backticked name, a file name, a snake_case or camelCase word, or "the/this/each <noun>" for a
# code noun: column, table, config, cache, library, job, endpoint, ...):
#
#   - a quantified fact: every, all, always, never, none, only, each, nothing, nowhere, with a code
#     noun, a named thing or a state word (set, null, required, cleared, ...) in the sentence
#     ("Every order has a currency set.")
#   - a count of code things: "14 callers", "3 files", "two tables"
#   - what a named thing does or is: "the cache is cleared on deploy", "this library retries by
#     default", "the config says X", "orders.currency is nullable"
#
# It leaves alone: questions, blockquotes and fenced code, hedged or planned statements (if, would,
# should, might, I will), the person's own words ("you said"), imperatives ("Never commit
# secrets"), a statement of what the turn itself changed ("I renamed"), and any text that says
# plainly it is unverified (unverified, haven't checked, from memory, I assume).
#
# A claim is checked when a tool call of the current turn that is not an edit (Read, Grep, a
# command, a query, a fetch, an agent) was given or returned text holding a distinctive word of the
# sentence (words of four letters or more, without stop words and generic code nouns; when none is
# left, any word of it). A sentence with no usable word is checked by any such call. Reads in
# earlier turns do not count: the source is read again, or the text says it is from earlier.
#
# Claims about what instructions require and what a tool cannot do are check-reply-sources.sh's;
# they are left to it. Never blocks what it can't read: no jq, no transcript or no text exits 0.
#
# Input: the PreToolUse payload on stdin. Output: the deny JSON, or nothing. Always exits 0.
# Hook schema: https://code.claude.com/docs/en/hooks
set -u

# shellcheck source=lib/hook-input.sh
. "$(dirname "$0")/lib/hook-input.sh"

command -v jq >/dev/null 2>&1 || exit 0

readonly QUANT='(^|[^[:alnum:]_])(every|all|always|never|none|only|each|nothing|nowhere|everywhere)([^[:alnum:]_]|$)'
readonly CODE_NOUN='(column|field|table|row|record|schema|migration|config|configuration|setting|flag|variable|function|method|class|module|endpoint|route|cache|callback|hook|job|worker|queue|query|index|constraint|validation|model|service|library|package|dependency|api|cli|sdk|file|test|spec|handler|middleware|serializer|controller|script|command|parameter|option|attribute|default|version|plugin|template|component|session|token|key|env|secret)'
readonly STATE='(set|unset|null|nullable|populated|present|defined|configured|enabled|disabled|required|optional|filled|blank|empty|deprecated|unused|cleared|reset|cached|retried|persisted|validated|indexed|scoped|stored)'
readonly CLAIM_VERB='(defaults? to|retr(y|ies)|clears?|returns?|raises?|throws?|caches?|ignores?|overrides?|expires?|skips?|falls? back|persists?|validates?|rejects?|says|sets|reads|writes|logs|triggers|fires|runs|loads|depends on|lives in|happens)'
readonly DET_NOUN="(^|[^[:alnum:]])(the|this|that|our|its|each|every|these|those)( [a-z0-9_-]+){0,2} ${CODE_NOUN}s?([^[:alnum:]]|\$)"
readonly NOUN_WORD="^${CODE_NOUN}s?$"
readonly COUNT='(^|[^[:alnum:]])([0-9]+|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|dozens?) (other )?(files?|rows?|records?|callers?|usages?|references?|call sites?|places?|tests?|specs?|columns?|tables?|endpoints?|routes?|jobs?|migrations?|occurrences?|matches|instances?|handlers?|consumers?|implementations?|models?)([^[:alnum:]]|$)'
# shellcheck disable=SC2016  # the backticks are Markdown code spans to match, not a command substitution
readonly TOKEN='`[^`]+`|[A-Za-z0-9_-]+\.(rb|js|jsx|ts|tsx|py|json|ya?ml|md|sh|sql|go|rs|toml|erb|env|lock|cfg|ini|php|java)([^[:alnum:]]|$)|[a-z0-9]+_[a-z0-9_]+|[a-z]+[A-Z][a-z]+|[A-Za-z_]+\(\)'
readonly SKIP='(^|[^[:alnum:]])(would|could|might|may|should|probably|likely|perhaps|maybe|whether|let me|i.ll|i will|we can|we could|going to|plan to|want to|need to|unless|suppose|if)([^[:alnum:]]|$)|(^|[^[:alnum:]])i (added|changed|renamed|removed|updated|fixed|created|wrote|moved|deleted|edited|replaced|made)|(^|[^[:alnum:]])(you|your|user) (said|asked|wrote|mentioned|told|reported)|per your|according to you|^(always|never) (add|use|run|commit|call|set|put|write|check|keep|include|pass|store|log|expose|trust|rely|do|forget|hardcode|mutate|skip|ignore|return|rescue|read|test|wrap|prefer|avoid|ship|push)'
readonly UNVERIFIED='unverified|not verified|unconfirmed|not checked|haven.t (checked|verified|looked|confirmed)|have not (checked|verified|looked|confirmed)|didn.t (check|verify)|did not (check|verify)|from memory|i assume|i.m assuming|untested'
readonly STOP=' that this with from have been were will they them then than into when what which where also does did can use used uses using one per via out off now yet too new old two here still just about over under after before while because since there their these those some more most other another such like make made makes need needs only never always every each none nothing nowhere everywhere sets reads writes runs loads logs says happens retries retry returns return raises throws clears cleared ignores skips default defaults true false not and the for are was has but all any its '

# What each publishing action carries as text.
readonly GIT_COMMIT='(^|[^[:alnum:]_.-])git[[:space:]]+(-[Cc][[:space:]]+[^[:space:]]+[[:space:]]+)*commit([[:space:]]|$)'
readonly GH_PUBLISH='(^|[^[:alnum:]_.-])gh[[:space:]]+((pr[[:space:]]+(create|edit|comment|review)|issue[[:space:]]+(create|edit|comment))([[:space:]]|$)|api[[:space:]].*body)'
readonly TRACKER_WRITE='mcp__.*((save|update|edit|create|add|post).*(comment|issue)|(comment|issue).*(save|update|edit|create|add|post))'

payload=$(cat)
tool_use_id=$(printf '%s' "$payload" | jq -r '.tool_use_id // empty' 2>/dev/null)
tool=$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null)
transcript=$(printf '%s' "$payload" | jq -r '.transcript_path // empty' 2>/dev/null)
[ -r "$transcript" ] || exit 0
reply=""
case "$tool" in
  Bash)
    command_text=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)
    if printf '%s' "$command_text" | grep -Eq "$GIT_COMMIT|$GH_PUBLISH"; then reply=$command_text; fi ;;
  mcp__*)
    if printf '%s' "$tool" | grep -Eiq "$TRACKER_WRITE"; then
      reply=$(printf '%s' "$payload" | jq -r '[.tool_input | .. | strings] | join("\n")' 2>/dev/null)
    fi ;;
esac
[ -n "$reply" ] || exit 0

printf '%s' "$reply" | tr '\n' ' ' | tr '[:upper:]' '[:lower:]' | grep -Eq "$UNVERIFIED" && exit 0

# Sentences of the text, one per line: fenced code and blockquotes taken out,
# list and heading markers dropped, split after . ! ? followed by a space (a dot inside a file name stays).
sentences=$(printf '%s\n' "$reply" \
  | awk '/^[ \t]*(```|~~~)/ { inside = !inside; next } !inside && !/^[ \t]*>/ { print }' \
  | sed -E 's/^[[:space:]]*([-*+]|[0-9]+[.)]|#+)[[:space:]]+//' \
  | sed -E 's/([.!?])[[:space:]]+/\1\
/g')

claims=()
while IFS= read -r sentence; do
  [ "${#sentence}" -ge 15 ] || continue
  lower=$(printf '%s' "$sentence" | tr '[:upper:]' '[:lower:]')
  case "$lower" in *'?') continue ;; esac
  printf '%s' "$lower" | grep -Eq "$SKIP" && continue
  has_token=false
  printf '%s' "$sentence" | grep -Eq "$TOKEN" && has_token=true
  has_subject=$has_token
  printf '%s' "$lower" | grep -Eq "$DET_NOUN" && has_subject=true
  has_noun=false
  printf '%s' "$lower" | grep -Eq "(^|[^[:alnum:]])${CODE_NOUN}s?([^[:alnum:]]|\$)" && has_noun=true
  has_state=false
  printf '%s' "$lower" | grep -Eq "(^|[^[:alnum:]])${STATE}([^[:alnum:]]|\$)" && has_state=true
  is_claim=false
  if printf '%s' "$lower" | grep -Eq "$QUANT" && { [ "$has_subject" = true ] || [ "$has_noun" = true ] || [ "$has_state" = true ]; }; then is_claim=true; fi
  if printf '%s' "$lower" | grep -Eq "$COUNT" && ! printf '%s' "$lower" | grep -Eq '(changed|edited|added|updated|touched|modified|created|deleted|renamed)'; then is_claim=true; fi
  if [ "$has_subject" = true ] && printf '%s' "$lower" | grep -Eq "(^|[^[:alnum:]])${CLAIM_VERB}([^[:alnum:]]|\$)|(^|[^[:alnum:]])(is|are|was|were|gets|got) ${STATE}([^[:alnum:]]|\$)"; then is_claim=true; fi
  [ "$is_claim" = true ] || continue
  claims+=("$sentence")
done <<< "$sentences"
[ "${#claims[@]}" -gt 0 ] || exit 0

# What the turn looked at: each tool call that is not an edit or bookkeeping, its input and what it returned.
evidence_file=$(mktemp) || exit 0
trap 'rm -f "$evidence_file"' EXIT
jq -L "$(dirname "$0")/lib" -rs --arg self "$tool_use_id" '
  include "typed-message";
  def result_text: if type == "string" then . else ([.[]? | (.text? // empty)] | join(" ")) end;
  turn_entries as $entries
  | ([$entries[] | select(.type == "user") | .message.content? | arrays | .[] | select(type == "object" and .type == "tool_result")
      | {key: .tool_use_id, value: (.content | result_text)}] | from_entries) as $results
  | $entries[] | select(.type == "assistant") | .message.content[]? | select(.type == "tool_use") | select(.id != $self)
  | select(.name | test("^(Edit|Write|MultiEdit|NotebookEdit|TodoWrite|TaskCreate|TaskUpdate|AskUserQuestion|SendMessage|ExitPlanMode|Skill)$") | not)
  | ((.input | tostring) + " " + ($results[.id] // "")) | .[0:60000] | ascii_downcase | gsub("[\n\t\r]"; " ")
' "$transcript" > "$evidence_file" 2>/dev/null || exit 0

unchecked=()
for sentence in "${claims[@]}"; do
  lower=$(printf '%s' "$sentence" | tr '[:upper:]' '[:lower:]')
  claim_words=$(printf '%s' "$lower" | grep -Eo '[a-z0-9_]{4,}' | sort -u)
  distinctive=""
  fallback=""
  for word in $claim_words; do
    case "$STOP" in *" $word "*) continue ;; esac
    stem=$word
    case "$stem" in *ss) ;; *s) stem=${stem%s} ;; esac
    fallback="$fallback $stem"
    printf '%s' "$word" | grep -Eq "$NOUN_WORD" && continue
    printf '%s' "$word" | grep -Eq "^${STATE}$" && continue
    distinctive="$distinctive $stem"
  done
  [ -n "$distinctive" ] || distinctive=$fallback
  if [ -z "$distinctive" ]; then
    [ -s "$evidence_file" ] && continue
  else
    seen=false
    for stem in $distinctive; do
      grep -qF -- "$stem" "$evidence_file" && { seen=true; break; }
    done
    [ "$seen" = true ] && continue
  fi
  unchecked+=("$sentence")
done
[ "${#unchecked[@]}" -gt 0 ] || exit 0

quoted=""
for sentence in "${unchecked[@]:0:2}"; do
  quoted="$quoted \"$(printf '%s' "$sentence" | cut -c1-110)\""
done
print_pretooluse_deny "Blocked by the kc-gates plugin: this text states facts about code, data or a tool that nothing this turn looked at:$quoted. Check each now (Read, Grep, a query or a command that names what it is about), then publish it corrected, or say plainly in the text that it is unverified (kc-conventions:kc-claims)."
exit 0
