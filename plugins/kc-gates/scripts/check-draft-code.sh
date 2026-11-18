#!/usr/bin/env bash
# Checks the code a drafted review comment shows against the repo, so a comment never hands the
# author a pattern nobody uses as if it were the house way. build-comment-payloads.sh runs it.
#
# Usage: check-draft-code.sh <drafts.json> <head-sha>
#   <drafts.json>  the JSON array of {path, line, body, ...} that build-comment-payloads.sh takes;
#                  a draft may carry "new": "<reason>" when the code it shows is meant to be new
#                  (and says so in its body)
#   <head-sha>     the commit the comments anchor to; code is looked up in its tree
#
# Code is an inline code span holding a call or a block (a `(` or a `{`), outside fenced blocks.
# A draft on the old side (side LEFT) quotes removed code, so it is not looked up.
# One that appears nowhere in the head commit's tree is reported: the comment either points at
# code that exists, or says it is new and why. Run from inside the repo; when <head-sha> is not a
# commit here, it prints nothing and exits 0.
#
# Prints one line per problem (`draft <n> (<path>:<line>): <problem>`) and exits 1 when there is
# any, 0 when every draft passes, 2 on a usage error or unreadable input.
set -euo pipefail

script_name=$(basename "$0")
[ "$#" -eq 2 ] || { echo "usage: $script_name <drafts.json> <head-sha>" >&2; exit 2; }
drafts_file=$1
head_sha=$2
[ -r "$drafts_file" ] || { echo "$script_name: cannot read $drafts_file" >&2; exit 2; }
git cat-file -e "$head_sha^{commit}" 2>/dev/null || exit 0

# `draft-number<TAB>path:line<TAB>code` per code span, from drafts without a "new" reason.
code_spans=$(perl -MJSON::PP -CS -e '
  use strict; use warnings;
  local $/; open(my $fh, "<:encoding(UTF-8)", $ARGV[0]) or exit 2;
  my $drafts = eval { JSON::PP->new->decode(<$fh>) };
  if (ref $drafts ne "ARRAY") { print STDERR "drafts file is not a JSON array\n"; exit 2 }
  my $draft_number = 0;
  for my $draft (@$drafts) {
    $draft_number++;
    next if ($draft->{new} // "") =~ /\S/;
    next if ($draft->{side} // "") eq "LEFT";
    (my $body = $draft->{body} // "") =~ s/```.*?```//gs;
    while ($body =~ /`([^`\n]*[({][^`\n]*)`/g) {
      printf "%d\t%s:%s\t%s\n", $draft_number, $draft->{path} // "?", $draft->{line} // "?", $1;
    }
  }
' "$drafts_file")

unfound_code_count=0
while IFS=$'\t' read -r draft_number draft_location code_span; do
  [ -n "$draft_number" ] || continue
  git grep -q -F -e "$code_span" "$head_sha" -- ':/' 2>/dev/null && continue
  echo "draft $draft_number ($draft_location): shows \`$code_span\`, which appears nowhere in the repo; point at code that exists, ask for the outcome instead, or say in \"new\" why it is new (and say so in the comment)"
  unfound_code_count=$((unfound_code_count + 1))
done <<EOF
$code_spans
EOF
[ "$unfound_code_count" -eq 0 ]
