#!/usr/bin/env bash
# PostToolUse hook for Bash: after a command that changes the installed plugins (`claude plugin
# install`, `update`, `enable`, or `claude plugin marketplace update`), reminds Claude that this
# session still runs the versions it loaded, so the person is asked for /reload-plugins at once,
# as the turn's one question, before any other work (working agreement, "Ask before assuming").
#
# The prompt-time notice (`check-loaded-version.sh`) says the same on the person's next message,
# but only if that hook runs then; a session that installed the update itself knows right away
# and asks right away, rather than leaving the request as a line in a message.
#
# It splits the command as the guards do, quotes or not; a reminder too many is harmless.
# Heredoc bodies are not dropped: a command that writes the words `claude plugin update` into a
# file is rare here, and the reminder costs nothing.
#
# Output: PostToolUse JSON with the reminder as additionalContext after such a command, nothing
# otherwise. Always exits 0. Hook schema: https://code.claude.com/docs/en/hooks
#
# KC_GUARD_NO_JQ=1 forces the sed fallback (used by the tests).

set -u

# shellcheck source=lib/hook-input.sh
. "$(dirname "$0")/lib/hook-input.sh"

readonly PLUGIN_CHANGE='(^|[^[:alnum:]_.-])claude[[:space:]]+plugin[[:space:]]+((install|update|enable)|marketplace[[:space:]]+update)([[:space:]]|$)'

main() {
  local input command segment
  input="$(cat)"
  command="$(extract_field "$input" command)"
  while IFS= read -r segment; do
    printf '%s' "$segment" | grep -Eq -- '(^|[[:space:]])(-h|--help)([[:space:]]|$)' && continue
    if printf '%s' "$segment" | grep -Eq "$PLUGIN_CHANGE"; then
      cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"kc-gates: this changed the installed plugins, and this session still runs the versions it loaded, so the newer rules are not active here. Ask the person for /reload-plugins now, as the turn's one question in the host's question box with an answer to click, before any other work (working agreement, Ask before assuming); a line about it inside a longer message is not asking."}}
EOF
      exit 0
    fi
  done <<EOF
$(split_segments "$command")
EOF
  exit 0
}

main
