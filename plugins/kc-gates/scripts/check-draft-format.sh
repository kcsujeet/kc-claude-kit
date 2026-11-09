#!/usr/bin/env bash
# Checks drafted review comments against kc-post-review's format rules, the ones a script can
# decide, so a draft that breaks them never reaches a payload. build-comment-payloads.sh runs it.
#
# Usage: check-draft-format.sh <drafts.json>
#   <drafts.json>  the JSON array of {path, line, body, ...} that build-comment-payloads.sh takes;
#                  a draft may carry "long": "<reason>" when its length is the stated exception,
#                  and "code": "<reason>" when its code is
#
# Each body must:
#   - open with a label from kc-post-review's Labels table on its own line
#     in either layout the skill shows (`**suggestion**:`, `**nitpick** (non-blocking):`, or the
#     Conventional Comments `**suggestion:**`, `**nitpick (non-blocking):**`), and use no `(blocking)`;
#   - hold no em dash, no `§` rule citation, no emoji, and not open with a praise phrase
#     (Good catch, Good call, Fair, Real bug, Nice find);
#   - outside code blocks, have at most 3 sentences and none over 25 words, unless "long" says why;
#   - hold at most 2 non-blank lines of code across its code blocks, unless "code" says why: a
#     comment says what is wrong and what should happen, and the author, who knows the code,
#     writes the fix.
#
# Prints one line per problem (`draft <n> (<path>:<line>): <problem>`) and exits 1 when there is
# any, 0 when every draft passes, 2 on a usage error or unreadable input.
set -euo pipefail

script_name=$(basename "$0")
[ "$#" -eq 1 ] || { echo "usage: $script_name <drafts.json>" >&2; exit 2; }
[ -r "$1" ] || { echo "$script_name: cannot read $1" >&2; exit 2; }

perl -MJSON::PP -CS -e '
  use strict; use warnings;
  local $/; open(my $fh, "<:encoding(UTF-8)", $ARGV[0]) or exit 2;
  my $drafts = eval { JSON::PP->new->decode(<$fh>) };
  if (ref $drafts ne "ARRAY") { print STDERR "drafts file is not a JSON array\n"; exit 2 }
  my $labels = qr/suggestion|nitpick|issue|question|chore|todo|note|thought|praise/;
  my $problems = 0;
  my $index = 0;
  for my $draft (@$drafts) {
    $index++;
    my $where = sprintf("draft %d (%s:%s)", $index, $draft->{path} // "?", $draft->{line} // "?");
    my $body = $draft->{body} // "";
    next unless $body =~ /\S/;  # build-comment-payloads.sh reports an empty body
    my @found;
    my ($first, $rest) = split /\n/, $body, 2;
    $rest //= "";
    if ($first !~ /^\*\*($labels)( \((non-blocking|if-minor)\))?(:\*\*|\*\*( \((non-blocking|if-minor)\))?:)\s*$/) {
      push @found, "the first line is not a label from the Labels table on its own line (`**suggestion**:`)";
    }
    push @found, "uses the (blocking) decoration; pick the label instead" if $body =~ /\(blocking\)/;
    push @found, "has an em dash" if $body =~ /\x{2014}/;
    push @found, "cites a rule with \x{a7}" if $body =~ /\x{a7}/;
    push @found, "has an emoji" if $body =~ /[\x{1F300}-\x{1FAFF}\x{2600}-\x{27BF}\x{2B50}\x{2705}]/;
    push @found, "opens with praise" if $rest =~ /\A\s*(Good catch|Good call|Fair\b|Real bug|Nice find)/i;
    (my $prose = $rest) =~ s/```.*?```//gs;
    $prose =~ s/`[^`]*`/code/g;
    my @sentences = grep { /\w/ } split /(?<=[.!?])\s+/, $prose;
    unless (defined $draft->{long} && $draft->{long} =~ /\S/) {
      push @found, sprintf("has %d sentences; keep to 3 or say why in \"long\"", scalar @sentences) if @sentences > 3;
      for my $sentence (@sentences) {
        my $words = () = $sentence =~ /\S+/g;
        if ($words > 25) {
          push @found, "has a $words-word sentence; split it or say why in \"long\"";
          last;
        }
      }
    }
    my $code_lines = 0;
    while ($rest =~ /```[^\n]*\n(.*?)```/gs) { $code_lines += () = $1 =~ /^[ \t]*\S/mg }
    if ($code_lines > 2 && !(defined $draft->{code} && $draft->{code} =~ /\S/)) {
      push @found, "has $code_lines lines of code; describe the problem and the behaviour expected, with code only for a one- or two-line fix, or say why in \"code\"";
    }
    for my $problem (@found) { print "$where: $problem\n"; $problems++ }
  }
  exit($problems ? 1 : 0);
' "$1"
