#!/usr/bin/env bash
# Prints the SHA-256 hex digest of a file, with whichever tool the machine has. Shared by
# build-comment-payloads.sh, which stamps the review payload it built, and guard-github-post.sh,
# which posts only a payload whose stamp still matches, so the two always hash the same way.
print_file_sha256() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | cut -d' ' -f1
  else
    sha256sum "$1" | cut -d' ' -f1
  fi
}
