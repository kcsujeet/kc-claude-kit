#!/usr/bin/env bash
#
# export-agent-skills.sh: copy every kit skill into another agent's skills directory.
#
# Usage:
#   scripts/export-agent-skills.sh [--gemini-extension] <dest-dir>
#
#   <dest-dir>            Skills land directly in it. Point it at any tool's
#                         skills directory, for example <repo>/.agents/skills
#                         (Antigravity workspace) or ~/.gemini/config/skills
#                         (Antigravity global), https://antigravity.google/docs/skills.
#   --gemini-extension    Skills land in <dest-dir>/skills and a
#                         <dest-dir>/gemini-extension.json manifest is written,
#                         making <dest-dir> a Gemini CLI extension
#                         (https://geminicli.com/docs/extensions/reference/).
#                         Gemini requires the extension name to match its
#                         directory name, so name <dest-dir> "kc-claude-kit".
#
# What it does, per skill directory plugins/<plugin>/skills/<skill>/:
#   - copies it to <skills-dir>/kc-<plugin>-<skill>/ (replacing an earlier export);
#   - sets the frontmatter `name:` to kc-<plugin>-<skill>, because other tools
#     share one flat namespace in which bare names like `naming` collide;
#   - in SKILL.md, rewrites `${CLAUDE_PLUGIN_ROOT}/skills/<s>/` to the absolute
#     path of the exported kc-<plugin>-<s>/, so a bundled script referenced as
#     `${CLAUDE_PLUGIN_ROOT}/skills/<topic>/scripts/x.sh` resolves to
#     `<new skill dir>/scripts/x.sh`;
#   - rewrites `<plugin>:<skill>` references to exported skills into their
#     kc-<plugin>-<skill> names;
#   - if a bundled script sources the plugin's shared library through
#     `../../../scripts/lib/` (the conventions sweeps do), copies
#     plugins/<plugin>/scripts/lib/ into the skill's scripts/lib/ and points
#     the scripts at `lib/`, so the exported skill is self-contained.
#
# Skipped on purpose:
#   - code-review/post-review: its safety depends on a Claude Code PreToolUse
#     hook that blocks unapproved GitHub posts. No other tool runs that hook.
#   - conventions/init: it copies the plugin-level rules/ directory into
#     .claude/rules/. Neither exists for another tool: rules/ is not a skill
#     and is not exported, and .claude/rules/ is read only by Claude Code.
#
# Limitations of the path rewrite:
#   - Only the `${CLAUDE_PLUGIN_ROOT}/skills/<s>/...` form is rewritten, which is
#     the form docs/architecture.md prescribes for sweep scripts. Anything else
#     under the plugin root (rules/, hooks/, agents/, scripts/) is not exported,
#     so a SKILL.md that still names `CLAUDE_PLUGIN_ROOT` after the rewrite is
#     reported with a warning and left as is.
#   - Only SKILL.md, plus the `../../../scripts/lib/` path in files directly
#     under a skill's scripts/, is rewritten. Everything else is copied
#     verbatim; a script that reads CLAUDE_PLUGIN_ROOT from its environment, or
#     reaches the plugin root by some other relative path, gets nothing.
#   - The rewritten paths are absolute, so moving the exported directory breaks
#     them. Re-run the export instead of moving it.
#   - Claude Code-only frontmatter (disable-model-invocation, paths,
#     allowed-tools) is kept; other tools ignore what they do not know.
#   - Gate agents and hooks are Claude Code features and are not exported.

set -euo pipefail

SKIPPED_SKILLS=(
  "code-review/post-review|posting to GitHub is guarded by a Claude Code hook that other tools do not run"
  "conventions/init|it installs plugin rules into .claude/rules/, which only Claude Code reads"
)

usage() {
  echo "usage: $(basename "$0") [--gemini-extension] <dest-dir>" >&2
  exit 2
}

gemini_extension=false
dest_arg=""
while [ $# -gt 0 ]; do
  case "$1" in
    --gemini-extension) gemini_extension=true ;;
    -h | --help) usage ;;
    -*)
      echo "unknown option: $1" >&2
      usage
      ;;
    *)
      if [ -n "$dest_arg" ]; then usage; fi
      dest_arg="$1"
      ;;
  esac
  shift
done
if [ -z "$dest_arg" ]; then usage; fi

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"

mkdir -p "$dest_arg"
dest_dir="$(cd "$dest_arg" && pwd -P)"
if [ "$gemini_extension" = true ]; then
  skills_dir="$dest_dir/skills"
else
  skills_dir="$dest_dir"
fi
mkdir -p "$skills_dir"

skip_reason() {
  local key="$1" entry
  for entry in "${SKIPPED_SKILLS[@]}"; do
    if [ "${entry%%|*}" = "$key" ]; then
      echo "${entry#*|}"
      return 0
    fi
  done
  return 1
}

# plugin/skill pairs to export, collected first so cross-skill references can
# be rewritten only when their target is exported too.
exported=()
for skill_path in "$repo_root"/plugins/*/skills/*/; do
  [ -f "$skill_path/SKILL.md" ] || continue
  skill_path="${skill_path%/}"
  skill="$(basename "$skill_path")"
  plugin="$(basename "$(dirname "$(dirname "$skill_path")")")"
  if reason="$(skip_reason "$plugin/$skill")"; then
    echo "note: skipped $plugin/$skill: $reason"
    continue
  fi
  exported+=("$plugin/$skill")
done

if [ ${#exported[@]} -eq 0 ]; then
  echo "no skills found under $repo_root/plugins/*/skills/" >&2
  exit 1
fi

# Rewrites one SKILL.md in place. Literal (index-based) replacement, so paths
# containing regex or sed metacharacters are safe.
rewrite_skill_md() {
  local file="$1" plugin="$2" new_name="$3" tmp
  tmp="$(mktemp)"
  awk \
    -v plugin="$plugin" \
    -v new_name="$new_name" \
    -v skills_dir="$skills_dir" \
    -v exported="${exported[*]}" '
    function replace_all(text, find, repl,    out, pos) {
      out = ""
      while ((pos = index(text, find)) > 0) {
        out = out substr(text, 1, pos - 1) repl
        text = substr(text, pos + length(find))
      }
      return out text
    }
    # `plugin:skill` followed by a character that cannot continue a name.
    function replace_ref(text, find, repl,    out, pos, next_char) {
      out = ""
      while ((pos = index(text, find)) > 0) {
        next_char = substr(text, pos + length(find), 1)
        out = out substr(text, 1, pos - 1)
        if (next_char ~ /[A-Za-z0-9_-]/) {
          out = out find
        } else {
          out = out repl
        }
        text = substr(text, pos + length(find))
      }
      return out text
    }
    BEGIN {
      count = split(exported, pairs, " ")
      for (i = 1; i <= count; i++) {
        split(pairs[i], parts, "/")
        export_plugin[i] = parts[1]
        export_skill[i] = parts[2]
      }
    }
    NR == 1 && $0 == "---" { in_frontmatter = 1; print; next }
    in_frontmatter && $0 == "---" { in_frontmatter = 0; print; next }
    in_frontmatter && /^name:/ { print "name: " new_name; next }
    {
      line = $0
      for (i = 1; i <= count; i++) {
        if (export_plugin[i] == plugin) {
          line = replace_all(line, \
            "${CLAUDE_PLUGIN_ROOT}/skills/" export_skill[i] "/", \
            skills_dir "/kc-" plugin "-" export_skill[i] "/")
        }
        line = replace_ref(line, \
          export_plugin[i] ":" export_skill[i], \
          "kc-" export_plugin[i] "-" export_skill[i])
      }
      print line
    }
  ' "$file" >"$tmp"
  cat "$tmp" >"$file"
  rm -f "$tmp"
}

# Replaces every literal occurrence of <find> with <repl> in <file>.
replace_literal_in_file() {
  local file="$1" find="$2" repl="$3" tmp
  tmp="$(mktemp)"
  awk -v find="$find" -v repl="$repl" '
    {
      line = $0
      out = ""
      while ((pos = index(line, find)) > 0) {
        out = out substr(line, 1, pos - 1) repl
        line = substr(line, pos + length(find))
      }
      print out line
    }
  ' "$file" >"$tmp"
  cat "$tmp" >"$file"
  rm -f "$tmp"
}

# Sweep scripts live at skills/<skill>/scripts/ and source the plugin-level
# scripts/lib/ three directories up, which is not part of the skill. Bundle
# that library into the exported skill and repoint the scripts at it.
bundle_plugin_lib() {
  local target_dir="$1" plugin="$2" plugin_lib script
  local lib_ref="../../../scripts/lib/"
  plugin_lib="$repo_root/plugins/$plugin/scripts/lib"
  [ -d "$target_dir/scripts" ] || return 0
  grep -rqF "$lib_ref" "$target_dir/scripts" || return 0
  if [ ! -d "$plugin_lib" ]; then
    echo "warning: $target_dir/scripts references $lib_ref but $plugin_lib does not exist" >&2
    return 0
  fi
  mkdir -p "$target_dir/scripts/lib"
  cp -R "$plugin_lib/." "$target_dir/scripts/lib/"
  for script in "$target_dir"/scripts/*; do
    [ -f "$script" ] || continue
    if grep -qF "$lib_ref" "$script"; then
      replace_literal_in_file "$script" "$lib_ref" "lib/"
    fi
  done
}

# A skill may run a plugin-level script, `${CLAUDE_PLUGIN_ROOT}/scripts/<name>.sh`
# (the conventions citation map is one). Copy each such script into the
# exported skill's scripts/, with the plugin's scripts/lib/ it sources, and
# point SKILL.md at the copy.
bundle_plugin_scripts() {
  local target_dir="$1" plugin="$2" script_name source_script
  # shellcheck disable=SC2016 # the literal placeholder text, not an expansion
  local ref_prefix='${CLAUDE_PLUGIN_ROOT}/scripts/'
  { grep -oE '\$\{CLAUDE_PLUGIN_ROOT\}/scripts/[A-Za-z0-9._-]+\.sh' "$target_dir/SKILL.md" 2>/dev/null || true; } \
    | sort -u | while IFS= read -r ref; do
      script_name="${ref#"$ref_prefix"}"
      source_script="$repo_root/plugins/$plugin/scripts/$script_name"
      if [ ! -f "$source_script" ]; then
        echo "warning: $target_dir/SKILL.md names $ref but $source_script does not exist" >&2
        continue
      fi
      mkdir -p "$target_dir/scripts"
      cp "$source_script" "$target_dir/scripts/$script_name"
      if [ -d "$repo_root/plugins/$plugin/scripts/lib" ]; then
        mkdir -p "$target_dir/scripts/lib"
        cp -R "$repo_root/plugins/$plugin/scripts/lib/." "$target_dir/scripts/lib/"
      fi
      replace_literal_in_file "$target_dir/SKILL.md" "$ref" "$target_dir/scripts/$script_name"
    done
}

for pair in "${exported[@]}"; do
  plugin="${pair%%/*}"
  skill="${pair#*/}"
  new_name="kc-$plugin-$skill"
  source_dir="$repo_root/plugins/$plugin/skills/$skill"
  target_dir="$skills_dir/$new_name"

  rm -rf "$target_dir"
  mkdir -p "$target_dir"
  cp -R "$source_dir/." "$target_dir/"
  rewrite_skill_md "$target_dir/SKILL.md" "$plugin" "$new_name"
  bundle_plugin_lib "$target_dir" "$plugin"
  bundle_plugin_scripts "$target_dir" "$plugin"

  if grep -n 'CLAUDE_PLUGIN_ROOT' "$target_dir/SKILL.md" >/dev/null; then
    echo "warning: $new_name/SKILL.md still names CLAUDE_PLUGIN_ROOT (not a skill path, left as is):" >&2
    grep -n 'CLAUDE_PLUGIN_ROOT' "$target_dir/SKILL.md" | sed "s|^|  $new_name/SKILL.md:|" >&2
  fi
  echo "exported $plugin/$skill -> $target_dir"
done

# Highest X.Y.Z among the plugin manifests: the extension bundles every plugin,
# so it moves whenever the furthest-ahead plugin does.
manifest_version() {
  local manifest="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -r '.version // empty' "$manifest"
  else
    sed -n 's/^  "version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$manifest" | head -n 1
  fi
}

extension_version() {
  local manifest
  for manifest in "$repo_root"/plugins/*/.claude-plugin/plugin.json; do
    manifest_version "$manifest"
  done | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -t. -k1,1n -k2,2n -k3,3n | tail -n 1
}

json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

if [ "$gemini_extension" = true ]; then
  version="$(extension_version)"
  if [ -z "$version" ]; then
    echo "could not read a plugin version from plugins/*/.claude-plugin/plugin.json" >&2
    exit 1
  fi
  description="Sujeet's personal coding conventions and review skills, exported from the kc-claude-kit Claude Code marketplace"
  cat >"$dest_dir/gemini-extension.json" <<EOF
{
  "name": "kc-claude-kit",
  "version": "$(json_escape "$version")",
  "description": "$(json_escape "$description")"
}
EOF
  echo "wrote $dest_dir/gemini-extension.json (version $version)"
  if [ "$(basename "$dest_dir")" != "kc-claude-kit" ]; then
    echo "note: Gemini CLI expects the extension directory to be named kc-claude-kit, not $(basename "$dest_dir")" >&2
  fi
fi
