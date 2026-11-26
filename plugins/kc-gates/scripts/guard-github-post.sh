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
# With the token present, a review write (a comment, a review, an approval) is also denied while
# the review's walk receipt fails check-walk-receipt.sh. The review is the `$KC_REVIEW_DIR` folder,
# or else the saved `${TMPDIR:-/tmp}/kc-review-*` folder (gather-review.sh, last day) with the
# newest meta.env whose `URL=` is this repo (the command's -R, URL or api path, else the origin
# remote) and whose `PR=<n>` is the pull request the command names, wherever its flags sit or in
# a URL or api path; a command that names none takes the newest folder of the repo. It holds
# review.diff, changed-files.txt and walk-receipt.tsv: select-gates.sh is run on the first two, and
# each `walk-item:` it prints needs a line in the receipt. No review folder, or no walk-item
# (WALK=not-required), means no check.
#
# With the token present, an approval (`gh pr review --approve`, or a reviews api write with event
# APPROVE) is also compared with the head the review walked: the pull request's current head
# (`gh pr view --json headRefOid`) against HEAD_SHA in the review folder's meta.env. When they
# differ and any file the pull request changes differs between the two commits, the approval is
# denied, naming the files: the new commits were not reviewed, unless the move was a rebase:
# `git range-diff` of the reviewed commits (merge-base with origin/<the pull request's base
# branch> up to the walked head) against the current ones then shows every one unchanged (only "="
# pairs), and the approval goes through with a one-line note. A commit changed, added or dropped
# is named in the denial; a base branch or commit this clone lacks keeps the denial and says to
# fetch. When they differ only by commits
# that touch none of the pull request's files (the default branch merged in), the approval goes
# through with a one-line systemMessage saying so. A head, file list or commit it can't read means
# no check.
#
# Output: the PreToolUse deny JSON on a blocked write, nothing otherwise (or the one-line note).
# Always exits 0. Hook schema: https://code.claude.com/docs/en/hooks
#
# KC_GUARD_NO_JQ=1 forces the sed fallback (used by the tests).

set -u

# shellcheck source=lib/hook-input.sh
. "$(dirname "$0")/lib/hook-input.sh"
# shellcheck source=lib/file-sha256.sh
. "$(dirname "$0")/lib/file-sha256.sh"
# shellcheck source=lib/review-dir.sh
. "$(dirname "$0")/lib/review-dir.sh"

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

# Prints the deny JSON when a token-carrying write posts inline review comments the payload
# builder did not check; nothing otherwise.
unchecked_comments_verdict() {
  local command=$1 segment review_payload_file reason=""
  while IFS= read -r segment; do
    is_review_write_segment "$segment" || continue
    if printf '%s' "$segment" | grep -Eq 'pulls/[0-9]+/comments([^/0-9]|$)'; then
      reason="this posts a new inline comment through the single-comment endpoint, which skips build-comment-payloads.sh and its checks (and shows on the PR as a review of its own)."
      break
    fi
    printf '%s' "$segment" | grep -Eq 'pulls/[0-9]+/reviews([^/0-9]|$)' || continue
    if printf '%s' "$segment" | grep -Eq "(^|[[:space:]])(-f|-F|--field|--raw-field)[[:space:]=]*[\"']?comments\\["; then
      reason="this sends inline review comments as fields, which skips build-comment-payloads.sh and its checks."
      break
    fi
    review_payload_file=$(printf '%s' "$segment" | sed -nE "s/.*--input[[:space:]=]+[\"']?([^[:space:]\"']+).*/\\1/p")
    # No --input and no comment fields: a review with only a top-level body.
    [ -n "$review_payload_file" ] || continue
    command -v jq >/dev/null 2>&1 || continue
    [ "$(jq '(.comments // []) | length' "$review_payload_file" 2>/dev/null)" = 0 ] && continue
    if [ ! -f "$review_payload_file.checked" ] || [ "$(cat "$review_payload_file.checked")" != "$(print_file_sha256 "$review_payload_file")" ]; then
      reason="the review payload $review_payload_file was not built, or was changed after it was built, by build-comment-payloads.sh, so its drafts never passed the checks (a reproduced issue, a capture of any screen a comment is about)."
      break
    fi
  done <<EOF
$(split_segments "$command")
EOF
  [ -n "$reason" ] || return 0
  printf 'Blocked by the kc-gates plugin: %s Write the drafts to a drafts file, run build-comment-payloads.sh, fix what it lists, show the drafts and its command to the user, and post only that command after their post signal.' "$reason" \
    | jq -Rsc '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: .}}'
}

# Prints "<owner/repo>|<number>" for the first review write in the command: the number after the
# subcommand wherever its flags sit, or in a pull or issue URL or an api path; the repository from
# -R/--repo, the URL or the api path. A part the command does not name is empty.
read_review_target() {
  local -a tokens=() segment=()
  local token word previous="" expecting="" repo="" number="" in_subcommand=false
  local url_pattern='github\.com/([^/]+/[^/]+)/(pull|issues)/([0-9]+)'
  local api_pattern='repos/([^/]+/[^/]+)/(pulls|issues)/([0-9]+)'
  while IFS= read -r -d $'\036' token; do
    tokens+=("$token")
  done <<EOF
$(tokenize "$1")
EOF
  tokens+=($'\035')
  for token in "${tokens[@]}"; do
    if [ "$token" != $'\035' ]; then
      segment+=("$token")
      continue
    fi
    if [ "${#segment[@]}" -gt 0 ] && is_review_write_segment "${segment[*]}"; then
      for word in "${segment[@]}"; do
        if [ -n "$expecting" ]; then
          if [ "$expecting" = repo ] && [ -z "$repo" ]; then repo=$word; fi
          expecting=""
        elif [[ $word =~ $url_pattern || $word =~ $api_pattern ]]; then
          [ -n "$repo" ] || repo=${BASH_REMATCH[1]}
          [ -n "$number" ] || number=${BASH_REMATCH[3]}
        else
          case "$word" in
            -R | --repo) expecting=repo ;;
            --repo=*) [ -n "$repo" ] || repo=${word#--repo=} ;;
            -R?*) [ -n "$repo" ] || repo=${word#-R} ;;
            -b | --body | -F | --body-file | -f | --field | --raw-field | -H | --header | -X | --method | --input | -t | --title | --jq | -q | --template) expecting=skip ;;
            -*) ;;
            review | comment) case "$previous" in pr | issue) in_subcommand=true ;; esac ;;
            *[!0-9]* | '') ;;
            *) if [ "$in_subcommand" = true ] && [ -z "$number" ]; then number=$word; fi ;;
          esac
        fi
        previous=$word
      done
      break
    fi
    segment=()
  done
  case "$repo" in *'{'*) repo="" ;; esac
  printf '%s|%s' "$repo" "$number"
}

# The owner/repo of this checkout's origin remote on github.com; nothing for any other remote.
read_remote_repo() {
  git remote get-url origin 2>/dev/null | sed -nE 's#^.*github\.com[:/]([^/]+/[^/]+)$#\1#p' | sed 's#\.git$##'
}


# Prints the saved review folder this command's write is about: $KC_REVIEW_DIR, else the newest
# folder for the repo and pull request the command names; nothing if none.
find_command_review_dir() {
  local target target_repo target_number
  if [ -n "${KC_REVIEW_DIR:-}" ]; then
    printf '%s' "$KC_REVIEW_DIR"
    return 0
  fi
  target=$(read_review_target "$1")
  target_repo=${target%%|*}
  target_number=${target#*|}
  [ -n "$target_repo" ] || target_repo=$(read_remote_repo)
  find_review_dir "$target_repo" "$target_number"
}

# True when the command approves a pull request: `gh pr review --approve` (or -a), or a reviews
# api write whose event is APPROVE, given as a field or in the --input file.
is_approval_command() {
  local segment payload_file payload_event
  while IFS= read -r segment; do
    is_review_write_segment "$segment" || continue
    if printf '%s' "$segment" | grep -Eq "${GH_COMMAND_START}pr[[:space:]]+review([[:space:]]|$)"; then
      printf '%s' "$segment" | grep -Eq '(^|[[:space:]])(--approve|-a)([[:space:]]|$)' && return 0
      continue
    fi
    printf '%s' "$segment" | grep -Eq 'pulls/[0-9]+/reviews([^/0-9]|$)' || continue
    printf '%s' "$segment" | grep -Eq "event[=:][[:space:]\"']*APPROVE" && return 0
    payload_file=$(printf '%s' "$segment" | sed -nE "s/.*--input[[:space:]=]+[\"']?([^[:space:]\"']+).*/\\1/p")
    [ -f "$payload_file" ] || continue
    command -v jq >/dev/null 2>&1 || continue
    payload_event=$(jq -r '.event // empty' "$payload_file" 2>/dev/null)
    [ "$payload_event" = APPROVE ] && return 0
  done <<EOF
$(split_segments "$1")
EOF
  return 1
}

# Compares the reviewed commits with the current ones by `git range-diff`, both ranges taken from
# the merge-base with origin/<base> (the pull request's base branch). Prints "same" when every
# pair is "=", "changed: <marker, short sha and subject of each commit that differs>" when a
# commit changed, was added or dropped, and "unknown" when the base, a commit or range-diff is
# unavailable here.
# Usage: compare_reviewed_commits <base branch> <walked> <current>
compare_reviewed_commits() {
  local base_ref="origin/$1" walked=$2 current=$3 walked_base current_base pairs
  local short_sha_chars=7
  local has_base_name=false has_base_commit=false
  [ -n "$1" ] && has_base_name=true
  git rev-parse --verify -q "$base_ref^{commit}" >/dev/null 2>&1 && has_base_commit=true
  if ! "$has_base_name" || ! "$has_base_commit"; then
    echo unknown
    return 0
  fi
  walked_base=$(git merge-base "$base_ref" "$walked" 2>/dev/null) || { echo unknown; return 0; }
  current_base=$(git merge-base "$base_ref" "$current" 2>/dev/null) || { echo unknown; return 0; }
  pairs=$(git range-diff --no-color "$walked_base..$walked" "$current_base..$current" 2>/dev/null) || { echo unknown; return 0; }
  printf '%s\n' "$pairs" | awk -v n="$short_sha_chars" '
    match($0, /^ *[0-9-]+: +[0-9a-f-]+ [=!<>] +[0-9-]+: +[0-9a-f-]+ /) {
      split($0, f, " ")
      if (f[3] == "=") { same++; next }
      sha = (f[2] == "-") ? f[5] : f[2]
      differ = differ f[3] " " substr(sha, 1, n) " " substr($0, RLENGTH + 1) "; "
    }
    END { if (differ != "") print "changed: " differ; else if (same) print "same"; else print "unknown" }'
}

# For an approval of a pull request whose head moved since the review walked it: prints the deny
# JSON when a file the pull request changes differs between the two heads, or the one-line note
# when only commits touching none of its files came in; nothing when the heads match or can't be
# read.
get_moved_head_verdict() {
  local command=$1 review_dir target repo number walked current_head pr_files changed_files block_reason short_walked short_current changed_text base_branch commits_state
  local -a gh_target=() paths=()
  local file
  # The message is shown as a hook message, so the file list is cut to a short length.
  local short_sha_chars=7 max_changed_chars=400
  is_approval_command "$command" || return 0
  review_dir=$(find_command_review_dir "$command")
  has_review_files "$review_dir" || return 0
  walked=$(sed -n 's/^HEAD_SHA=//p' "$review_dir/meta.env" 2>/dev/null | head -n 1)
  [ -n "$walked" ] || return 0
  target=$(read_review_target "$command")
  repo=${target%%|*}
  number=${target#*|}
  [ -n "$number" ] && gh_target+=("$number")
  [ -n "$repo" ] && gh_target+=(-R "$repo")
  current_head=$(gh pr view ${gh_target[@]+"${gh_target[@]}"} --json headRefOid --jq .headRefOid 2>/dev/null) || return 0
  [ -n "$current_head" ] && [ "$current_head" != "$walked" ] || return 0
  pr_files=$(gh pr view ${gh_target[@]+"${gh_target[@]}"} --json files --jq '.files[].path' 2>/dev/null) || return 0
  [ -n "$pr_files" ] || return 0
  git cat-file -e "$walked^{commit}" 2>/dev/null && git cat-file -e "$current_head^{commit}" 2>/dev/null || return 0
  while IFS= read -r file; do paths+=("$file"); done <<EOF
$pr_files
EOF
  changed_files=$(git diff --name-only "$walked" "$current_head" -- "${paths[@]}" 2>/dev/null) || return 0
  short_walked=$(printf '%s' "$walked" | cut -c1-"$short_sha_chars")
  short_current=$(printf '%s' "$current_head" | cut -c1-"$short_sha_chars")
  if [ -z "$changed_files" ]; then
    printf 'the pull request head moved from %s to %s since the review, by commits that touch none of its files (a merge of the default branch), so the approval stands.' "$short_walked" "$short_current"
    return 0
  fi
  base_branch=$(gh pr view ${gh_target[@]+"${gh_target[@]}"} --json baseRefName --jq .baseRefName 2>/dev/null) || base_branch=
  commits_state=$(compare_reviewed_commits "$base_branch" "$walked" "$current_head")
  if [ "$commits_state" = same ]; then
    printf 'the pull request head moved from %s to %s since the review by a rebase: git range-diff shows every reviewed commit unchanged, so the approval stands.' "$short_walked" "$short_current"
    return 0
  fi
  changed_text=$(printf '%s' "$changed_files" | tr '\n' ' ' | sed 's/["\\]//g' | cut -c1-"$max_changed_chars")
  block_reason="Blocked by the kc-gates plugin: the pull request head is $short_current but the review walked $short_walked, and these files of the pull request changed in between: $changed_text. Review the new commits first (gather the review again, then walk and grade them), then approve the head you reviewed."
  case "$commits_state" in
    changed:*) block_reason="$block_reason Commits that differ from the reviewed ones (range-diff: < dropped, > added, ! changed): $(printf '%s' "${commits_state#changed: }" | sed 's/["\\]//g' | cut -c1-"$max_changed_chars")" ;;
    *) block_reason="$block_reason If the head only moved by a rebase, fetch the pull request's base branch and head so git range-diff can compare the reviewed commits, then try again." ;;
  esac
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}' "$block_reason"
}

# Prints the deny JSON when the saved review has walk-items without a full receipt line; nothing
# otherwise, and nothing when no review folder or no select-gates.sh can be found.
get_unwalked_review_verdict() {
  local scripts_dir review_dir selected uses_file problems reason problem_text
  # The reason is shown as a hook message, so the problem list is cut to a short length.
  local max_problem_chars=600
  scripts_dir=$(dirname "$0")
  review_dir=$(find_command_review_dir "$1")
  has_review_files "$review_dir" || return 0
  selected=$(mktemp)
  if ! bash "$scripts_dir/select-gates.sh" "$review_dir/review.diff" "$review_dir/changed-files.txt" . > "$selected" 2>/dev/null; then
    rm -f "$selected"
    return 0
  fi
  uses_file=$review_dir/uses.txt
  [ -r "$uses_file" ] || uses_file=""
  problems=$(bash "$scripts_dir/check-walk-receipt.sh" "$selected" "$review_dir/walk-receipt.tsv" "$uses_file" 2>&1) && { rm -f "$selected"; return 0; }
  rm -f "$selected"
  problem_text=$(printf '%s' "$problems" | tr '\n' ' ' | sed 's/["\\]//g' | cut -c1-"$max_problem_chars")
  reason="Blocked by the kc-gates plugin: this review changed behaviour it has no walk receipt for, so it cannot be posted or approved yet. Walk each item on its QA surface (browser, API, terminal, unit) and write one line per item to $review_dir/walk-receipt.tsv (path, what was seen, evidence of that surface: browser a screenshot or recording, api a curl request and its saved response, terminal or unit a run transcript, exit 0: run.txt). $problem_text"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}' "$reason"
}

print_deny() {
  cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked by the kc-gates plugin: this command writes a PR or issue comment or review to GitHub without the approval token. Do not retry and do not add the token yourself. Show the user the full draft, the head SHA it anchors to and the posting shape, then stop and wait for an explicit, fresh post signal in their latest message. Only after that signal, prefix each write command with KC_REVIEW_POST_APPROVED=1 in the same command (see /kc-gates:kc-post-review)."}}
EOF
}

main() {
  local input command transcript verdict verdict_unshown
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
        verdict=$(get_unwalked_review_verdict "$command")
        if [ -n "$verdict" ]; then
          printf '%s' "$verdict"
          exit 0
        fi
        verdict=$(get_moved_head_verdict "$command")
        case "$verdict" in
          '{'*)
            printf '%s' "$verdict"
            exit 0
            ;;
        esac
        transcript="$(extract_field "$input" transcript_path)"
        verdict_unshown=$(unshown_body_verdict "$command" "$transcript")
        if [ -n "$verdict_unshown" ]; then
          printf '%s' "$verdict_unshown"
        elif [ -n "$verdict" ]; then
          printf '{"systemMessage":"%s"}' "$verdict"
        fi
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
