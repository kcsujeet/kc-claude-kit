---
name: unrelated-request
description: A question with no code or review request in it does not trigger the review-code skill.
tags: [negative]
plugins: ["../..", "../../../conventions"]
allowed_tools: [Read, Glob, Grep, Bash, Agent, Skill]
max_turns: 60
timeout_seconds: 300
---

In two sentences, what does `git rebase` do?
