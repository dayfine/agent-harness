---
name: codex-dispatch
description: Hand work to OpenAI Codex (CLI or cloud) and use it as an advisory PR reviewer, safely. Use when the user asks to dispatch, brief or hand a task to Codex, to get a Codex review of a PR, to check Codex quota, or to set up Codex in a repo.
harness: reusable
---

# Codex dispatch

Codex is a second agent with a different failure profile. Use it for two
things: **bounded tasks** (it opens a PR) and **advisory reviews** (it reads a
PR and the script posts its report). In both, your project's own gates decide
the merge. Codex never merges, approves or stands in for a gate.

The scripts below live in `dev/lib/` of a repo that synced the harness. In a
repo that has not, run them from the harness checkout instead
(`sh ${AGENT_HARNESS:-~/Projects/agent-harness}/dev/lib/codex-review.sh <PR>`): they
resolve the repo from the current directory, not from where they live.

## Before any hand-off: check the quota

```sh
sh dev/lib/codex-quota.sh --guard 70 --weekly-guard 80   # exit 3 = over a guard: skip, say so
```

Codex CLI and cloud share one account limit, and a cloud task cannot read it,
so pace from the dispatcher. It reads the newest `~/.codex/sessions` rollout
(probing with one tiny `codex exec` if stale) and logs each reading to
`~/.codex-quota/log.csv`.

## Advisory review

```sh
sh dev/lib/codex-review.sh <PR>             # sample → checkout → codex exec → validate → post
sh dev/lib/codex-review.sh <PR> --force     # skip the sampling draw and daily cap
sh dev/lib/codex-review.sh <PR> --no-post   # validate only; prints the report path
sh dev/lib/codex-review.sh <PR> --dry-run   # print the prompt
```

- Run it when the PR passes its first gate, so the review lands before merge.
- Codex runs read-only in a detached worktree at the head SHA; the script
  validates the report (`Reviewed SHA:` line 1, `## Codex review —` heading,
  one `## Verdict` → `APPROVED | NEEDS_REWORK`, no gate heading) and posts it
  as a COMMENTED review pinned to that SHA.
- Budget: a deterministic 25 % sample per (PR, SHA) and 3 live runs a day by
  default; labels `review/codex-requested` (skip sampling) and
  `review/codex-required` (skip both) override. Token usage lands in
  `dev/_tmp/codex/reviews-<date>.log`.
- `CODEX_REVIEW=off` turns it into a no-op.
- Read a Codex NEEDS_REWORK as findings to check, not as a block. If you want
  Codex promoted to a gate one day, log each reviewed PR's Codex verdict next to
  your gate verdicts at merge and require a high agreement rate first.

## Handing Codex a task

Codex's replies are not evidence. It has reported "done" for edits that never
happened. So:

1. **Pick bounded, verifiable work**: docs, a script with a test, one module
   with TDD. Not long runs, not judgment calls. A wrong answer must be cheap and
   obvious.
2. **Write a numbered, exact brief**: the files to touch, the commands to run,
   the expected output. Restate the evidence checklist every time:
   - `git diff --stat` lists only the brief's files;
   - the formatter shows no diff;
   - paste the test command's result line and the pushed SHA;
   - write `CANNOT: <why>` instead of claiming something it could not do.
3. **Route it.** Locally: `codex exec` in a worktree. Cloud:
   `codex cloud exec --env <environment id>`, then poll its status. On GitHub,
   an `@codex` comment on the issue also starts a cloud task.
4. **Judge by the push, never the reply**: the PR's SHA, its file list and CI.
5. **Rework**: comment on the PR with a link to the review, "rework iteration
   N of 2", and ask for a second commit, not an amend.
6. **Stop rule**: after 2 corrective rounds, finish it yourself (rebuild from
   the default branch with only the brief's files, credit Codex, open a
   superseding PR). Don't start a third round.
7. **Cap open PRs per external agent** (3 is a good default) so reviews keep up.

Pitfalls:
- **Never write "@codex" in a PR body, commit message or doc.** The GitHub
  connector reacts to the mention and starts a task.
- Bots often cannot edit PR bodies; fix issue links (`Closes #N`) yourself.
- Ownership by label (`agent/codex`), since every agent may share one GitHub
  account. Codex labels its own PRs `author/codex`.

## Setting up a repo (project layer)

1. **`AGENTS.md`** (Codex reads it): how to claim an issue (`agent/codex` +
   `ready-for-agent`, a claim comment), branch `codex/<issue>-<slug>`, push only
   with `sh dev/lib/codex-push.sh`, PR body starts `Closes #<issue>`, rework is a
   second commit, `BLOCKED:` comment instead of widening scope, never merge or
   approve, and the advisory review format above.
2. **`.codex/rules/<project>.rules`**: copy
   `docs/conventions/codex.rules.template` (forbids `gh pr merge`, prompts on
   reviews / `gh api` / raw `git push`, allows `codex-push.sh`), then add
   project lines.
3. **`dev/codex-review.env`** (optional): `CODEX_REVIEW_DOCS_GLOBS`,
   `CODEX_REVIEW_PROMPT_ADDENDUM`, `CODEX_REVIEW_READER` (your status script's
   verdict reader, so a report is posted only if your tooling reads the same
   verdict), `CODEX_REVIEW_GATE_HEADINGS`. See the script header.
4. **`.codex/review-prompt.md`** (optional): what to look for in this repo
   (rule files, test conventions). Appended to the review prompt.
5. Gitignore `dev/_tmp/`.
