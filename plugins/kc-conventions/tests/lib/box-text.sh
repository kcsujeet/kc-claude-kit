# shellcheck shell=bash
# Sourced by the rules-text tests, which set plugin_dir before sourcing.

# box_text <skill dir name> <§ID>: a checklist box's line from the skill's SKILL.md, then the section of
# references/detail.md headed with that id, where a long box's full wording lives (the box is one line,
# at most 220 characters; scripts/check-box-length.sh). A test that asks what a box says reads both.
box_text() {
  local skill_dir="${plugin_dir:?}/skills/$1" id=$2
  grep -E "^- \[ \] $id( |\$)" "$skill_dir/SKILL.md" || true
  awk -v id="$id" '
    /^#+ / { match($0, /^#+/); level = RLENGTH; if (on && level <= start) exit; if (!on && $0 ~ ("^#+ " id "([^0-9A-Za-z]|$)")) { on = 1; start = level; next } }
    on' "$skill_dir/references/detail.md"
}

# box_has <skill dir name> <§ID> <extended regex> [<grep option>]: succeeds when box_text holds a match. Read
# through a variable, so grep -q closing the pipe early cannot fail the test under pipefail.
box_has() {
  local text
  text=$(box_text "$1" "$2")
  if [ "${4:-}" = i ]; then grep -Eiq -- "$3" <<< "$text"; else grep -Eq -- "$3" <<< "$text"; fi
}
