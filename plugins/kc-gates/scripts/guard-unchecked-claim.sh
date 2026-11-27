#!/usr/bin/env bash
# PreToolUse guard: blocks text that is about to be published when it states a fact about code,
# data, a setting or a tool and nothing in the turn looked at a source that mentions what the fact
# is about (kc-conventions:kc-check-claims: "check the source in this turn before stating what code
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
# A claim is checked when a tool call of the current turn (Read, Grep, a command, a query, a fetch,
# an agent; not an edit, not a call that publishes text) was given or returned text holding a
# distinctive word of the sentence (words of four letters or more, without stop words and generic
# code nouns; when none is left, any word of it). A sentence with no usable word is checked by any such call. Reads in
# earlier turns do not count: the source is read again, or the text says it is from earlier. A
# `git commit` message is also checked against the staged diff (git diff --cached in the payload's cwd).
#
# Claims about what instructions require and what a tool cannot do are check-reply-sources.sh's;
# they are left to it. Never blocks what it can't read: no jq, no transcript or no text exits 0.
#
# Input: the PreToolUse payload on stdin. Output: the deny JSON, or nothing. Always exits 0.
# Hook schema: https://code.claude.com/docs/en/hooks
set -u

# shellcheck source=lib/hook-input.sh
. "$(dirname "$0")/lib/hook-input.sh"

# shellcheck source=lib/reply-misses.sh
. "$(dirname "$0")/lib/reply-misses.sh"

command -v jq >/dev/null 2>&1 || exit 0

readonly MIN_SENTENCE_CHARS=15   # a shorter fragment is a heading or a label, not a claim
readonly MIN_WORD_CHARS=4        # a shorter word names nothing a source would hold
readonly EVIDENCE_CHARS_PER_CALL=60000 # a huge result is cut so it cannot dominate the evidence
readonly MAX_QUOTED_CLAIMS=2
readonly QUOTE_WIDTH=110

readonly QUANT='(^|[^[:alnum:]_])(every|all|always|never|none|only|each|nothing|nowhere|everywhere)([^[:alnum:]_]|$)'
readonly CODE_NOUN='(column|field|table|row|record|schema|migration|config|configuration|setting|flag|variable|function|method|class|module|endpoint|route|cache|callback|hook|job|worker|queue|query|index|constraint|validation|model|service|library|package|dependency|api|cli|sdk|file|test|spec|handler|middleware|serializer|controller|script|command|parameter|option|attribute|default|version|plugin|template|component|session|token|key|env|secret)'
readonly STATE_WORD='(set|unset|null|nullable|populated|present|defined|configured|enabled|disabled|required|optional|filled|blank|empty|deprecated|unused|cleared|reset|cached|retried|persisted|validated|indexed|scoped|stored)'
readonly CLAIM_VERB='(defaults? to|retr(y|ies)|clears?|returns?|raises?|throws?|caches?|ignores?|overrides?|expires?|skips?|falls? back|persists?|validates?|rejects?|says|sets|reads|writes|logs|triggers|fires|runs|loads|depends on|lives in|happens)'
readonly DET_NOUN="(^|[^[:alnum:]])(the|this|that|our|its|each|every|these|those)( [a-z0-9_-]+){0,2} ${CODE_NOUN}s?([^[:alnum:]]|\$)"
readonly NOUN_WORD="^${CODE_NOUN}s?$"
readonly COUNTED_THING='(^|[^[:alnum:]])([0-9]+|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|dozens?) (other )?(files?|rows?|records?|callers?|usages?|references?|call sites?|places?|tests?|specs?|columns?|tables?|endpoints?|routes?|jobs?|migrations?|occurrences?|matches|instances?|handlers?|consumers?|implementations?|models?)([^[:alnum:]]|$)'
readonly OWN_EDIT='(changed|edited|added|updated|touched|modified|created|deleted|renamed)'
# shellcheck disable=SC2016  # the backticks are Markdown code spans to match, not a command substitution
readonly TOKEN='`[^`]+`|[A-Za-z0-9_-]+\.(rb|js|jsx|ts|tsx|py|json|ya?ml|md|sh|sql|go|rs|toml|erb|env|lock|cfg|ini|php|java)([^[:alnum:]]|$)|[a-z0-9]+_[a-z0-9_]+|[a-z]+[A-Z][a-z]+|[A-Za-z_]+\(\)'
readonly DOES_PATTERN="(^|[^[:alnum:]])${CLAIM_VERB}([^[:alnum:]]|\$)"
readonly IS_STATE_PATTERN="(^|[^[:alnum:]])(is|are|was|were|gets|got) ${STATE_WORD}([^[:alnum:]]|\$)"
readonly NOT_A_FACT='(^|[^[:alnum:]])(would|could|might|may|should|probably|likely|perhaps|maybe|whether|let me|i.ll|i will|we can|we could|going to|plan to|want to|need to|unless|suppose|if)([^[:alnum:]]|$)|(^|[^[:alnum:]])i (added|changed|renamed|removed|updated|fixed|created|wrote|moved|deleted|edited|replaced|made)|(^|[^[:alnum:]])(you|your|user) (said|asked|wrote|mentioned|told|reported)|per your|according to you|^(always|never) (add|use|run|commit|call|set|put|write|check|keep|include|pass|store|log|expose|trust|rely|do|forget|hardcode|mutate|skip|ignore|return|rescue|read|test|wrap|prefer|avoid|ship|push)'
readonly UNVERIFIED='unverified|not verified|unconfirmed|not checked|haven.t (checked|verified|looked|confirmed)|have not (checked|verified|looked|confirmed)|didn.t (check|verify)|did not (check|verify)|from memory|i assume|i.m assuming|untested'
readonly STOP_WORDS=' that this with from have been were will they them then than into when what which where also does did can use used uses using one per via out off now yet too new old two here still just about over under after before while because since there their these those some more most other another such like make made makes need needs only never always every each none nothing nowhere everywhere sets reads writes runs loads logs says happens retries retry returns return raises throws clears cleared ignores skips default defaults true false not and the for are was has but all any its '
# Tool calls that look at nothing a claim is about, besides the edits (EDIT_CALLS): bookkeeping and the skill loader.
readonly BOOKKEEPING_CALLS=$'^(TodoWrite|TaskCreate|TaskUpdate|AskUserQuestion|SendMessage|ExitPlanMode|Skill)\t'

# What each publishing action carries as text.
readonly GIT_COMMIT='(^|[^[:alnum:]_.-])git[[:space:]]+(-[Cc][[:space:]]+[^[:space:]]+[[:space:]]+)*commit([[:space:]]|$)'
readonly GH_PUBLISH="${GH_COMMAND_START}((pr[[:space:]]+(create|edit|comment|review)|issue[[:space:]]+(create|edit|comment))([[:space:]]|\$)|api[[:space:]].*(-f|-F|--field|--raw-field)[[:space:]=]*.?body)"
readonly TRACKER_WRITE='mcp__.*((save|update|edit|create|add|post).*(comment|issue)|(comment|issue).*(save|update|edit|create|add|post))'

# is_text_matching <text> <extended regex>
is_text_matching() { printf '%s' "$1" | grep -Eq "$2"; }

payload=$(cat)
tool=$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null)
transcript=$(printf '%s' "$payload" | jq -r '.transcript_path // empty' 2>/dev/null)
[ -r "$transcript" ] || exit 0
published_text=""
case "$tool" in
  Bash)
    command_text=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)
    if is_text_matching "$command_text" "$GIT_COMMIT|$GH_PUBLISH"; then published_text=$command_text; fi ;;
  mcp__*)
    if printf '%s' "$tool" | grep -Eiq "$TRACKER_WRITE"; then
      published_text=$(printf '%s' "$payload" | jq -r '[.tool_input | .. | strings] | join("\n")' 2>/dev/null)
    fi ;;
esac
[ -n "$published_text" ] || exit 0

is_text_matching "$(printf '%s' "$published_text" | tr '\n' ' ' | tr '[:upper:]' '[:lower:]')" "$UNVERIFIED" && exit 0

# Sentences of the text, one per line: fenced code and blockquotes taken out,
# list and heading markers dropped, split after . ! ? followed by a space (a dot inside a file name stays).
sentences=$(printf '%s\n' "$published_text" \
  | awk '/^[ \t]*(```|~~~)/ { inside = !inside; next } !inside && !/^[ \t]*>/ { print }' \
  | sed -E 's/^[[:space:]]*([-*+]|[0-9]+[.)]|#+)[[:space:]]+//' \
  | sed -E 's/([.!?])[[:space:]]+/\1\
/g')

claims=()
while IFS= read -r sentence; do
  [ "${#sentence}" -ge "$MIN_SENTENCE_CHARS" ] || continue
  sentence_lower=$(printf '%s' "$sentence" | tr '[:upper:]' '[:lower:]')
  case "$sentence_lower" in *'?') continue ;; esac
  is_text_matching "$sentence_lower" "$NOT_A_FACT" && continue
  has_code_subject=false
  is_text_matching "$sentence" "$TOKEN" && has_code_subject=true
  is_text_matching "$sentence_lower" "$DET_NOUN" && has_code_subject=true
  has_noun=false
  is_text_matching "$sentence_lower" "(^|[^[:alnum:]])${CODE_NOUN}s?([^[:alnum:]]|\$)" && has_noun=true
  has_state_word=false
  is_text_matching "$sentence_lower" "(^|[^[:alnum:]])${STATE_WORD}([^[:alnum:]]|\$)" && has_state_word=true
  has_anchor=false
  if [ "$has_code_subject" = true ] || [ "$has_noun" = true ] || [ "$has_state_word" = true ]; then has_anchor=true; fi
  states_quantifier=false
  is_text_matching "$sentence_lower" "$QUANT" && states_quantifier=true
  states_count=false
  is_text_matching "$sentence_lower" "$COUNTED_THING" && ! is_text_matching "$sentence_lower" "$OWN_EDIT" && states_count=true
  says_what_it_does=false
  is_text_matching "$sentence_lower" "$DOES_PATTERN|$IS_STATE_PATTERN" && says_what_it_does=true
  if [ "$states_quantifier" = true ] && [ "$has_anchor" = true ]; then claims+=("$sentence")
  elif [ "$states_count" = true ]; then claims+=("$sentence")
  elif [ "$has_code_subject" = true ] && [ "$says_what_it_does" = true ]; then claims+=("$sentence")
  fi
done <<< "$sentences"
[ "${#claims[@]}" -gt 0 ] || exit 0

# What the turn looked at, one line per call: its input and what it returned, lowercased. Left out: edits,
# bookkeeping, and every call that publishes text, the one being judged included (a denied first try
# carries the claim's own words, so it can't be the read that backs the retry). A call publishes by its
# name and input only: a read whose output mentions a commit or an issue update still counts.
evidence_file=$(mktemp) || exit 0
trap 'rm -f "$evidence_file"' EXIT
jq -L "$(dirname "$0")/lib" -rs --argjson cap "$EVIDENCE_CHARS_PER_CALL" --arg git_commit "$GIT_COMMIT" --arg gh_publish "$GH_PUBLISH" --arg tracker_write "$TRACKER_WRITE" '
  include "typed-message";
  def joined_text: [.[]? | (.text? // empty)] | join(" ");
  def result_text: if type == "string" then . else joined_text end;
  def build_evidence_line($result): ((.input | tostring) + " " + $result) | .[0:$cap] | ascii_downcase | gsub("[\n\t\r]"; " ");
  def publishes:
    (.name | test("^" + $tracker_write; "i"))
    or (.name == "Bash" and ((.input.command // "") | test($git_commit + "|" + $gh_publish; "i")));
  turn_entries as $entries
  | ([$entries[] | select(.type == "user") | .message.content? | arrays | .[] | select(type == "object" and .type == "tool_result")
      | {key: .tool_use_id, value: (.content | result_text)}] | from_entries) as $results
  | $entries[] | select(.type == "assistant") | .message.content[]? | select(.type == "tool_use") | select(publishes | not)
  | .name + "\t" + build_evidence_line($results[.id] // "")
' "$transcript" 2>/dev/null \
  | grep -Ev "$EDIT_CALLS" | grep -Ev "$BOOKKEEPING_CALLS" > "$evidence_file" || true

# A commit message that describes the diff being committed checked it: the staged diff is evidence too.
commit_dir=$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)
if [ -n "$commit_dir" ] && is_text_matching "${command_text:-}" "$GIT_COMMIT"; then
  git -C "$commit_dir" diff --cached --no-color 2>/dev/null | head -c "$EVIDENCE_CHARS_PER_CALL" | tr '[:upper:]' '[:lower:]' | tr '\n\t\r' '   ' >> "$evidence_file" || true
fi

unchecked=()
for sentence in "${claims[@]}"; do
  sentence_lower=$(printf '%s' "$sentence" | tr '[:upper:]' '[:lower:]')
  claim_words=$(printf '%s' "$sentence_lower" | grep -Eo "[a-z0-9_]{$MIN_WORD_CHARS,}" | sort -u)
  distinctive=""
  fallback=""
  for word in $claim_words; do
    case "$STOP_WORDS" in *" $word "*) continue ;; esac
    stem=$word
    case "$stem" in *ss) ;; *s) stem=${stem%s} ;; esac
    fallback="$fallback $stem"
    is_text_matching "$word" "$NOUN_WORD" && continue
    is_text_matching "$word" "^${STATE_WORD}$" && continue
    distinctive="$distinctive $stem"
  done
  [ -n "$distinctive" ] || distinctive=$fallback
  if [ -z "$distinctive" ]; then
    [ -s "$evidence_file" ] && continue
  else
    has_evidence=false
    for stem in $distinctive; do
      grep -qF -- "$stem" "$evidence_file" && { has_evidence=true; break; }
    done
    [ "$has_evidence" = true ] && continue
  fi
  unchecked+=("$sentence")
done
[ "${#unchecked[@]}" -gt 0 ] || exit 0

quoted=""
for sentence in "${unchecked[@]:0:$MAX_QUOTED_CLAIMS}"; do
  quoted="$quoted \"$(printf '%s' "$sentence" | cut -c1-"$QUOTE_WIDTH")\""
done
print_pretooluse_deny "Blocked by the kc-gates plugin: this text states facts about code, data or a tool that nothing this turn looked at:$quoted. Check each now (Read, Grep, a query or a command that names what it is about), then publish it corrected, or say plainly in the text that it is unverified (kc-conventions:kc-check-claims)."
exit 0
