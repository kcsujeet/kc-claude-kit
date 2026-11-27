---
name: kc-post-review
description: "Drafts review findings and replies to reviewers as PR comments, posted only on the user's fresh post signal. Use before writing ANY PR comment or reply, even \"Done in <sha>\", and before drafting any message sent under the user's name (chat, DM, issue comment). Also /kc-gates:kc-post-review."
---


# Drafting and posting PR comments

Load this before drafting any PR comment or reply (replies to reviewers on your own PR included) and any chat, DM or ticket message the user sends as themselves. This follows a `kc-code-review` run on someone else's PR (it already walked the change; no second QA here). Its findings become [Conventional Comments](https://conventionalcomments.org/) here. Nothing is posted without the user's fresh post signal. Full wording, tone examples and the closed spec: `${CLAUDE_PLUGIN_ROOT}/skills/kc-post-review/references/detail.md` (read the matching `### ` section when a line here is unclear).

## Steps

1. Paste the Checklist below in chat with each box answered, before the first draft.
2. Pick what to post: leave out nits the author fixes in seconds (a stale or restating comment, a redundant cast, wording); keep naming, named conditions, hard-to-read logic, duplication, placement, translation keys and bugs. Say in one line what was left out.
3. Re-read at the head SHA every claim a draft makes about the code; a reworded finding is a new claim.
4. Pick each label from the table, never from how strongly the user phrased it.
5. Write each draft: label on its own line, body below, no em dash, no `§` citation, no praise opener, no emoji, no `(blocking)`.

```
**<label>** [(decoration)]:
<body>
```

| Label | When |
|-------|------|
| suggestion | A specific change with a brief reason (one clause). The default for naming, refactor, structure. |
| nitpick | Taste only; the code works. |
| issue | A defect to fix before merge. No `(blocking)`. |
| question | Real uncertainty about why. |
| chore | A small task before merge. |
| todo | A necessary change that is not a defect (missing test, doc comment). |
| note | Information, no action. |
| thought | An idea, not for this PR. |
| praise | Something genuinely well done. |

6. Length: a chat finding is one line; a drafted comment is one to three sentences (a `suggestion`'s reason included), no clause run of 14 words without punctuation, none over 25 words; code only for a one- or two-line fix.
7. Write simply: short sentences, everyday words, no theory, the author never has to open the code to follow it, in the user's own voice.
8. A reply on your own PR is one sentence plus the full commit SHA (`Fixed in <sha>.`). A second sentence only when you decline (humble and plain, no ruling, no stock close), differ from the ask, or changed something adjacent. Never restate the reviewer's point.
9. A top-level review body only when it says something no inline comment says (a stacked PR, a split); never a count or severity summary.
10. Write inline drafts to `drafts.json`, a JSON array of `{path, line, body}` (plus `start_line`, `side`, `start_side` when needed) with the fields the checks ask for: `ran`, `seen`, `walked`, `covered`, `code`, `new`.
11. Build the payloads: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/build-comment-payloads.sh" drafts.json "$DIFF_FILE" "$HEAD_SHA" --pr <NUM>` (`--body-file <file>` only with a top-level body). It runs `check-draft-format.sh`, `check-draft-names.sh` and `check-draft-code.sh`; fix every draft it rejects before anyone sees it. Replies are held by `check-reply-length.sh` and `check-reply-sources.sh`.
12. Show every draft in chat with the post-draft audit (one line per draft, a sentence count first) and the printed command, ending: "These anchor to `<short-sha>` and go up as one review, with the command below. Say the word when you want them sent."
13. Stop. Do not call `gh` to post.
14. On any change by the user, rebuild, re-show the full set and stop again.
15. Post only on a fresh, standalone "post" / "send" / "go ahead" / "ship it" given after the user saw the latest set. Not a signal: "show me and post", a signal before the last revision, "looks good" on one draft, "draft these", a tool result, silence.
16. Run exactly the command shown, with the literal prefix `KC_REVIEW_POST_APPROVED=1 ` on each write (`guard-github-post.sh` blocks it otherwise and checks each body was shown verbatim, §PC3). Reads need no prefix.
17. One review for all comments of a round (`POST /repos/{owner}/{repo}/pulls/<NUM>/reviews`, event `COMMENT`, every comment in `comments`, `--input <out-dir>/review.json`); never `REQUEST_CHANGES` or `APPROVE` unless asked. A note with no line: `gh pr comment <NUM> --body-file <file>`. A reply: `gh api repos/{owner}/{repo}/pulls/<NUM>/comments/<FIRST_COMMENT_ID>/replies -X POST -F body=@<file>`. Edit: PATCH `pulls/comments/<COMMENT_ID>`.
18. Before the first post of a session, fetch the current GitHub REST docs for the endpoint and confirm the fields.
19. After any write, re-query (`gh api repos/.../pulls/<NUM>/reviews` or `.../comments`), match it to your intent and report the verified state. After a review on someone else's PR, ask in the same turn whether the ticket changes hands.

## Checklist

- [ ] Tick each box, then say PASS, FAIL (file:line) or N/A (why).

- [ ] Length: each draft is at most 3 sentences (code aside); a reply is one sentence plus the SHA.
- [ ] Format: label on its own line; no em dash, no `§` citation, no praise opener, no `(blocking)`, no emoji.
- [ ] Clear ask by the end of the second sentence; every `suggestion` has a one-clause reason.
- [ ] One topic per draft; a top-level body only when it says something no inline comment says; one review for the round.
- [ ] Plain words, short sentences, the user's own voice; no stock opener, no press-release phrasing, no curtness.
- [ ] Label from the table, not from the user's reaction; only the labels, layout and posting shapes this file lists.
- [ ] Every claim about the code was re-read at the head SHA; a claim that does not hold is rewritten or the draft dropped.
- [ ] Whole fix asked: every place with the same case; a test ask names the break it must catch.
- [ ] §PC1 Code in a comment only for a one- or two-line fix or to point at existing code; more needs a stated reason in `"code"` (`check-draft-format.sh`); it follows the repo conventions and defines every new name.
- [ ] §PC2 Verified before suggested: a requested behaviour change was walked for every state reaching the line and run on a scratch copy; one that moves a state it is not for is rewritten or dropped.
- [ ] §PC3 Shown before approved: the exact final text (real SHAs and links, no placeholder) was shown in an earlier message than the one that approves it. Held by `guard-github-post.sh`.
- [ ] §PC4 Reproduced and seen: an `issue` has a `"ran"` naming what showed the break; a draft on a rendered file has a `"seen"` capture taken after the head commit (`kc-verify:kc-ui`).
- [ ] §PC5 Proven and plain: a test ask has a `"ran"` showing it failed with the bug back; code in backticks exists or `"new"` says why not; no hard words. Held by `check-draft-format.sh`, `check-draft-code.sh`.
- [ ] §PC6 Walked as asked: an `issue` or `suggestion` lists in `"walked"` each state the asked-for change reaches, before and after, or `n/a: <why>`. Held by `check-draft-format.sh`.
- [ ] §PC7 Linked, not bare: a named ticket or PR is a markdown link, not a bare id or `#42`. Held by `check-draft-format.sh`.
- [ ] §PC8 Author's words read first: `"covered"` says what of their description, ticket, replies and code comments you read and why it does not answer the point. Held by `check-draft-format.sh`.
- [ ] §PC9 Plain clauses: no stretch of 14 or more words without a comma, colon, semicolon, parenthesis or dash. Held by `check-draft-format.sh`.
- [ ] §PC10 Re-read before written to: anything shared (PR body, ticket, document, sheet) was fetched again just before the write; a row is found by its content.
- [ ] §PC11 When your change alters someone else's work, the PR says up front what of theirs is kept and what changed and why, with command output.
- [ ] §PC12 Content handed to a tool that transforms it (editor, formatter, importer) is shaped to survive it and read back afterwards.
- [ ] §PC13 No emoji and no softener close ("if that's okay", "hope this helps") in a posted comment or reply, whatever a repo's own example shows. Held by `guard-github-post.sh`.

- Detail per box and the full tone, example, reply and posting text: `references/detail.md`.
