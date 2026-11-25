#!/usr/bin/env bash
# i18n §I10: one term, one spelling. Lists every word the source-locale values write in more
# than one spelling once case and hyphens are set aside (`Add-ons` beside `Addons`,
# `e-mail` beside `email`), so a renamed term has no old spelling left on another screen.
# A lookup over the whole tree, not a diff sweep: the stale spelling sits in lines the diff
# never touched.
#
# Usage: term-spellings.sh <locale-dir>
# Reads the values of every .json file under <locale-dir> and prints one line per word, sorted:
#   <word>: <most used spelling> x<count> (first <path>:<line>); <other spelling> (<path>:<line>, ...)
# with every place of each other spelling, since each is a string to change or a call to make. Placeholder names and ICU arguments are
# skipped; the text inside plural and select branches is read. Each hit is a lead: two spellings
# with two meanings (`checkout` the purchase, `check-out` the departure) are judged by reading.
# Exits 0 with or without hits, 2 on a usage error.
set -euo pipefail

script_name=$(basename "$0")
if [ "$#" -ne 1 ] || [ ! -d "$1" ]; then
  echo "usage: $script_name <locale-dir>" >&2
  exit 2
fi

find "$1" -type f -name '*.json' | LC_ALL=C sort | while IFS= read -r locale_file; do
  awk -v path="$locale_file" '
    # A value is the text after the colon; placeholders ({name}, {count, plural, ...}) are dropped.
    match($0, /"[^"]*"[[:space:]]*:[[:space:]]*"/) {
      value = substr($0, RSTART + RLENGTH)
      sub(/",?[[:space:]]*$/, "", value)
      # A placeholder name or an ICU argument ({name}, {count, plural, =0 ...) is not text.
      gsub(/[{][[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*[}]/, " ", value)
      gsub(/[{][[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*,[^{}]*/, " ", value)
      gsub(/[{}#]/, " ", value)
      n = split(value, words, /[^A-Za-z-]+/)
      for (i = 1; i <= n; i++) {
        word = words[i]
        gsub(/^-+|-+$/, "", word)
        if (length(word) < 3) continue
        printf "%s\t%s:%d\n", word, path, NR
      }
    }' "$locale_file"
done | awk -F '\t' '
  {
    # Case is not a spelling: `Add-ons` and `add-ons` are one, `Addons` another.
    spelling = tolower($1)
    norm = spelling
    gsub(/-/, "", norm)
    key = norm SUBSEP spelling
    if (!(key in uses)) {
      spellings[norm] = spellings[norm] SUBSEP spelling
      hyphen[norm] = hyphen[norm] || index(spelling, "-") > 0
      joined[norm] = joined[norm] || index(spelling, "-") == 0
    }
    uses[key]++
    places[key] = places[key] (uses[key] > 1 ? ", " : "") $2
    if (uses[key] == 1) first[key] = $2
  }
  END {
    for (norm in spellings) {
      if (!(hyphen[norm] && joined[norm])) continue
      count = split(substr(spellings[norm], 2), list, SUBSEP)
      # The most used spelling is the one kept: it gets its count; every other spelling, each place.
      top = list[1]
      for (i = 2; i <= count; i++) if (uses[norm, list[i]] > uses[norm, top]) top = list[i]
      line = norm ": " top " x" uses[norm, top] " (first " first[norm, top] ")"
      for (i = 1; i <= count; i++) if (list[i] != top) line = line "; " list[i] " (" places[norm, list[i]] ")"
      print line
    }
  }' | LC_ALL=C sort
