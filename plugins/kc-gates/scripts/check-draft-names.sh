#!/usr/bin/env bash
# Checks the names drafted review comments suggest against the names already in the repo, so a
# suggestion never reads as a typo of something that exists. build-comment-payloads.sh runs it.
#
# Usage: check-draft-names.sh <drafts.json> <head-sha>
#   <drafts.json>  the JSON array of {path, line, body, ...} that build-comment-payloads.sh takes;
#                  a draft may carry "names": "<reason>" when a near name is meant (a rename to fix
#                  a typo, say)
#   <head-sha>     the commit the comments anchor to; names are read from its tree
#
# A name is an identifier in inline code in a body (`customerEmail`, `orders.customerEmail`; each
# dotted part on its own), four characters or longer, outside fenced code blocks. One that is not
# in the head commit's tree (the whole repo, whichever folder this runs from) is new, and a new
# name one edit (a letter added, dropped or changed) from a name that is in the tree is reported:
# `customersEmail` beside `customerEmail`.
#
# Run from inside the repo. When <head-sha> is not a commit here (a draft checked away from its
# repo), it prints nothing and exits 0, since there is nothing to compare against.
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

# `draft-number<TAB>path:line<TAB>name` per suggested name, from drafts without a "names" reason.
suggested=$(perl -MJSON::PP -CS -e '
  use strict; use warnings;
  # A shorter name reads as a word, not a typo of one.
  my $min_name_length = 4;
  local $/; open(my $fh, "<:encoding(UTF-8)", $ARGV[0]) or exit 2;
  my $drafts = eval { JSON::PP->new->decode(<$fh>) };
  if (ref $drafts ne "ARRAY") { print STDERR "drafts file is not a JSON array\n"; exit 2 }
  my $index = 0;
  for my $draft (@$drafts) {
    $index++;
    my $names_reason = $draft->{names} // "";
    next if $names_reason =~ /\S/;
    my $path = $draft->{path} // "?";
    my $line = $draft->{line} // "?";
    (my $body = $draft->{body} // "") =~ s/```.*?```//gs;
    my %seen;
    while ($body =~ /`([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)`/g) {
      for my $name (split /\./, $1) {
        next if length($name) < $min_name_length;
        next if $seen{$name}++;
        printf "%d\t%s:%s\t%s\n", $index, $path, $line, $name;
      }
    }
  }
' "$drafts_file")

# Every identifier in the head commit's tree, whatever folder this runs from (`:/` is the repo's
# top). A suggested name in it is a reference; one that isn't, and is one edit from one that is,
# is reported.
git grep -h -o -w -I -E '[A-Za-z_][A-Za-z0-9_]{2,}' "$head_sha" -- ':/' 2>/dev/null | sort -u |
  KC_SUGGESTED="$suggested" perl -e '
    use strict; use warnings;
    my %known = map { chomp; $_ => 1 } <STDIN>;
    # True when a and b differ by one letter added, dropped or changed.
    sub one_edit {
      my ($a, $b) = @_;
      my ($la, $lb) = (length $a, length $b);
      return 0 if abs($la - $lb) > 1;
      if ($la == $lb) { my $d = () = ($a ^ $b) =~ /[^\0]/g; return $d == 1 }
      ($a, $b) = ($b, $a) if $la > $lb;
      for my $i (0 .. length($b) - 1) { return 1 if substr($b, 0, $i) . substr($b, $i + 1) eq $a }
      return 0;
    }
    my $problems = 0;
    for my $row (grep { length } split /\n/, $ENV{KC_SUGGESTED}) {
      my ($number, $where, $name) = split /\t/, $row;
      next if $known{$name};
      my @near = sort grep { one_edit($name, $_) } keys %known;
      next unless @near;
      my $near_list = join(", ", map { "`$_`" } @near);
      print "draft $number ($where): suggests `$name`, one letter from $near_list already in the repo; pick a name that differs more, or say why in \"names\"\n";
      $problems++;
    }
    exit($problems ? 1 : 0);
  '
