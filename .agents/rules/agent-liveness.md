---
harness: reusable
---

# Agent liveness — dispatched agents finish, or fail loudly

A dispatched agent that stops making progress rarely says so. From the
dispatcher's side, a stalled agent, a slow build and a finished agent whose
work was lost look the same until someone checks. This file lists the five
ways agents stall, the rule that prevents each, and how the dispatcher
recovers without losing work.

The rules an agent must follow live **in its own definition** (see
`standing-rules.md`), not in each dispatch brief. A brief that restates them
costs context on every dispatch and drifts from the definition over time.

## The five stall classes

### 1. Waiting for an event that never comes

The agent starts a long command in the background, says "I'll wait for the
completion event", and ends its turn. **Nothing wakes a subagent.** The turn
is over; the work sits unverified and unpushed until a human notices.

Observed three times in one week in the source project, about 30 minutes of
latency each, and once the same agent did it twice in a row.

**Rule:**

- Run builds and tests in the **foreground** with an explicit tool timeout
  (for Claude Code's Bash tool, `timeout: 600000`, the 10-minute maximum).
- When one call could run longer, split it into scoped calls (format, build,
  one test directory at a time).
- Read exit codes from a file (`cmd; echo $? > rc`), never through a pipe.
  `cmd | tail; echo $?` reports `tail`'s exit code.
- If something does run in the background, keep polling its output file in
  bounded loops (class 2) until it finishes. Never end the turn waiting.

### 2. A poll loop that never ends

`until COND; do sleep 30; done` spins forever when `COND` is malformed (a
wrong path, a glob that never matches, quoting inside a process
substitution) or when the producing process died before writing what the
loop watches.

**Rule:** every wait loop has an iteration cap **and** checks that the
producer is still alive.

```sh
i=0
until grep -q 'DONE' "$log"; do
  i=$((i + 1)); [ "$i" -le 120 ] || { echo "timeout after $i polls" >&2; break; }
  kill -0 "$pid" 2>/dev/null || { echo "producer exited" >&2; break; }
  sleep 30
done
```

To stop a runaway loop that the harness started, kill its `sleep` child,
never the harness process.

### 3. Stalls that look like a slow command

Two causes give the same symptom, a session that executes nothing for hours,
and their fixes do not overlap:

| cause | observed | fix |
|---|---|---|
| a shell command waiting on a permission prompt | 44 h | allowlist the routine commands (VCS, `gh`, container exec, read-only shell tools, the project's own scripts) in settings |
| an expired login | 11 h | only the user can fix it (`/login`); nothing inside the session can |

Allowlisting does not make stalls impossible. When output goes quiet,
compare the clock with the last command's start before assuming it is slow.

### 4. The agent dies, or its work is reaped

- **Uncommitted work is deleted.** Claude Code removes an `isolation:
  "worktree"` worktree that has **no commits** when the agent finishes, and
  every uncommitted edit goes with it. There is no prompt and no copy.
- **Usage limits stop agents mid-task.** Subagents share the account's
  limits. A dead agent's notification repeats the limit message as its
  result; messaging it again only repeats the message.

**Rules:**

- Commit and push **as soon as the scoped checks pass** (format, the touched
  module's build, its tests). The full build and test run comes after the
  push. A failure there becomes a follow-up commit, not lost work.
- **Finish protocol**, in one turn, in the foreground: verify → commit →
  push → open the PR → confirm the PR's file list matches what you changed.
  Never end a turn with an unpushed commit.
- **Salvage** after a death: in the agent's worktree, commit what is there as
  `WIP: <topic> — state UNVERIFIED` and push it to `wip/<topic>`, never to
  the PR branch. Comment the location on the PR. The next session verifies
  in full before moving it onto the real branch.

### 5. Contention makes everything slow

Agents that share a build container, a build lock or a CPU slow each other
down until each one looks stalled.

**Rules:**

- Cap concurrent build-running agents. Size the cap from measured container
  memory, not a guess. The source project uses 3 on a 7.75 GB container and
  0 while a long batch job holds it.
- Give each agent its own checkout (see `worktree-isolation.md`), so agents
  do not share a working copy or a build directory.
- Stopping a task that ran `docker exec` (or any remote shell) does not stop
  the process on the other side. Check for orphans when everything is slow.

## Dispatcher-side recovery

Before re-dispatching a stalled agent, check whether its work already exists:

```sh
git -C <agent-worktree> log --oneline origin/main..HEAD   # commits made?
git -C <agent-worktree> status --short                    # uncommitted edits?
gh pr list --head <branch> --state open                   # PR opened?
```

- **Commits exist but no PR:** verify, push and open the PR yourself. This
  is faster than a re-dispatch and cannot lose the work.
- **Uncommitted edits only:** salvage to `wip/<topic>` (class 4) before
  anything else touches the worktree.
- **Nothing exists:** re-dispatch, and name the stall class in the brief so
  the agent avoids it.

**Rework cap.** When a review returns NEEDS_REWORK, re-dispatch at most
twice. After the second rework round, stop, leave the PR in draft and flag
it for a human. A third round is a scope question, not an agent question.

## Keep briefs short

A dispatch brief carries only the task: the issue or PR, the tip SHA, the
scope or the delta since the last review, the prior review's location and
the rework iteration. Target about 0.5 KB. Everything that is true for every
dispatch of that agent belongs in its definition's standing-rules block,
which `bin/agent-standing-rules-check.sh` keeps from going missing.

## What a reviewer can check

- **L1.** Every dispatched agent definition carries the standing-rules
  block (`bin/agent-standing-rules-check.sh`).
- **L2.** No script or brief added in the diff contains an uncapped
  `until … done` or `while true` wait loop.
- **L3.** A dispatch brief does not restate the standing rules.
