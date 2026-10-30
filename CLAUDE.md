# CLAUDE.md

This repo is public. Anyone can install and read these plugins.

## Examples stay neutral

Rules here are often learned while working on other projects. Write the lesson, never the project:

- No names, ticket ids, people, repo or file paths, class or component names, or domain details from the project a rule came from. That covers files, commit messages, PR titles and PR descriptions.
- Examples use a neutral domain (a shop, its storefronts and orders) and placeholder ids (`ABC-1`).
- Before committing or editing a PR, read the diff and the PR text for anything that names where a lesson came from, and rewrite it.

## Rules stay general

A lesson arrives as one case; the rule is the habit that catches the whole class. Before writing it, strip what the case brought with it:

- No one API shape (query params, includes, REST verbs), library (`lodash`), framework name or UI element (a picker, when the habit covers every read).
- State the principle at the widest scope it holds, and keep the case as one example among several ("a list, table, picker, search or count").
- Examples show the idea in plain code a reader of any stack can follow.

## Lessons

Lessons arrive from the maintainer's other work: a correction, a review comment or a QA finding that would have been caught by a habit. Each becomes its own PR here, written to the two sections above, and is merged once its checks pass, so installs get it on their next update.

## Before a PR

Run `/kc-gates:kc-ready-for-review`: it walks `.claude/hand-off-checklist.md`, which checks the two sections above and the version bump.

## Developing

Layout, conventions and release steps are in the README's "Developing" section and in `docs/architecture.md`.
