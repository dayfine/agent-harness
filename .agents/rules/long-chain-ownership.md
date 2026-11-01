---
harness: reusable
---

# Long-chain ownership — scripts wait, agents decide

A chain of work that runs for hours (build → test → PR → CI → review → fix →
merge, or a series of batch jobs) is cheap to run and expensive to *watch*.
This file says who owns which part, so the model is only in the loop when a
decision is due.

Pairs with `agent-liveness.md` (why agents stall) and `standing-rules.md`
(what every agent definition carries).

## Why watching is expensive

Every time an agent wakes it re-reads its whole context. In the source
project, measured over a month of sessions:

- the fixed floor (rules, memory index, tool definitions) was about 112k
  tokens per call before any work;
- 85 % of spend was in calls above 150k context;
- re-reading the main context was about 55 % of all spend.

So an agent that owns an 8-hour chain and checks in every 10 minutes makes
about 50 wakes at 150–300k tokens each, around 10M input tokens, most of
them spent re-reading its own history while nothing changed. Cached reads are
discounted, but the volume still dominates. Cost scales with **wakes ×
context size**, and both grow when one agent owns the whole chain.

## The split

| who | owns | never does |
|---|---|---|
| **a script** (`dev/lib/chain-runner.sh`, `wait-pr-checks.sh`) | the order of steps, retries, timeouts, resume, all waiting | decide anything |
| **the dispatcher** (main session) | starting the script as a tracked background task, reading `handoff.md` when it exits, dispatching the next stage | poll on a short timer, read raw logs |
| **a stage agent** (fresh per stage) | one stage: a fix, a review, a reading of results | wait on anything outside its own turn |

```
chain-runner.sh run chain.txt state/      (harness-tracked background task)
      │ exits: 0 done · 10 decision · 1 failed
      ▼
dispatcher reads state/handoff.md         (one small file, not the logs)
      │
      ├─ done      → report
      ├─ decision  → dispatch a fresh stage agent with handoff.md as its brief
      └─ failed    → fix or flag; `chain-runner.sh reset state/ <step>`; re-run
```

## Waiting for CI (and anything else outside the turn)

**A subagent never waits for CI.** Nothing wakes a subagent after its turn
ends, so "I'll wait for the checks" ends the agent with the work in limbo
(`agent-liveness.md` class 1). Instead:

1. **The agent finishes its stage and stops:** commit, push, open or update
   the PR, and report the PR number and tip SHA. That is its whole job.
2. **The dispatcher waits, cheaply:** it runs
   `sh dev/lib/wait-pr-checks.sh <PR>` as a harness-tracked background task.
   That is bash polling `gh` once a minute, at zero tokens; the harness
   re-invokes the dispatcher when the script exits. Exit 0 means green, 10 a
   failed check, 1 still pending at the cap.
3. **The next stage is a new agent:** green → dispatch the reviewer; red →
   dispatch a fixer with the failing check's name and log excerpt. Neither
   inherits the previous agent's context.

Inside a chain, the same waiter is just a step:

```
push      git push -u origin feat/x
ci        sh dev/lib/wait-pr-checks.sh 123
merge     gh pr merge 123 --squash
```

A failed check exits 10, so the runner stops with status `decision` and the
dispatcher brings in an agent only then.

**What an agent may run in the background:** only work it will collect
before its own turn ends: a long build it polls in bounded loops, parallel
test shards it waits on. If the agent cannot collect it within the turn, it
belongs to the dispatcher or the runner.

**What the dispatcher should not do:** short timed wake-ups to "check on"
something a tracked task will report anyway. Use one long fallback heartbeat
(20–30 min) only to catch a hung script.

## Stage agents get a handoff, not a history

Each stage agent is dispatched fresh with:

- the `handoff.md` the runner wrote (status, step, attempts, a log tail);
- the task for this stage, about 0.5 KB;
- paths to artifacts, not their contents.

It returns a short result; anything durable goes in a file the next stage
can read. The context of each stage stays flat instead of growing for the
length of the chain, and a crash loses one stage, not the chain.

## Budgets the automation enforces

A chain needs caps that do not depend on the model noticing:

- **Attempts per step:** `CHAIN_MAX_ATTEMPTS` (default 2). Attempts count
  across runs, so a failed step stays failed until someone `reset`s it.
- **Time per step:** `CHAIN_STEP_TIMEOUT`; the runner kills the step's whole
  process group, not only its shell.
- **Polls per wait:** `WAIT_MAX_POLLS` in `wait-pr-checks.sh`.
- **Rework rounds:** at most 2 per PR, then flag a human
  (`agent-liveness.md`).
- **Stage agent turns:** pass a turn or token cap on the dispatch if your
  harness supports one; otherwise keep stages small enough that one turn
  finishes them.

When a cap is hit, the runner writes `handoff.md` and exits. It never
continues on hope.

## Model by step, not by chain

The chain's mechanical parts are not model work at all (they are script
steps). Of the stages that are:

| stage | model / effort |
|---|---|
| mechanical fix with a clear failing check | small model |
| code review gate | mid model; top model for the behavioral gate |
| a reading of results that sets the next direction | top model, high effort |

## Hygiene

- `handoff.md` quotes the tail of the stopping step's log. Keep secrets and
  licensed data out of step output, or run with `CHAIN_TAIL_LINES=0`.
- Keep the state directory outside any directory a VCS operation can rewrite
  (a `jj`/`git` checkout switch must not reach it).
- Compact the dispatcher's context before starting a long wait, not after.

## Measuring it

Record tokens per completed step before and after moving a chain to this
pattern (per dispatch, plus the dispatcher's wakes). The pattern pays when
tokens per step fall; if a chain has few waits and short stages, one agent
may still be cheaper.

## What a reviewer can check

- **C1.** No agent definition or brief tells a subagent to wait for CI or
  another external event after its stage.
- **C2.** Every wait in a chain is a bounded script step or a tracked
  background task, never a model poll on a timer.
- **C3.** A chain's state directory and handoff live outside the checkout.
