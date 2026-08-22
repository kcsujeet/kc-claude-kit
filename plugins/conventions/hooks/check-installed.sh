#!/usr/bin/env bash
# Says nothing when the conventions are installed, so the normal case costs no context.
# Anything printed here lands in the model's context at session start.
set -u

# Not a project directory, or conventions already present: stay quiet.
[ -d .git ] || exit 0
[ -f .claude/rules/working-agreement.md ] && exit 0
[ -f "$HOME/.claude/rules/working-agreement.md" ] && exit 0

echo "The portable coding conventions are not installed in this project. Run /conventions:init to copy them into .claude/rules/, or say so if this project should not have them."
