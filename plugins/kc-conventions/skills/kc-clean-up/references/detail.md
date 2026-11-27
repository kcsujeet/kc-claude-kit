# kc-clean-up detail

### Steps

- §CU1 Check background tasks, dev servers, watchers and agents the session started (child processes included); stop what is not needed.
- §CU1 Never stop the person's own long-running servers or browser; a restart can sign them out, so ask first.
- §CU2 Run `git fetch` first so merged status is current; `list-cleanup.sh` lists only worktrees with a clean status whose branch is merged into the default branch.
- §CU2 Remove each worktree (`git worktree remove <path>`), then its branch (`git branch -d <branch>`); never `-D` or `--force`.
- §CU2 Never touch a worktree with uncommitted or unpushed work.
- §CU3 Match stashes by message or date to this task; drop only those (`git stash drop stash@{n}`), never older ones.
- §CU4 Hand-on files: rendered videos, screenshots after upload, exports after sending, scratch copies.
- §CU4 Delete them once the copy that matters is confirmed in place; files the person asked for stay.
- §CU5 `git fetch --prune` drops remote-tracking refs for branches deleted on the remote.
- §CU6 Report two lists: removed, and kept with the reason (unmerged, dirty, older than the task, the person's own).
- §CU7 Anything not created in this session (older worktrees, stashes, files) is asked about first.
