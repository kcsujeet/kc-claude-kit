#!/usr/bin/env bash
# Regenerates rules/<topic>.md from each topic skill, skills/<topic>/SKILL.md.
#
# A generated rule is three parts: the skill's `paths:` frontmatter, a one-line
# "generated" comment, then the skill's `# Title` and its `## Rules` section,
# with every heading inside that section raised one level so the file reads as a
# standalone rule. rules/working-agreement.md has no skill and is left alone.
#
# Usage: build-rules.sh           rewrite rules/
#        build-rules.sh --check   rebuild into a temp dir; exit 1 with a diff if
#                                 rules/ differs, 0 if it is current
set -euo pipefail

plugin_dir=$(cd "$(dirname "$0")/.." && pwd)
skills_dir="$plugin_dir/skills"
rules_dir="$plugin_dir/rules"

check_only=0
case "${1:-}" in
  "") ;;
  --check) check_only=1 ;;
  *) echo "usage: $(basename "$0") [--check]" >&2; exit 2 ;;
esac

# Writes the generated rule for one skill to stdout.
render_rule() {
  local skill_file=$1
  local topic=$2
  awk -v topic="$topic" '
    NR == 1 && $0 == "---" { in_frontmatter = 1; next }
    in_frontmatter && $0 == "---" {
      in_frontmatter = 0
      if (paths == "") { print "build-rules: no paths in skills/" topic "/SKILL.md" > "/dev/stderr"; exit 1 }
      printf "---\n%s---\n<!-- Generated from skills/%s/SKILL.md by scripts/build-rules.sh. Edit the skill, not this file. -->\n\n", paths, topic
      next
    }
    in_frontmatter {
      if ($0 ~ /^paths:/) { in_paths = 1; paths = paths $0 "\n"; next }
      if (in_paths && $0 ~ /^[ \t]+- /) { paths = paths $0 "\n"; next }
      in_paths = 0
      next
    }
    title == "" && /^# / { title = $0; next }
    /^```/ { in_fence = !in_fence }
    !in_fence && $0 == "## Rules" { in_rules = 1; print title; next }
    !in_fence && in_rules && /^## / { in_rules = 0 }
    in_rules {
      line = $0
      if (!in_fence && line ~ /^###+ /) line = substr(line, 2)
      body[++body_count] = line
    }
    END {
      if (title == "" || body_count == 0) { print "build-rules: no title or ## Rules in skills/" topic "/SKILL.md" > "/dev/stderr"; exit 1 }
      while (body_count > 0 && body[body_count] == "") body_count--
      for (i = 1; i <= body_count; i++) print body[i]
    }
  ' "$skill_file"
}

output_dir=$rules_dir
if [ "$check_only" -eq 1 ]; then
  output_dir=$(mktemp -d)
  trap 'rm -rf "$output_dir"' EXIT
  cp "$rules_dir"/working-agreement.md "$output_dir"/
fi

for skill_file in "$skills_dir"/*/SKILL.md; do
  topic=$(basename "$(dirname "$skill_file")")
  grep -q '^## Rules$' "$skill_file" || continue
  render_rule "$skill_file" "$topic" > "$output_dir/$topic.md"
done

if [ "$check_only" -eq 1 ]; then
  if diff -ru "$rules_dir" "$output_dir"; then
    echo "rules/ is current"
  else
    echo "rules/ is stale: run scripts/build-rules.sh and commit the result" >&2
    exit 1
  fi
fi
