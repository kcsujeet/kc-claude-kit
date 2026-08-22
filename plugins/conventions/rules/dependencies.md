---
paths:
  - "**/package.json"
  - "**/Gemfile"
  - "**/pnpm-workspace.yaml"
  - "**/requirements.txt"
  - "**/pyproject.toml"
  - "**/go.mod"
  - "**/Cargo.toml"
  - "**/*.podspec"
  - "**/Package.swift"
---

# Dependencies

Code is cheap; maintenance is not. Prefer the platform over a package, and a well-established package over rolling your own.

- **Ask before adding a dependency.** Never add one as a side effect of another task.
- Check and state, before installing: healthy download volume, a release in the last six months, more than one maintainer.
- Nothing single-maintainer or freshly published for anything touching auth, crypto, networking, or file handling.
- No new dependency for something the standard library, the framework, or an existing dependency already does. Check what is already installed first.
- Exact versions, lockfile committed. Never pin to a floating latest.
- Check how the repo manages versions before adding anything: a monorepo with a catalog or a shared manifest has one place versions are declared, and adding to the wrong one silently diverges.
- Removing an unused dependency is a change worth making on its own, not a side quest inside a feature.
