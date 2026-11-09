# kc-claude-kit

Sujeet's personal [Claude Code](https://code.claude.com/docs) toolkit. It works in any codebase and does three things:

1. **Teaches Claude how to write code** the way a careful engineer would (naming, structure, tests, and so on).
2. **Reviews code** against those same rules, yours or a teammate's.
3. **Checks the work** in the running app before calling it done.

Everything is a Claude Code plugin. Install the ones you want; nothing needs to be added to your project.

## Start here: the skills used every day

If you only try three things, try these. They are all in the `kc-gates` plugin.

| When | Type or say | What happens |
|---|---|---|
| Your PR is about to go to a reviewer | `/kc-gates:kc-ready-for-review` | One review and QA pass on your own PR. Claude fixes what it finds, proves each fix with a test, and gives you a short list of anything left for you to decide. The goal: your reviewer finds nothing the rules already say. |
| You are reviewing someone's PR (or want yours checked) | "review this PR" | `kc-code-review` reads the change against every rule and reports PASSED or FAILED with one line per finding. Nothing is posted anywhere. |
| You want those findings as PR comments | `/kc-gates:kc-post-review` | Drafts short, polite comments, shows them to you, and posts only after you say so. |

The rest of the kit supports these three: the rules they check against, and the QA steps they run.

## The plugins

| Plugin | What it is for | When you would use it |
|---|---|---|
| `kc-gates` | Code review. The three skills above. | Every PR. |
| `kc-conventions` | The coding rules, one skill per topic. They load on their own while Claude writes code, and `kc-gates` reviews against them. | Always on. Install it and forget it. |
| `kc-verify` | QA. Looks at the change in the running app, checks a person can use it, and tests a change end to end. | Any change a person sees. |
| `kc-instructions` | Audits a repo's Claude setup: what belongs in `CLAUDE.md`, a rule, a skill or a hook. | Once per repo, or when `CLAUDE.md` gets long. |
| `kc-usage-band` | A status row above the prompt: model, branch, context used, rate limits, cost. | Always on. Terminal only. |
| `kc-image-preview` | Shows thumbnails of images you paste into the prompt. | Always on. Terminal on macOS only. |
| `kc-autopilot` 🚧 | **Work in progress.** Takes an approved plan and turns it into pull requests on its own. | Not ready for everyday use. |

## How they fit together

```
                 kc-conventions
        (the rules: naming, tests, structure ...)
              |                        |
   loads while Claude writes     is what reviews check against
              |                        |
              v                        v
         your code  ───────────►   kc-gates
                                 kc-code-review      (review any change)
                                 kc-ready-for-review (review + QA your own PR)
                                 kc-post-review      (turn findings into PR comments)
                                       |
                              runs QA with
                                       v
                                   kc-verify
                              (UI, usability, end to end)
```

- **`kc-conventions` is the foundation.** The rules live there once. Claude follows them when writing, and `kc-gates` grades against the same text, so the two never disagree.
- **`kc-gates` needs `kc-conventions`**, and installs it for you.
- **`kc-ready-for-review` ties it together:** it runs `kc-code-review`, then the `kc-verify` QA skills, then your project's own hand-off checklist if it has one.
- **`kc-instructions`, `kc-usage-band` and `kc-image-preview` stand alone.** Use them or not; nothing else depends on them.
- **`kc-autopilot`** (work in progress) sits on top of `kc-gates` and `kc-conventions`.

## Every skill, in one line

Most skills start on their own when the topic comes up. You can also type any of them as `/plugin:skill`.

**`kc-gates`: review**

| Skill | What it does | Starts when |
|---|---|---|
| `kc-code-review` | Reviews a PR, branch or your working changes. One checker per topic, one PASSED or FAILED verdict. | You say "review this PR" or "review my changes". |
| `kc-ready-for-review` | The one review and QA pass on your own PR before a person sees it. | Work is about to go to review. Claude is reminded to run it. |
| `kc-post-review` | Drafts PR comments and replies, and posts them only on your say-so. | Claude is about to write any PR comment, or you type it. |

**`kc-verify`: QA**

| Skill | What it does | Starts when |
|---|---|---|
| `kc-ui` | Looks at the change rendered in a browser: every state, realistic data, different screen sizes. | "does this look right" |
| `kc-ux` | Checks a person can actually use it: the flow, the wording, what happens on a mistake. | "is this easy to use", "check the flow" |
| `kc-e2e` | Drives a change through every layer it touches, front to back. | "test this end to end" |

**`kc-conventions`: the rules**

| Skill | Covers |
|---|---|
| `kc-naming` | Names that say what a thing is for. |
| `kc-clarity` | Code that reads in one pass: simple conditions, useful comments, no magic numbers. |
| `kc-structure` | Where code lives and how files are shaped. |
| `kc-simplicity` | Reuse what exists, build only what is needed. |
| `kc-correctness` | Bugs: edge cases, wrong conditions, and other code that breaks when this code changes. |
| `kc-testing` | Tests that fail when the code is broken. |
| `kc-datetime` | Dates, times and time zones. |
| `kc-i18n` | Translations and locale files. |
| `kc-react` | React components, hooks, data fetching and forms. |
| `kc-rails` | Rails models, queries, migrations and specs. |
| `kc-type-safety` | Types that tell the truth. |
| `kc-error-handling` | Errors that are caught, reported and explained. |
| `kc-performance` | Queries and renders that stay fast. |
| `kc-dependencies` | Adding a library only when it earns its place. |
| `kc-init` | Copies the rules into a project so they load automatically. Run once per project. |

**`kc-instructions`**

| Skill | What it does | Starts when |
|---|---|---|
| `kc-audit` | Reviews a repo's Claude instructions and proposes a cleaner setup. | "audit my CLAUDE.md" |

**`kc-autopilot`** 🚧 work in progress

| Skill | What it does |
|---|---|
| `kc-init` | Sets a repo up for autopilot. Run once per repo, by typing it. |
| `kc-run` | Splits an approved plan into units and delivers each as a pull request. |

`kc-usage-band` and `kc-image-preview` have no skills. Once installed, they just show up above the prompt.

## Install

Add the marketplace, then install what you want. To get the everyday workflow, the first three lines are enough:

```
/plugin marketplace add kcsujeet/kc-claude-kit
/plugin install kc-gates@kc-claude-kit
/plugin install kc-verify@kc-claude-kit
/plugin install kc-instructions@kc-claude-kit
/plugin install kc-usage-band@kc-claude-kit
/plugin install kc-image-preview@kc-claude-kit
```

`kc-gates` brings `kc-conventions` with it. Then, once in each project where you want the coding rules to load on their own:

```
/kc-conventions:kc-init
```

`kc-autopilot` is a work in progress; install it only if you want to try it:

```
/plugin install kc-autopilot@kc-claude-kit
```

To keep the kit current, turn on auto-update for the marketplace: `/plugin`, the Marketplaces tab, `kc-claude-kit`, **Enable auto-update**. More in [Staying up to date](docs/reference.md#staying-up-to-date).

## Make it yours

The kit knows general rules, not your project. Three optional files in your repo teach it the rest. None is required.

| File | What it adds |
|---|---|
| `.claude/review-conventions.md` | Your project's own review rules. They win over the built-in ones. |
| `.claude/hand-off-checklist.md` | What to check before a PR goes to review: the description, the ticket, linked PRs. |
| `.claude/sensitive-paths.txt` | Paths to treat as risky, beyond the built-in list (payments, permissions, migrations). |

## More detail

Everything else is in [`docs/reference.md`](docs/reference.md):

- [Install details](docs/reference.md#install-details) and [staying up to date](docs/reference.md#staying-up-to-date)
- [The conventions](docs/reference.md#writing-code-the-conventions), topic by topic
- [How a review works](docs/reference.md#reviewing-code), and each gate
- [Posting review comments](docs/reference.md#posting-review-comments-to-github) and the safeguards around it
- [The pass before a PR goes to review](docs/reference.md#before-a-pr-goes-to-review)
- [Adding your repo's own rules](docs/reference.md#adding-your-repos-own-rules)
- [Using the skills in Gemini CLI or Antigravity](docs/reference.md#using-the-skills-in-gemini-cli-or-antigravity)
- [Script reference](docs/reference.md#script-reference)
- [Developing the kit](docs/reference.md#developing)
- [Autopilot](docs/reference.md#delivering-a-plan-with-autopilot-work-in-progress) (work in progress)

How the kit is built and why: [`docs/architecture.md`](docs/architecture.md).
