# shellcheck shell=bash
# Reads a Bash hook's payload (PreToolUse or PostToolUse) for the kit's hooks. Sourced, never
# executed.
#
# KC_GUARD_NO_JQ=1 forces the sed fallback (used by the tests).

# Where a `gh` command starts in a segment: `gh` as a whole word, then its subcommand.
# shellcheck disable=SC2034  # read by guard-github-post.sh and remind-look-back.sh
readonly GH_COMMAND_START='(^|[^[:alnum:]_.-])gh[[:space:]]+'

# Prints a top-level or tool_input string field of the payload: `command`
# comes from tool_input, `cwd` from the top level.
extract_field() {
  local input="$1" field="$2" path
  case "$field" in
    command) path='.tool_input.command' ;;
    *) path=".$field" ;;
  esac
  if [ "${KC_GUARD_NO_JQ:-0}" != 1 ] && command -v jq >/dev/null 2>&1; then
    printf '%s' "$input" | jq -r "$path // empty" 2>/dev/null
    return
  fi
  # JSON strings hold no raw newlines, so joining lines is safe. The capture is
  # the field's JSON text, escapes and all, which perl's core JSON module decodes
  # from UTF-8 and prints as UTF-8 (`\\`, `\"` and `\u00e9` included), so the sed
  # that splits it never meets a stray byte. Text it can't decode (a lone
  # surrogate, an unknown escape) is printed as captured, so a guard still reads
  # the command rather than an empty one.
  printf '%s' "$input" \
    | tr '\n' ' ' \
    | sed -nE 's/.*"'"$field"'"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)".*/\1/p' \
    | perl -MJSON::PP -0777 -ne '
        chomp;
        my $value = eval { JSON::PP->new->utf8->allow_nonref->decode(qq("$_")) };
        if (defined $value) { binmode STDOUT, ":encoding(UTF-8)"; print $value } else { print $_ }'
}

# Prints the command with the text that isn't shell syntax made inert, read the way bash reads
# it: escaped characters, `$'...'`, "..." (with `\"` inside) and '...' strings, `#` comments and
# heredoc bodies. In that text `;`, `|`, `&` and newlines become spaces and a flag-like word after
# a space gets an `x` in front (`-b "please --approve"` becomes `-b "please x--approve"`), so a
# review body neither splits its command nor reads as one of its flags. A flag quoted on its own
# (`'--approve'`) is still the flag, and an unclosed quote is left as it is.
#
# Only for a hook whose miss is harmless (remind-look-back.sh). The guards split the raw command:
# quoted text can be what runs (`bash -c "..."`, `eval`, `ssh host '...'`), and masking it would
# hide a write from them.
mask_quoted_text() {
  printf '%s\n' "$1" | perl -0777 -ne '
    sub as_text {
      my ($span) = @_;
      $span =~ s/[;|&\n]/ /g;
      $span =~ s/(\s)(-{1,2}[A-Za-z])/$1x$2/g;
      return $span;
    }
    my $masked = "";
    my @heredoc_ends;
    while (1) {
      if (/\G(\\.)/gcs) { $masked .= as_text($1) }
      elsif (/\G(\$\x27(?:[^\x27\\]|\\.)*\x27)/gcs) { $masked .= as_text($1) }
      elsif (/\G("(?:[^"\\]|\\.)*")/gcs) { $masked .= as_text($1) }
      elsif (/\G(\x27[^\x27]*\x27)/gcs) { $masked .= as_text($1) }
      elsif (/\G(?<![^\s])(#[^\n]*)/gc) { $masked .= as_text($1) }
      # A heredoc body is masked only up to a line holding its end word, so a `<<` with none after
      # it (`$((x << y))`, or one never closed) masks nothing. The end word runs to whitespace or
      # an operator, as bash reads it (`<<MY-END`), and only `<<-` lets the end line start with tabs.
      elsif (/\G(<<(-?)[ \t]*([\x27"]?)([^\s;&|<>()\x27"]+)\3)/gc) {
        my ($opener, $dash, $end) = ($1, $2, $4);
        push @heredoc_ends, [$dash ? "\t*" : "", $end];
        $masked .= $opener;
      }
      elsif (@heredoc_ends && /\G\n/gc) {
        $masked .= "\n";
        for my $heredoc (@heredoc_ends) {
          my ($indent, $end) = @$heredoc;
          $masked .= as_text($1) . $2 if /\G((?:[^\n]*\n)*?)($indent\Q$end\E)(?=\n|\z)/gc;
        }
        @heredoc_ends = ();
      }
      elsif (/\G(.)/gcs) { $masked .= $1 }
      else { last }
    }
    print $masked;
  '
}

# One shell segment per line: split on newlines, ;, &&, || and |, quotes or not. Splitting
# inside a quoted argument can only add segments, so a guard reading these sees every command.
split_segments() {
  printf '%s\n' "$1" | sed -e 's/&&/\
/g' -e 's/||/\
/g' -e 's/;/\
/g' -e 's/|/\
/g'
}
