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
# A hunk runs for the line counts its `@@` header gives, so a hunk line whose text starts `-- ` or
# `++ ` is read as a line, not as a file header.
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
  my ($path, $new_line, $old_left, $new_left, @removed, @added) = ("", 0, 0, 0);
  my $identifier = qr/[A-Za-z_][A-Za-z0-9_]*/;

  sub split_tokens { my ($text) = @_; return grep { length } split /($identifier)/, $text }

  # Returns the "old -> new" renames that turn <old> into <new>, or nothing when anything else changed.
  sub renames_between {
    my ($old_text, $new_text) = @_;
    my @old = split_tokens($old_text);
    my @new = split_tokens($new_text);
    return () unless @old == @new;
    my (%map, @order);
    for my $position (0 .. $#old) {
      my ($was, $now) = ($old[$position], $new[$position]);
      if ($was !~ /\A$identifier\z/ || $now !~ /\A$identifier\z/) {
        return () if $was ne $now;
        next;
      }
      # A name kept in one place and renamed in another is not a rename.
      return () if exists $map{$was} && $map{$was} ne $now;
      next if exists $map{$was};
      $map{$was} = $now;
      push @order, $was if $was ne $now;
    }
    return map { "$_ -> $map{$_}" } @order;
  }

  sub report_renamed_pairs {
    if (@removed && @removed == @added) {
      for my $index (0 .. $#added) {
        my @renames = renames_between($removed[$index], $added[$index]->[1]);
        printf "%s:%d: %s\n", $path, $added[$index]->[0], join(", ", @renames) if @renames;
      }
    }
    @removed = (); @added = ();
  }

  while (my $line = <>) {
    chomp $line;
    # A hunk line whose text starts "-- " or "++ " reads "--- " or "+++ ": it is a header only once
    # the line counts in the hunk header are used up.
    my $in_hunk = $old_left > 0 || $new_left > 0;
    if (!$in_hunk && $line =~ /^\+\+\+ (?:b\/)?(.*)$/) { report_renamed_pairs(); $path = $1; $path =~ s/\t.*$//; next }
    if (!$in_hunk && $line =~ /^--- /) { report_renamed_pairs(); next }
    if ($line =~ /^@@ -\d+(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/) {
      report_renamed_pairs();
      ($old_left, $new_line, $new_left) = ($1 // 1, $2, $3 // 1);
      next;
    }
    if ($line =~ /^-(.*)$/) { report_renamed_pairs() if @added; push @removed, $1; $old_left--; next }
    if ($line =~ /^\+(.*)$/) { push @added, [$new_line, $1]; $new_line++; $new_left--; next }
    report_renamed_pairs();
    next unless $line =~ /^ /;
    $new_line++; $old_left--; $new_left--;
  }
  report_renamed_pairs();
' "$1"
