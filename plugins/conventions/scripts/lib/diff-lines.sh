# shellcheck shell=bash
# Shared diff walking for the convention sweeps. Sourced, never executed.
#
# A sweep reads a unified diff (`git diff` output, or `-` for stdin), looks only
# at the lines the diff adds, and prints one `path:line: text` hit per line,
# where `line` is the line number on the new side of the diff.
#
# Portable to bash 3.2, BSD awk and GNU awk. Regexes are POSIX EREs evaluated by
# awk, so `\b` and other GNU-only escapes are not available: spell a word
# boundary as `(^|[^A-Za-z0-9_$])`.

# Exits 2 with a usage line unless $1 is a readable file or `-`.
kc_require_diff_arg() {
  local script_name=$1
  local diff_arg=${2:-}
  local extra_usage=${3:-}
  if [ -z "$diff_arg" ]; then
    echo "usage: $script_name <diff-file|->$extra_usage" >&2
    exit 2
  fi
  if [ "$diff_arg" != "-" ] && [ ! -r "$diff_arg" ]; then
    echo "$script_name: cannot read diff file: $diff_arg" >&2
    exit 2
  fi
}

# Prints every added line as `path<TAB>new-line-number<TAB>text`.
# Hunk bodies are walked by their line counts, so an added line whose own text
# starts with `++` or `--` is never mistaken for a file header.
kc_added_lines() {
  awk '
    function reset_hunk() { old_left = 0; new_left = 0 }
    BEGIN { path = ""; reset_hunk() }
    old_left > 0 || new_left > 0 {
      marker = substr($0, 1, 1)
      if (marker == "+") {
        if (path != "") printf "%s\t%d\t%s\n", path, new_line, substr($0, 2)
        new_line++; new_left--
      } else if (marker == "-") {
        old_left--
      } else if (marker == "\\") {
        # "\ No newline at end of file" belongs to neither side.
      } else {
        new_line++; new_left--; old_left--
      }
      next
    }
    /^diff --git / { path = ""; next }
    /^\+\+\+ / {
      target = substr($0, 5)
      sub(/\t.*$/, "", target)
      if (target == "/dev/null") { path = ""; next }
      sub(/^b\//, "", target)
      path = target
      next
    }
    /^@@ / {
      header = $0
      sub(/^@@ -/, "", header)
      old_spec = header; sub(/ .*$/, "", old_spec)
      new_spec = header; sub(/^[^ ]* \+/, "", new_spec); sub(/ .*$/, "", new_spec)
      old_left = (index(old_spec, ",") > 0) ? substr(old_spec, index(old_spec, ",") + 1) + 0 : 1
      new_start = (index(new_spec, ",") > 0) ? substr(new_spec, 1, index(new_spec, ",") - 1) + 0 : new_spec + 0
      new_left = (index(new_spec, ",") > 0) ? substr(new_spec, index(new_spec, ",") + 1) + 0 : 1
      new_line = new_start
      next
    }
  ' "$1"
}

# Prints the new-side path of every file the diff creates (old side /dev/null).
kc_added_files() {
  awk '
    /^diff --git / { from_null = 0; next }
    /^--- \/dev\/null/ { from_null = 1; next }
    /^\+\+\+ / {
      target = substr($0, 5)
      sub(/\t.*$/, "", target)
      sub(/^b\//, "", target)
      if (from_null && target != "/dev/null") print target
      from_null = 0
    }
  ' "$1"
}

# Prints the new-side path of every file the diff touches, excluding deletions.
kc_changed_files() {
  awk '
    /^\+\+\+ / {
      target = substr($0, 5)
      sub(/\t.*$/, "", target)
      if (target == "/dev/null") next
      sub(/^b\//, "", target)
      print target
    }
  ' "$1" | sort -u
}

# kc_sweep <diff> <include-ERE> [exclude-ERE] [path-ERE]
# Prints `path:line: text` for each added line matching include-ERE, not matching
# exclude-ERE (when given), in a file whose path matches path-ERE (when given).
kc_sweep() {
  local diff_file=$1
  kc_added_lines "$diff_file" |
    KC_INCLUDE=$2 KC_EXCLUDE=${3:-} KC_PATHS=${4:-} awk -F '\t' '
      {
        text = $0
        sub(/^[^\t]*\t[^\t]*\t/, "", text)
        if (ENVIRON["KC_PATHS"] != "" && $1 !~ ENVIRON["KC_PATHS"]) next
        if (text !~ ENVIRON["KC_INCLUDE"]) next
        if (ENVIRON["KC_EXCLUDE"] != "" && text ~ ENVIRON["KC_EXCLUDE"]) next
        printf "%s:%s: %s\n", $1, $2, text
      }
    '
}
