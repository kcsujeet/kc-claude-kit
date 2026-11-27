---
name: kc-clean-up
description: Use when a task is handed off or merged, or on "clean up": stop what the session started, remove merged worktrees and branches, drop its stashes, delete hand-on files, prune, and report what went and what stayed.
---

# Clean up

Runs once a task is handed off or merged. Candidates: `scripts/list-cleanup.sh --repo <dir>` (lists, deletes nothing). Wording: `references/detail.md`.

## Steps

1. List what the session started (background tasks, dev servers, watchers, agents); stop what is not needed.
2. Run `scripts/list-cleanup.sh --repo .`; remove worktrees whose branch is merged, then their local branches.
3. Drop the stashes this task created, never older ones.
4. Delete files made only to hand on, once the copy that matters is confirmed.
5. Run `git fetch --prune` for deleted remote branches.
6. Report what was removed and what was kept, and why.
7. Ask before deleting anything not created in this session.

## Checklist

- [ ] §CU1 Session-started tasks, servers, watchers and agents listed and stopped unless needed; the person's own servers and browser untouched.
- [ ] §CU2 Worktrees with a merged branch removed, then their branches; fetched first; none with uncommitted or unpushed work.
- [ ] §CU3 Only stashes this task created dropped (by message or date).
- [ ] §CU4 Hand-on files deleted once the copy that matters is confirmed; files the person asked for kept.
- [ ] §CU5 `git fetch --prune` run.
- [ ] §CU6 Report names what was removed, what was kept, and why.
- [ ] §CU7 Anything not created in this session was asked about before deletion.
