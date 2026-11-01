---
harness: template
---

# Standing rules — the block every dispatched agent definition carries

Rules that hold for every dispatch of an agent go in its definition, once,
under the heading below. The dispatcher's brief then carries only the task
(`agent-liveness.md` §Keep briefs short). `bin/agent-standing-rules-check.sh`
fails when a listed agent's definition loses the block or one of its
required phrases; `.agents/standing-rules.conf` lists which agents need which
roles.

Copy the block for the agent's role into its definition and replace the
`<TODO>` placeholders with your project's commands. **Keep the phrases the
checker looks for verbatim** (listed under each block).

## Role `all` — every dispatched agent

```markdown
## Standing rules — the dispatch brief does not repeat these

<!-- standing-rules: pinned by bin/agent-standing-rules-check.sh -->
The dispatcher's brief carries only the task: the issue or PR and its tip SHA, the scope or the delta
since the last review, the prior review's location, and the rework iteration. The rules below apply
without being restated.

- **No waiting.** Run every build and test in the foreground with `timeout: 600000`, split into scoped
  calls (`<TODO: format command>`, `<TODO: build command>`, `<TODO: test command for one directory>`)
  when one call could run longer. Read the exit code from a file (`…; echo $? > rc`), never through a
  pipe. Never background a long command and end the turn waiting for it: nothing wakes a subagent.
  If a command does run in the background, keep polling its output in bounded loops until it finishes.
- **Bounded loops.** Every wait loop has an iteration cap and checks that the producing process is
  still alive.
- **Your own checkout.** Work only in your own worktree: `<TODO: checkout command>`. Run builds against
  that tree, never the dispatcher's.
```

Required phrases: `## Standing rules — the dispatch brief does not repeat these`,
`<!-- standing-rules`, `Never background a long command and end the turn`,
`Every wait loop has an iteration cap`.

## Role `build` — agents that commit (feat, code-health, harness-maintainer)

Append to the `all` block:

```markdown
- **Commit early, finish in one turn.** Commit and push as soon as the scoped checks pass; the full
  build and test run comes after the push. Then, in the foreground and without ending the turn:
  verify → commit → push → open the PR → confirm the PR's file list. Never end with an unpushed commit.
  If the push or PR step fails twice, report the branch, the commit id and "PR NOT opened".
- **Your stage ends at the PR.** Never wait for CI or any other event after pushing: report the PR
  number and tip SHA and stop; the dispatcher waits for CI (`.agents/rules/long-chain-ownership.md`).
```

Required phrases: `Never end with an unpushed commit.`, `the dispatcher waits for CI`.

## Role `review` — agents that post a verdict (qc-*)

Append to the `all` block:

```markdown
- **Review delivery.** Line 1 is `Reviewed SHA: <full sha>`; `## Verdict` sits on its own line,
  followed by `APPROVED` or `NEEDS_REWORK`. **Post first, then verify:** re-read the PR's reviews and
  confirm yours is there. A verdict that exists only in your return text did not happen.
```

Required phrase: `Post first, then verify`.
