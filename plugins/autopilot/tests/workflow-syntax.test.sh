#!/usr/bin/env bash
# Checks workflows/*.js parse as JavaScript modules and obey the workflow
# runtime's rules: meta first, no Date.now/Math.random/new Date()/import().
# Rules: https://code.claude.com/docs/en/workflows ("Edit a saved script").
set -euo pipefail
tests_dir=$(cd "$(dirname "$0")" && pwd)
dir="$(dirname "$tests_dir")/workflows"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failures=0
for file in "$dir"/*.js; do
  name=$(basename "$file")
  # Wrap in an async function so top-level await and return parse.
  { echo 'const agent=async()=>null,parallel=async()=>[],pipeline=async()=>[],phase=()=>{},log=()=>{},args={};'
    echo 'export const __run = async () => {'
    sed '/^export const meta/,/^}/d' "$file"
    echo '}'; } > "$tmp/$name.mjs"
  if node --check "$tmp/$name.mjs"; then echo "ok   $name parses"; else echo "FAIL $name parses"; failures=$((failures + 1)); fi
  if head -n 1 "$file" | grep -q '^export const meta = {'; then echo "ok   $name meta first"; else echo "FAIL $name meta first"; failures=$((failures + 1)); fi
  if grep -nE 'Date\.now\(|Math\.random\(|new Date\(\)|import\(' "$file"; then echo "FAIL $name forbidden call"; failures=$((failures + 1)); else echo "ok   $name no forbidden calls"; fi
done
[ "$failures" = 0 ]
