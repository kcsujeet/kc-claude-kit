#!/usr/bin/env bash
# shellcheck disable=SC2016 # single-quoted text holds Markdown backticks and awk code, not shell expansions
# Writes plugins/kc-gates/agents/<topic>-gate.md for each convention topic from one template, or with
# --check fails when a file differs from what the template makes (drift).
#
# The topic gates are one agent with the topic filled in. An agent's `skills:` preload list is static
# frontmatter and cannot take the topic as a parameter, so each topic keeps its own file; this script
# is the only place their text is written, and CI runs --check so none is edited by hand.
#
# Template placeholders: {{TOPIC}}, {{EXTRA_SKILL}} (a second preloaded skill), {{PRELOAD_NOTE}} (the
# sentence about it), {{APPLIES}} (when the gate may return PASS (N/A)), {{EXTRA_SECTION}}.
#
# Usage: build-gate-agents.sh <template> [--check] [--out-dir <dir>]
#   --out-dir  where the agent files go (default: the agents/ folder next to the template)
# Prints one line per file that differs and exits 1 with --check when there is any, 0 otherwise.
set -euo pipefail

TOPICS="clarity correctness datetime i18n naming rails react security simplicity structure testing"
DEFAULT_APPLIES='This gate applies to every diff. A box is N/A only under its own stated N/A condition.'

# The text the template takes for one placeholder of one topic.
get_extra_skill() {
  case "$1" in
    correctness) printf '\n  - kc-conventions:kc-performance' ;;
  esac
}
get_preload_note() {
  case "$1" in
    correctness) printf '%s' ' `kc-conventions:kc-performance` is preloaded too: its `## Review checklist` (the §PF boxes), detail and `## Sweeps` are graded in this same block, the same way (invoke it with the Skill tool when it is not in your context).' ;;
  esac
}
get_applies() {
  case "$1" in
    datetime) printf '%s' 'Return `STATUS: PASS (N/A)` only after reading the diff and finding no date or time logic in it; say so in the evidence.' ;;
    i18n) printf '%s' 'Return `STATUS: PASS (N/A)` only after reading the diff and finding no locale or translation file in it; say so in the evidence.' ;;
    rails) printf '%s' 'Return `STATUS: PASS (N/A)` only after reading the diff and finding no Ruby, rake, Gemfile or `db/` change in it; say so in the evidence.' ;;
    react) printf '%s' 'Return `STATUS: PASS (N/A)` only after reading the diff and finding no React or JSX UI code in it; say so in the evidence.' ;;
    security) printf '%s' 'Return `STATUS: PASS (N/A)` only after reading the diff and finding no handler, route, callback or request input in it; say so in the evidence.' ;;
    testing) printf '%s' 'Return `STATUS: PASS (N/A)` only after reading the diff and finding that it changes no behavior and touches no test file; say so in the evidence.' ;;
    *) printf '%s' "$DEFAULT_APPLIES" ;;
  esac
}
get_extra_section() {
  case "$1" in
    i18n) cat <<'EOF'
## The per-key audit table is mandatory

When the diff touches any locale or translation file, the per-key audit table from the skill's §I1 is the first thing in your evidence: one row per new key, in the exact row shape §I1 gives, every cell filled after actually running the §I3 greps and the ICU and naming checks for that key. Put the table under the `BOXES:` line for §I1, before the other boxes.

- A missing or incomplete table is an automatic gate FAIL.
- An aggregate report ("checked 7 keys, all unique") is not the table and fails §I1.
- "It matches the neighbors", "low-value" and "no new keys" are not valid reasons to skip it. If the diff touches a locale file and adds no key, say which file was touched and that it adds no key, and still walk §I3 over the touched file's pre-existing keys.
- Do not fill rows from memory.

EOF
      ;;
  esac
}

template=""
check=false
out_dir=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --check) check=true ;;
    --out-dir) out_dir=${2:?--out-dir needs a folder}; shift ;;
    *) template=$1 ;;
  esac
  shift
done
[ -r "$template" ] || { echo "usage: build-gate-agents.sh <template> [--check] [--out-dir <dir>]" >&2; exit 2; }
out_dir=${out_dir:-$(cd "$(dirname "$template")" && pwd)/agents}

# render_gate <topic>: the agent file's text for the topic.
render_gate() {
  local topic=$1 content section
  content=$(cat "$template"; printf x)
  content=${content%x}
  content=${content//"{{EXTRA_SKILL}}"/$(get_extra_skill "$topic")}
  content=${content//"{{PRELOAD_NOTE}}"/$(get_preload_note "$topic")}
  content=${content//"{{APPLIES}}"/$(get_applies "$topic")}
  section=$(get_extra_section "$topic")
  if [ -n "$section" ]; then section="$section"$'\n'; fi
  content=${content//"{{EXTRA_SECTION}}"/$section}
  content=${content//"{{TOPIC}}"/$topic}
  printf '%s' "$content"
}

drifted=0
for topic in $TOPICS; do
  target="$out_dir/$topic-gate.md"
  rendered=$(render_gate "$topic"; printf x)
  rendered=${rendered%x}
  if $check; then
    if [ "$(cat "$target" 2>/dev/null; printf x)" != "$rendered$(printf x)" ]; then
      echo "drift: $target differs from the template; run scripts/build-gate-agents.sh $template"
      drifted=1
    fi
  else
    mkdir -p "$out_dir"
    printf '%s' "$rendered" > "$target"
  fi
done
exit "$drifted"
