#!/usr/bin/env bash
# PreToolUse guard for Bash: blocks GitHub review writes that lack the
# approval token.
#
# A write is `gh pr comment`, `gh pr review`, `gh issue comment`, or a
# `gh api` call on a PR's or issue's comments or reviews that uses a write
# method (-X/--method POST, PATCH, PUT or DELETE, or any -f/-F/--field/
# --raw-field/--input without an explicit GET). Such a command passes only
# when it contains the literal KC_REVIEW_POST_APPROVED=1, which the
# kc-post-review skill adds after the user's explicit post signal.
#
# With the token present, each body the command posts must also be text the user was shown
# before their latest message (the post signal): the guard reads the transcript (the payload's
# `transcript_path`) and denies a body that appears in no assistant text before that message. So
# the posted text is the text the user approved: a draft shown only after the question, or one
# with a placeholder (`<full SHA>`), is caught here. Bodies are read from -f/-F/--field/
# --raw-field body=..., --body/-b, and --input JSON (top-level body, comments[].body). A body it
# can't read reliably (a file argument, a shell substitution other than a quoted heredoc, an
# unbalanced quote, an unreadable --input file) is skipped, and no transcript means no check:
# the guard never blocks what it can't read. Needs jq for the transcript; without jq the shown
# check is skipped and only the token is enforced.
#
# With the token present, inline review comments must also come from build-comment-payloads.sh,
# which runs the draft checks (format, a reproduced issue, a capture of any screen a comment is
# about): a review posted with --input whose comments array is not empty needs the builder's
# `<file>.checked` stamp, holding the file's SHA-256, so a payload written or edited by hand
# is denied; and a new inline comment through the single-comment endpoint
# (`pulls/<n>/comments` without an id) is denied, since the builder never makes one.
#
# Output: the PreToolUse deny JSON on a blocked write, nothing otherwise.
# Always exits 0. Hook schema: https://code.claude.com/docs/en/hooks
#
# KC_GUARD_NO_JQ=1 forces the sed fallback (used by the tests).

set -u

# shellcheck source=lib/hook-input.sh
. "$(dirname "$0")/lib/hook-input.sh"

readonly APPROVAL_TOKEN='KC_REVIEW_POST_APPROVED=1'

readonly REVIEW_ENDPOINT='(pulls|issues)/([0-9]+/(comments|reviews)|comments/[0-9]+)'
readonly WRITE_METHOD='(-X|--method)[[:space:]=]*["'"'"']?(POST|PATCH|PUT|DELETE)'
readonly GET_METHOD='(-X|--method)[[:space:]=]*["'"'"']?GET([^[:alpha:]]|$)'
readonly FIELD_FLAG='(^|[[:space:]])(-f|-F|--field|--raw-field|--input)([[:space:]=]|[^[:space:]-]|$)'

is_review_write_segment() {
  local segment="$1"
  if printf '%s' "$segment" | grep -Eq "${GH_COMMAND_START}(pr[[:space:]]+(comment|review)|issue[[:space:]]+comment)([[:space:]]|$)"; then
    return 0
  fi
  if ! printf '%s' "$segment" | grep -Eq "${GH_COMMAND_START}api([[:space:]]|$)"; then
    return 1
  fi
  if ! printf '%s' "$segment" | grep -Eq "$REVIEW_ENDPOINT"; then
    return 1
  fi
  if printf '%s' "$segment" | grep -Eiq "$WRITE_METHOD"; then
    return 0
  fi
  if printf '%s' "$segment" | grep -Eiq "$GET_METHOD"; then
    return 1
  fi
  printf '%s' "$segment" | grep -Eq "$FIELD_FLAG"
}

contains_review_write() {
  local segment
  while IFS= read -r segment; do
    if is_review_write_segment "$segment"; then
      return 0
    fi
  done <<EOF
$(split_segments "$1")
EOF
  return 1
}

# Prints the command as tokens, each ended by an RS byte (0x1e), the way a shell would split it:
# quotes and backslashes resolved, and an unquoted newline, ; & or | printed as a token holding
# one GS byte (0x1d). An unbalanced quote prints a token holding one US byte (0x1f) last.
tokenize() {
  CMD="$1" awk 'BEGIN {
    s = ENVIRON["CMD"]; n = length(s); q = 0; tok = ""; has = 0
    for (i = 1; i <= n; i++) {
      c = substr(s, i, 1)
      if (q == 1) { if (c == "\047") q = 0; else tok = tok c; continue }
      if (q == 2) {
        if (c == "\"") q = 0
        else if (c == "\\" && index("\"\\$`", substr(s, i + 1, 1))) { i++; tok = tok substr(s, i, 1) }
        else tok = tok c
        continue
      }
      if (c == "\047") { q = 1; has = 1 }
      else if (c == "\"") { q = 2; has = 1 }
      else if (c == "\\") { i++; if (substr(s, i, 1) != "\n") { tok = tok substr(s, i, 1); has = 1 } }
      else if (c == " " || c == "\t") { if (has) printf "%s\036", tok; tok = ""; has = 0 }
      else if (c == "\n" || c == ";" || c == "&" || c == "|") {
        if (has) printf "%s\036", tok; tok = ""; has = 0; printf "\035\036"
      }
      else { tok = tok c; has = 1 }
    }
    if (q != 0) { printf "\037\036"; exit }
    if (has) printf "%s\036", tok
  }'
}

# A body written as "$(cat <<'EOF' ... EOF)" is the text between the delimiters; anything else
# starting with $( or a backtick is a substitution whose result can't be known here.
unwrap_heredoc() {
  local value=$1 first delimiter
  # shellcheck disable=SC2016 # literal $( patterns
  case "$value" in
    '$(cat <<'*) ;;
    '$('* | '`'*) return 1 ;;
    *) printf '%s' "$value"; return 0 ;;
  esac
  first=${value%%$'\n'*}
  delimiter=$(printf '%s' "$first" | sed -nE "s/^\\\$\\(cat <<-?[\"']?([A-Za-z_][A-Za-z0-9_]*)[\"']?.*/\\1/p")
  [ -n "$delimiter" ] || return 1
  printf '%s\n' "${value#*$'\n'}" | DELIM="$delimiter" awk '
    { stripped = $0; sub(/^[ \t]+/, "", stripped) }
    stripped == ENVIRON["DELIM"] || stripped == ENVIRON["DELIM"] ")" { exit }
    { lines[++n] = $0 }
    END { for (i = 1; i <= n; i++) printf "%s%s", lines[i], (i < n ? "\n" : "") }'
}

# Prints each body a command would post, one per RS-terminated (0x1e) record.
extract_bodies() {
  local -a tokens=()
  local segment_has_write token next value file
  while IFS= read -r -d $'\036' token; do
    tokens+=("$token")
  done <<EOF
$(tokenize "$1")
EOF
  tokens+=($'\035')
  local -a segment=()
  local i
  for ((i = 0; i < ${#tokens[@]}; i++)); do
    token=${tokens[$i]}
    if [ "$token" = $'\037' ]; then
      return 0
    fi
    if [ "$token" != $'\035' ]; then
      segment+=("$token")
      continue
    fi
    segment_has_write=0
    if [ "${#segment[@]}" -gt 0 ] && is_review_write_segment "${segment[*]}"; then
      segment_has_write=1
    fi
    if [ "$segment_has_write" = 1 ]; then
      local j=0 count=${#segment[@]}
      while [ "$j" -lt "$count" ]; do
        token=${segment[$j]}
        next=""
        [ $((j + 1)) -lt "$count" ] && next=${segment[$((j + 1))]}
        value=""
        file=""
        case "$token" in
          -f | --raw-field) case "$next" in body=*) value=${next#body=} ;; esac; j=$((j + 1)) ;;
          -F | --field) case "$next" in body=@*) ;; body=*) value=${next#body=} ;; esac; j=$((j + 1)) ;;
          -fbody=*) value=${token#-fbody=} ;;
          -Fbody=@*) ;;
          -Fbody=*) value=${token#-Fbody=} ;;
          --raw-field=body=*) value=${token#--raw-field=body=} ;;
          --field=body=@*) ;;
          --field=body=*) value=${token#--field=body=} ;;
          --body | -b) value=$next; j=$((j + 1)) ;;
          --body=*) value=${token#--body=} ;;
          --input) file=$next; j=$((j + 1)) ;;
          --input=*) file=${token#--input=} ;;
        esac
        if [ -n "$value" ] && value=$(unwrap_heredoc "$value"); then
          printf '%s\036' "$value"
        fi
        if [ -n "$file" ] && [ "$file" != - ] && [ -f "$file" ] && command -v jq >/dev/null 2>&1; then
          jq -j '[.body?, (.comments[]?.body?)] | .[] | select(type == "string" and . != "") | ., "\u001e"' "$file" 2>/dev/null
        fi
        j=$((j + 1))
      done
    fi
    segment=()
  done
}

# Text as the user would match it by eye: no blockquote markers, whitespace collapsed, no
# surrounding backticks or quotes.
normalize_text() {
  sed -E 's/^[[:space:]]*(>[[:space:]]?)+//' \
    | tr '[:space:]' ' ' | tr -s ' ' \
    | sed -E 's/^ //; s/ $//; s/^[`"'"'"']+//; s/[`"'"'"']+$//'
}

# Prints the normalized text of every assistant message before the user's latest typed message.
shown_text() {
  jq -rs -L "$(dirname "$0")/lib" 'include "typed-message";
    (map(is_typed_message) | rindex(true)) as $last
    | (if $last == null then [] else .[:$last] end)
    | .[] | select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text' \
    "$1" 2>/dev/null | normalize_text
}

# Prints the deny JSON when a body is missing from what the user was shown; nothing when all were
# shown or the check can't run.
unshown_body_verdict() {
  local command=$1 transcript=$2 shown body normalized reason
  [ -n "$transcript" ] && [ -r "$transcript" ] && command -v jq >/dev/null 2>&1 || return 0
  shown=$(shown_text "$transcript")
  while IFS= read -r -d $'\036' body; do
    normalized=$(printf '%s' "$body" | normalize_text)
    [ -n "$normalized" ] || continue
    case "$shown" in
      *"$normalized"*) ;;
      *)
        reason="Blocked by the kc-gates plugin: the text this command posts was not shown to the user before their latest message. Not shown verbatim: \"$(printf '%s' "$normalized" | cut -c1-80)\". Show the full final draft in a message (real commit SHAs, no placeholders, exactly the text that will be posted), then ask, and post only after the user's next answer. Do not retry this command, and do not paste the draft and ask in the same message."
        printf '%s' "$reason" | jq -Rsc '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: .}}'
        return 0
        ;;
    esac
  done <<EOF
$(extract_bodies "$command")
EOF
}

# Prints the SHA-256 of a file, with whichever tool the machine has.
file_sha256() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | cut -d' ' -f1
  else
    sha256sum "$1" | cut -d' ' -f1
  fi
}

# Prints the deny JSON when a token-carrying write posts inline review comments the payload
# builder did not check; nothing otherwise.
unchecked_comments_verdict() {
  local command=$1 segment file reason=""
  while IFS= read -r segment; do
    is_review_write_segment "$segment" || continue
    if printf '%s' "$segment" | grep -Eq 'pulls/[0-9]+/comments([^/0-9]|$)'; then
      reason="this posts a new inline comment through the single-comment endpoint, which skips build-comment-payloads.sh and its checks (and shows on the PR as a review of its own)."
      break
    fi
    printf '%s' "$segment" | grep -Eq 'pulls/[0-9]+/reviews([^/0-9]|$)' || continue
    file=$(printf '%s' "$segment" | sed -nE "s/.*--input[[:space:]=]+[\"']?([^[:space:]\"']+).*/\1/p")
    if [ -z "$file" ] || [ ! -f "$file" ] || ! command -v jq >/dev/null 2>&1; then
      continue
    fi
    [ "$(jq '(.comments // []) | length' "$file" 2>/dev/null)" = 0 ] && continue
    if [ ! -f "$file.checked" ] || [ "$(cat "$file.checked")" != "$(file_sha256 "$file")" ]; then
      reason="the review payload $file was not built, or was changed after it was built, by build-comment-payloads.sh, so its drafts never passed the checks (a reproduced issue, a capture of any screen a comment is about)."
      break
    fi
  done <<EOF
$(split_segments "$command")
EOF
  [ -n "$reason" ] || return 0
  printf 'Blocked by the kc-gates plugin: %s Write the drafts to a drafts file, run build-comment-payloads.sh, fix what it lists, show the drafts and its command to the user, and post only that command after their post signal.' "$reason" \
    | jq -Rsc '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: .}}'
}

print_deny() {
  cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked by the kc-gates plugin: this command writes a PR or issue comment or review to GitHub without the approval token. Do not retry and do not add the token yourself. Show the user the full draft, the head SHA it anchors to and the posting shape, then stop and wait for an explicit, fresh post signal in their latest message. Only after that signal, prefix each write command with KC_REVIEW_POST_APPROVED=1 in the same command (see /kc-gates:kc-post-review)."}}
EOF
}

main() {
  local input command transcript verdict
  input="$(cat)"
  command="$(extract_field "$input" command)"
  if [ -z "$command" ]; then
    exit 0
  fi
  case "$command" in
    *"$APPROVAL_TOKEN"*)
      if contains_review_write "$command"; then
        verdict=$(unchecked_comments_verdict "$command")
        if [ -n "$verdict" ]; then
          printf '%s' "$verdict"
          exit 0
        fi
        transcript="$(extract_field "$input" transcript_path)"
        unshown_body_verdict "$command" "$transcript"
      fi
      exit 0
      ;;
  esac
  if contains_review_write "$command"; then
    print_deny
  fi
  exit 0
}

main
