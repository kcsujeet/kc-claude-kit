#!/usr/bin/env bash
# Checks drafted review comments against kc-post-review's format rules, the ones a script can
# decide, so a draft that breaks them never reaches a payload. build-comment-payloads.sh runs it.
#
# Usage: check-draft-format.sh <drafts.json> [<head-sha>]
#   <drafts.json>  the JSON array of {path, line, body, ...} that build-comment-payloads.sh takes;
#                  a draft may carry "long": "<reason>" when its length is the stated exception,
#                  and "code": "<reason>" when its code is; an `issue` or `suggestion` draft carries
#                  "ran": what its asked-for change was run against and the result, or
#                  "n/a: <why>" when it asks for no behaviour change, or asks for an outcome and a
#                  test rather than code; it also carries "walked": the states the asked-for
#                  change reaches with what each shows before and after, or "n/a: <why>" when no
#                  behaviour change is asked (a rename, a missing test); a draft on a file people
#                  see rendered carries "seen"
#   <head-sha>     the commit the comments anchor to; when given and the repo knows it, a "seen"
#                  capture must be newer than that commit
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
#     writes the fix;
#   - when it is an `issue` or a `suggestion`, carry a "walked" record: the change it asks for is
#     walked, not only the bug that prompted it, so each state the change reaches has what it
#     showed before and after. An "n/a" needs a reason;
#   - when it is an `issue` or a `suggestion`, carry a "ran" record: a change asked for in a
#     review is code the author writes on the reviewer's word, so it is run before it is asked
#     for, not only read (kc-post-review's "Verified before suggested"). An "n/a" needs a reason;
#   - outside code, name a ticket or pull request only as a link: a tracker id (ABC-123, two or more
#     capitals) or a #123 / PR 123 / pull request 123 reference that is not the text of a
#     [..](http..) link and not part of a URL is a problem, so the reader can open it; standards
#     names (UTF-8, ISO-8601, SHA-256, RFC, HTTP, TLS, SSL) are not ids (kc-post-review's "Linked, not bare");
#   - use none of a short list of hard words (gated, callers, derive, invariant, predicate, and the
#     code-flow words rerender, refetch, fallback, mid-edit, early return, short-circuit, bail out): a comment is read by a person, so it says the thing in everyday words;
#   - when it asks for a test, carry a "ran" that says the test failed with the bug put back: a
#     suggested test that still passes with the bug in place guards nothing;
#   - when it says something about query counts (an N+1, extra or per-record queries), carry a
#     "ran" naming a request and its counts: a request's query cache and loaded associations can
#     make per-record queries free, so a count taken in a console or a serializer call misleads;
#   - when it says something about an earlier review ("last round", "I was wrong"), carry a "ran"
#     that is not "n/a": a claim that reverses or repeats an earlier comment is checked again first;
#   - when it is an `issue`, carry a "ran" that is not "n/a": an issue says something is broken,
#     so the break is reproduced (a failing test, a request, a capture) before it is claimed;
#   - when it is on a file people see rendered (a component, template or stylesheet; not a test,
#     spec or story) and is not a question, note, thought or praise, carry "seen": the path of a
#     screenshot or recording of the running app showing it, taken after the head commit. Reading
#     the code is not seeing the screen (kc-post-review's "Seen before drafted").
#
# Prints one line per problem (`draft <n> (<path>:<line>): <problem>`) and exits 1 when there is
# any, 0 when every draft passes, 2 on a usage error or unreadable input.
set -euo pipefail

script_name=$(basename "$0")
{ [ "$#" -eq 1 ] || [ "$#" -eq 2 ]; } || { echo "usage: $script_name <drafts.json> [<head-sha>]" >&2; exit 2; }
[ -r "$1" ] || { echo "$script_name: cannot read $1" >&2; exit 2; }
# The head commit's time, so a capture taken before the code under review existed doesn't count.
KC_HEAD_TIME=""
[ "$#" -eq 2 ] && KC_HEAD_TIME=$(git show -s --format=%ct "$2" 2>/dev/null) || true
export KC_HEAD_TIME
# shellcheck source=lib/capture-paths.sh
. "$(dirname "$0")/lib/capture-paths.sh"
export KC_CAPTURE_PATH

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
    if ($first =~ /^\*\*(issue|suggestion)\b/) {
      my $ran = $draft->{ran} // "";
      $ran = "" if ref $ran;
      if ($ran !~ /\S/) {
        push @found, "asks for a change with no \"ran\": run it on a scratch copy and say what it passed, or \"n/a: <why>\"";
      } elsif ($ran =~ m{^\s*n/?a\W*$}i) {
        push @found, "says \"ran\": n/a with no reason; give the why";
      } elsif ($first =~ /^\*\*issue\b/ && $ran =~ m{^\s*n/?a\b}i) {
        push @found, "is an issue with \"ran\": n/a; an issue says something is broken, so reproduce it (a failing test, a request, a screenshot) and say in \"ran\" what showed it, or use another label";
      }
      my $walked = $draft->{walked} // "";
      $walked = "" if ref $walked;
      if ($walked !~ /\S/) {
        push @found, "asks for a change with no \"walked\": list each state the asked-for change reaches with what it shows before and after, or \"n/a: <why>\" when no behaviour change is asked";
      } elsif ($walked =~ m{^\s*n/?a\W*$}i) {
        push @found, "says \"walked\": n/a with no reason; give the why, or list the states the change reaches with before and after";
      }
    }
    my $ran_record = ref $draft->{ran} ? "" : ($draft->{ran} // "");
    # Words a reader has to stop and decode; each has an everyday way to say it.
    (my $linkable = $rest) =~ s/```.*?```//gs;
    $linkable =~ s/`[^`\n]*`//g;
    $linkable =~ s{\[[^\]\n]*\]\(https?:[^)\s]*\)}{}g;
    $linkable =~ s{https?://\S+}{}g;
    my %bare;
    $bare{$1} = 1 while $linkable =~ /(?<![\w\/#&-])((?:PR|[Pp]ull [Rr]equest) #?\d+)\b/g;
    $linkable =~ s/(?:PR|[Pp]ull [Rr]equest) #?\d+\b//g;
    $bare{$1} = 1 while $linkable =~ /(?<![\w\/&-])((?!(?:UTF|ISO|SHA|RFC|HTTP|TLS|SSL)-)[A-Z]{2,}-\d+(?:-\d+)?)\b/g;
    # A # and six digits is a colour (#333333), not a pull request.
    $bare{$1} = 1 while $linkable =~ /(?<![\w\/&#])(#\d+)\b(?<!#\d{6})/g;
    for my $ref (sort keys %bare) {
      push @found, "names ${ref} without a link; write it as [${ref}](<url>)";
    }
    my $hard_words = qr/\b(gated|ungated|callers?|derived?|derives|semantics|invariants?|predicates?|passthrough|upstream|downstream|idempotent|coerced?|coerces|hydrated?|truthy|falsy|mutates?|memoi[sz]ed?|re-?render(s|ed|ing)?|re-?fetch(es|ed|ing)?|fall-?backs?|mid-edit|early returns?|short-circuit(s|ed)?|bail(s|ed)? out)\b/i;
    if ($prose =~ $hard_words) {
      push @found, "uses the hard word \"$1\"; say it in everyday words (who sees what, what happens)";
    }
    my $asks_for_test = $prose =~ /\b(add|write|needs?|missing|a|an|another|one) (new )?(test|spec)\b/i;
    my $test_seen_failing = $ran_record =~ /\bfail/i;
    if ($asks_for_test && !$test_seen_failing) {
      push @found, "asks for a test with no proof it catches the bug: write it, put the bug back, and say in \"ran\" that it failed";
    }
    my $mentions_earlier_review = $prose =~ /\b(last|earlier|previous|first|second) (round|review)\b|\bI was wrong\b/i;
    my $has_real_run = $ran_record =~ /\S/ && $ran_record !~ m{^\s*n/?a\b}i;
    if ($mentions_earlier_review && !$has_real_run) {
      push @found, "says something about an earlier review with nothing run behind it: check that claim again and say in \"ran\" what showed it";
    }
    my $claims_query_cost = $prose =~ /\bN\s*\+\s*1\b|\b(extra|per[- ](record|row|item)|repeated) quer(y|ies)\b|\bquer(y|ies) (per|for each|once per) (record|row|item|booking|order)\b|\b\d+ (extra )?quer(y|ies)\b/i;
    my $measured_in_request = $ran_record =~ /\brequest\b/i && $ran_record =~ /\d/;
    if ($claims_query_cost && !$measured_in_request) {
      push @found, "says something about query counts with no request measuring them: count the database queries through a request (a request spec) for one record and for several, and give the counts in \"ran\"; a console or serializer call has no query cache";
    }
    my $path = $draft->{path} // "";
    my $rendered = $path =~ /\.(tsx|jsx|vue|svelte|astro|html?|erb|haml|slim|hbs|handlebars|mustache|twig|liquid|css|scss|sass|less|styl)$/i
      && $path !~ m{(^|/)(__tests__|tests?|specs?|e2e|stories)/|\.(test|spec|stories|cy)\.[a-z]+$}i;
    if ($rendered && $first !~ /^\*\*(question|note|thought|praise)\b/) {
      my $seen = $draft->{seen} // "";
      $seen = "" if ref $seen;
      my $is_capture_name = $seen =~ /$ENV{KC_CAPTURE_PATH}/i;
      my $capture_exists = -f $seen;
      if ($seen !~ /\S/) {
        push @found, "is on a screen with no \"seen\": open the running app, capture what the comment says, and give the file path";
      } elsif (!$is_capture_name || !$capture_exists) {
        push @found, "\"seen\" is not a screenshot or recording that exists: $seen";
      } elsif ($ENV{KC_HEAD_TIME} =~ /^\d+$/ && (stat $seen)[9] < $ENV{KC_HEAD_TIME}) {  # [9]: mtime
        push @found, "\"seen\" was captured before the head commit, so it shows older code: $seen";
      }
    }
    for my $problem (@found) { print "$where: $problem\n"; $problems++ }
  }
  exit($problems ? 1 : 0);
' "$1"
