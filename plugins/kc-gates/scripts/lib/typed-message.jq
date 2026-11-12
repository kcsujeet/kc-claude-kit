# What a person typed, in a Claude Code transcript entry: the text blocks of a user message that
# aren't a hook note, a command echo or a skill's preamble. Read with `include "typed-message";`
# and `jq -L <this folder>` (https://jqlang.org/manual/#modules), by feedback-ledger.sh and
# check-reply-sources.sh, so both agree on where the person's messages are.

def is_not_typed:
  test("^(<system-reminder>|<task-notification>|<local-command|<command-name>|<command-message>|Caveat: |Base directory for this skill: )");

# The entry's text blocks, as strings.
def message_texts:
  if (.message.content | type) == "string" then [.message.content]
  else [.message.content[]? | select(.type == "text") | .text] end;

# The texts the person typed: a user entry's text blocks that aren't machine notes.
def typed_texts:
  message_texts[] | select(is_not_typed | not);

# True for an entry that is a message the person typed: not a tool result (whose entry can carry
# text beside it), a summary or a machine note.
def is_typed_message:
  .type == "user" and (.isMeta | not) and (.isCompactSummary | not)
  and ([.message.content[]? | select(.type == "tool_result")] | length) == 0
  and ([typed_texts] | length) > 0;
