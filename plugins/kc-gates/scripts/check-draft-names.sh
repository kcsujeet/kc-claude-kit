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
# in the tree is new, and a new name one edit (a letter added, dropped or changed) from a name that
# is in the tree is reported: `customersEmail` beside `customerEmail`.
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
  local $/; open(my $fh, "<:encoding(UTF-8)", $ARGV[0]) or exit 2;
  my $drafts = eval { JSON::PP->new->decode(<$fh>) };
  if (ref $drafts ne "ARRAY") { print STDERR "drafts file is not a JSON array\n"; exit 2 }
  my $index = 0;
  for my $draft (@$drafts) {
    $index++;
    next if defined $draft->{names} && $draft->{names} =~ /\S/;
    (my $body = $draft->{body} // "") =~ s/```.*?```//gs;
    my %seen;
    while ($body =~ /`([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)`/g) {
      for my $name (split /\./, $1) {
        next if length($name) < 4 || $seen{$name}++;
        printf "%d\t%s:%s\t%s\n", $index, $draft->{path} // "?", $draft->{line} // "?", $name;
      }
    }
  }
' "$drafts_file")
[ -n "$suggested" ] || exit 0

new_names=""
while IFS=$'\t' read -r _ _ name; do
  git grep -q -w -F -e "$name" "$head_sha" -- . 2>/dev/null || new_names+="$name"$'\n'
done <<< "$suggested"
[ -n "$new_names" ] || exit 0

# Every identifier in the tree, then each new name's neighbours one edit away.
known_names=$(git grep -h -o -w -I -E '[A-Za-z_][A-Za-z0-9_]{2,}' "$head_sha" -- . 2>/dev/null | sort -u)
neighbours=$(KC_NEW="$new_names" perl -e '
  use strict; use warnings;
  my %new = map { $_ => 1 } grep { length } split /\n/, $ENV{KC_NEW};
  # True when a and b differ by one letter added, dropped or changed.
  sub one_edit {
    my ($a, $b) = @_;
    my ($la, $lb) = (length $a, length $b);
    return 0 if abs($la - $lb) > 1 || $a eq $b;
    if ($la == $lb) { my $d = () = ($a ^ $b) =~ /[^\0]/g; return $d == 1 }
    ($a, $b) = ($b, $a) if $la > $lb;
    for my $i (0 .. length($b) - 1) { return 1 if substr($b, 0, $i) . substr($b, $i + 1) eq $a }
    return 0;
  }
  my %near;
  while (my $known = <STDIN>) {
    chomp $known;
    for my $name (keys %new) { push @{ $near{$name} }, $known if one_edit($name, $known) }
  }
  for my $name (sort keys %near) { printf "%s\t%s\n", $name, join(", ", map { "`$_`" } sort @{ $near{$name} }) }
' <<< "$known_names")
[ -n "$neighbours" ] || exit 0

problems=0
while IFS=$'\t' read -r number where name; do
  near=$(printf '%s\n' "$neighbours" | awk -F'\t' -v name="$name" '$1 == name { print $2 }')
  [ -n "$near" ] || continue
  echo "draft $number ($where): suggests \`$name\`, one letter from $near already in the repo; pick a name that differs more, or say why in \"names\""
  problems=$((problems + 1))
done <<< "$suggested"
[ "$problems" -eq 0 ]
