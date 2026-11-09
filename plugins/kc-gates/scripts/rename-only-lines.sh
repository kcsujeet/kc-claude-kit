#!/usr/bin/env bash
# Lists the lines of a diff whose only change is a rename, so a re-review keeps the verdict the
# earlier round gave them instead of judging old code again because a rename put it back in the
# delta (kc-code-review's re-review rules, verification §V9).
#
# Usage: rename-only-lines.sh <diff-file>     (`-` reads the diff from stdin)
#
# Within each hunk, a run of removed lines followed by a run of added lines of the same length is
# read pair by pair. A pair is rename-only when both lines split into the same sequence of tokens
# except at identifier positions (a letter or `_`, then letters, digits or `_`), each old
# identifier maps to one new one throughout the pair, and at least one identifier differs. Runs of
# unequal length, and lines whose punctuation, literals or token count moved, are not listed.
#
# Prints one `path:line: old -> new[, old -> new]` per rename-only line, `line` on the new side,
# and exits 0, hits or none; 2 on a usage error or unreadable input.
set -euo pipefail

script_name=$(basename "$0")
[ "$#" -eq 1 ] || { echo "usage: $script_name <diff-file>" >&2; exit 2; }
if [ "$1" != - ] && [ ! -r "$1" ]; then
  echo "$script_name: cannot read $1" >&2
  exit 2
fi

perl -e '
  use strict; use warnings;
  my ($path, $new_line, @removed, @added) = ("", 0);
  my $identifier = qr/[A-Za-z_][A-Za-z0-9_]*/;

  sub tokens { my ($text) = @_; return grep { length } split /($identifier)/, $text }

  sub flush {
    if (@removed && @removed == @added) {
      for my $index (0 .. $#added) {
        my @old = tokens($removed[$index]);
        my @new = tokens($added[$index]->[1]);
        next unless @old == @new;
        my (%map, @order, $ok);
        $ok = 1;
        for my $position (0 .. $#old) {
          my ($was, $now) = ($old[$position], $new[$position]);
          if ($was !~ /\A$identifier\z/ || $now !~ /\A$identifier\z/) {
            if ($was ne $now) { $ok = 0; last }
            next;
          }
          # A name kept in one place and renamed in another is not a rename.
          if (exists $map{$was}) {
            if ($map{$was} ne $now) { $ok = 0; last }
          } else {
            $map{$was} = $now;
            push @order, $was if $was ne $now;
          }
        }
        next unless $ok && @order;
        printf "%s:%d: %s\n", $path, $added[$index]->[0], join(", ", map { "$_ -> $map{$_}" } @order);
      }
    }
    @removed = (); @added = ();
  }

  while (my $line = <>) {
    chomp $line;
    if ($line =~ /^\+\+\+ (?:b\/)?(.*)$/) { flush(); $path = $1; $path =~ s/\t.*$//; next }
    if ($line =~ /^--- /) { flush(); next }
    if ($line =~ /^@@ -\d+(?:,\d+)? \+(\d+)/) { flush(); $new_line = $1; next }
    if ($line =~ /^-(.*)$/) { flush() if @added; push @removed, $1; next }
    if ($line =~ /^\+(.*)$/) { push @added, [$new_line, $1]; $new_line++; next }
    flush();
    $new_line++ if $line =~ /^ /;
  }
  flush();
' "$1"
