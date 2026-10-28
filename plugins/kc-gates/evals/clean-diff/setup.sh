#!/usr/bin/env bash
# Builds a repo whose feature branch only fixes a typo in the README: no
# code, no behavior change, nothing any gate should fail.
set -euo pipefail

git init -q -b main
git config user.email eval@example.com
git config user.name "Eval Fixture"

mkdir -p src
cat > src/widget.ts <<'TS'
export interface Widget {
  id: string
  ownerId: string
}
TS
cat > README.md <<'MD'
# widgets

Small widget helpers for the storefront. Run the tests with your package
manager's test script before openning a pull request.
MD
git add -A
git commit -q -m "Add widget type and README"

git checkout -q -b fix/readme-typo
sed 's/openning/opening/' README.md > README.md.tmp
mv README.md.tmp README.md
git add -A
git commit -q -m "Fix typo in README"
