# agent-harness

Extracted from a production algorithmic trading system.

This repo provides the generic orchestration layer — a set of agent
definitions, rules, GitHub Actions workflows, and directory contracts —
that drive parallel feature development across multiple feat-agents,
with structural and behavioral QC gates, daily orchestrator runs, and
health/budget tracking.

It is not a runtime. It is a set of markdown files, YAML workflows, and
small POSIX shell helpers that Claude Code reads and executes against
your project.

## What's in here

```
.agents/
  agents/
    lead-orchestrator.md       — the daily driver; dispatches feat / QC / health agents
    harness-maintainer.md      — owns dev/ harness changes (status files, workflows, scripts)
    health-scanner.md          — light + deep code-health scans
    code-health.md             — applies fixes for findings the scanner produced
    qc-structural.md           — generic structural-review protocol (build, lints, architecture)
    qc-behavioral.md           — generic behavioral-review protocol (semantics, domain rules)
    feat-agent-template.md     — skeleton each project copies into its own feat-<name>.md
  rules/
    worktree-isolation.md      — invariants for isolation:worktree dispatches
    agent-liveness.md          — five ways dispatched agents stall, and the rule for each
    standing-rules.md          — the block every dispatched agent definition carries
    long-chain-ownership.md    — scripts wait, agents decide: runner, handoff, CI waits, budgets
  standing-rules.conf          — which agents must carry which standing-rules roles
.claude/skills/
  pr-tree/SKILL.md             — "print the PR tree and queue"; runs dev/lib/pr-tree.sh
  codex-dispatch/SKILL.md      — hand tasks to Codex, advisory Codex PR reviews, quota pacing
bin/
  agent-harness-check.sh       — every harness file carries a harness: layer tag
  agent-standing-rules-check.sh — every listed agent definition carries its standing rules
.github/workflows/
  orchestrator.yml             — daily orchestrator dispatch via claude-code-action
  health-deep-weekly.yml       — weekly deep health-scanner dispatch
dev/
  agent-feature-workflow.md    — shared workflow doc every feat-agent reads at session start
  lib/chain-runner.sh          — resumable step runner; exits on done / decision / failed, writes handoff.md
  lib/wait-pr-checks.sh        — bounded wait for a PR's checks; 0 green, 10 failed, 1 timeout
  lib/run-in-env.sh            — shell wrapper that execs commands inside the devcontainer
  lib/pr-tree.sh               — stacked-PR tree + review/send queue (config: dev/pr-tree.json)
  lib/codex-review.sh          — advisory Codex review of one PR, validated then posted (config: dev/codex-review.env)
  lib/codex-quota.sh           — Codex 5-hour / weekly usage, with --guard exits for pacing
  lib/codex-push.sh            — the only push Codex runs: current codex/* branch to origin
  plans/README.md              — conventions for `dev/plans/<feature>-<YYYY-MM-DD>.md` files
  status/_index.md             — skeleton index of tracked work
```

## Handing this to an agent

Paste the brief below to an agent working in the repo that should adopt the
harness. It is written to that agent.

> **Adopt agent-harness's agent-liveness and long-chain patterns in this repo.**
>
> Clone https://github.com/dayfine/agent-harness next to this repo
> (`git clone https://github.com/dayfine/agent-harness ../agent-harness`), then read, in order:
> `.agents/rules/agent-liveness.md` (five ways dispatched agents stall, the rule for each),
> `.agents/rules/long-chain-ownership.md` (scripts wait, agents decide), and
> `.agents/rules/standing-rules.md` (the block every dispatched agent definition carries).
>
> **The pattern.** Subagents never wait on anything outside their own turn, because nothing
> wakes a subagent once its turn ends. A stage agent commits, pushes, opens the PR, reports the
> PR number and tip SHA, and stops. Scripts own all waiting and sequencing:
> `dev/lib/chain-runner.sh` runs a resumable chain of steps (exit 0 done, 10 a step needs a
> decision, 1 a step failed; writes `handoff.md` each time) and `dev/lib/wait-pr-checks.sh`
> waits on CI with a cap on polls (0 passed, 10 a check failed, 1 at the cap). The dispatcher
> runs these as harness-tracked background tasks, reads only `handoff.md` when one exits, and
> starts a fresh agent with a short brief for each stage that needs a decision. Every wake
> re-reads the whole context, so one agent watching an hours-long chain mostly pays to re-read
> itself.
>
> **Install.** No harness yet: `sh ../agent-harness/bin/agent-harness init .`
> Existing harness: list first, copying nothing:
> `yes n | AGENT_HARNESS_UPSTREAM=../agent-harness sh ../agent-harness/bin/agent-harness sync`,
> then re-run without `yes n |` and answer per file. Sync offers updates to `harness: reusable`
> files and offers `harness: template` files only when missing. It keeps local frontmatter but
> replaces a reusable file's body: read each diff first if this repo edited those files.
>
> **Then:**
> 1. For each agent this repo dispatches, paste the standing-rules block for its role from
>    `standing-rules.md` into its definition. Fill in the `<TODO>` build, test and checkout
>    commands; keep the checked phrases word for word.
> 2. List those agents and roles in `.agents/standing-rules.conf` (`<agent> all build`, or
>    `<agent> all review` for a reviewer).
> 3. `sh bin/agent-standing-rules-check.sh` and `sh bin/agent-harness-check.sh` must pass; keep
>    both in CI (`.github/workflows/harness-check.yml` runs them).
> 4. Cut from dispatch briefs anything the standing rules now cover. A brief carries only the
>    task: issue or PR, tip SHA, scope, prior review, rework iteration (about 0.5 KB).
> 5. Move one real multi-step chain to `chain-runner.sh`, with `wait-pr-checks.sh` as its CI
>    step. Record tokens per completed step before and after.
>
> **While doing this:** don't wait for your PR's CI; report the PR and stop. Every wait loop
> you write has an iteration cap. Keep secrets and licensed data out of step output
> (`handoff.md` quotes the end of the stopping step's log; `CHAIN_TAIL_LINES=0` turns that
> off). One PR for the install and standing rules, a separate PR for the first chain
> migration. If something here doesn't fit this repo, open an issue on dayfine/agent-harness
> rather than changing your copy in place.

## Three-layer model

Every `.agents/agents/*.md` and `.agents/rules/*.md` carries a
`harness:` frontmatter field. There are three values:

| Layer        | Meaning                                                          | Lives in            |
|--------------|------------------------------------------------------------------|---------------------|
| `reusable`   | Ship as-is. Generic across any project.                          | this repo           |
| `template`   | Skeleton each consuming project copies and fills in.             | this repo (with `<TODO>` placeholders) |
| `project`    | Project-specific. Domain rules, tool lists, lint names, etc.     | the consuming repo  |

The QC agents are split along the **methodology / authority seam**:

- The `.md` under `.agents/agents/qc-{structural,behavioral}.md` describes
  the generic review protocol (when it runs, how it formats findings,
  how it pass/fails). It is `harness: reusable`.
- The companion `.agents/rules/qc-{structural,behavioral}-authority.md`
  in the consuming project lists the project's specific lint names,
  architecture constraints, domain references, test framework, etc.
  Those files are `harness: project` and live only in your repo.

## How to consume this harness

There is no published CLI yet (planned: `bin/agent-harness init` — see
"Planned tooling" below). For now, manual steps:

1. Clone this repo's contents into your new project's root.
2. Delete the harness-only `LICENSE` and `README.md` if you want your
   own; keep the `.agents/`, `.github/workflows/`, and `dev/` trees.
3. Replace `<TODO>` placeholders in:
   - `.agents/agents/feat-agent-template.md` — copy to
     `.agents/agents/feat-<your-feature>.md` per active track and fill in.
   - `.agents/agents/lead-orchestrator.md` Configuration block — set
     repo URL, container image, track names, feat-agent names, branch
     conventions.
   - `.github/workflows/orchestrator.yml` — secret names, image refs,
     branch patterns, cron slots.
   - `dev/status/_index.md` — add one row per active track.
4. Write your project-specific authority files for QC:
   - `.agents/rules/qc-structural-authority.md` — your lints, build
     gates, architecture constraints. `harness: project`.
   - `.agents/rules/qc-behavioral-authority.md` — your domain
     references, test conventions. `harness: project`.
5. Write any `feat-<name>.md` agents your project needs (one per track).
   These are `harness: project`.
6. Adjust `dev/agent-feature-workflow.md` for your toolchain. The
   shipped version is tool-agnostic with placeholders; edit to match
   your stack. (See `dev/agent-feature-workflow-example.md` for inspiration).

## Intake sources — single-dev vs public-user projects

The shipped harness assumes a **single-developer model**: the human
maintains `dev/status/<track>.md` files as the canonical source of
"what's being worked on." The orchestrator reads those files at the
start of every session, picks the highest-priority open item per
track, and dispatches `feat-*` agents accordingly.

Projects with **public users** have a second input stream — GitHub
Issues (or the equivalent: project board, milestones, external
ticket system). Issues are not in `dev/status/`; they arrive
asynchronously, at unpredictable cadence, and not every Issue is a
real track. Consuming the harness in such a project needs an
explicit **triage layer** between the Issue stream and the
orchestrator's status-driven loop.

Two ways to wire this in:

**Option A — Issues are the canonical source.** Every track in
`dev/status/` corresponds to one Issue (or epic). The orchestrator's
Step-2 read becomes "list open Issues with label `track`," and
`dev/status/` is regenerated from that or skipped entirely. The
single-dev model collapses to a special case.

**Option B — Issues feed `dev/status/` via triage.** A separate
`intake-triage` agent (template provided as `feat-agent-template.md`'s
sibling — copy it and customise) polls Issues, classifies each (bug
fix → `cleanup/<short>` branch via code-health; feature → new
`dev/status/<track>.md` file; question → close with response;
duplicate → close), and writes status entries the orchestrator then
picks up. The orchestrator's logic doesn't change.

For 1–10 issues/month, Option B with a once-a-day triage subagent is
simpler. For higher volume, Option A keeps the Issues board as the
single source of truth.

The harness ships **neither** by default. Add what your project needs:

```
.agents/agents/intake-triage.md     # harness: project — your triage rules
dev/intake/                         # optional dir for cached/processed Issue state
```

If you write a generic-enough intake-triage template that works for
many projects, contribute it back as a `harness: template` agent.

## Updating from upstream

Use `agent-harness sync` to pull in upstream improvements to
`harness: reusable` files. Run from your consuming project's root:

```bash
agent-harness sync
```

The tool clones the upstream repo at the pinned `AGENT_HARNESS_TAG`
(defaults to `main`), diffs each reusable file, and presents a
per-file `[y/N/skip]` prompt. Local frontmatter is always preserved;
only the body content is updated. It covers `.agents/`, `.agents/agents/`,
`.agents/rules/`, `.github/workflows/`, `dev/lib/` and `bin/` (the harness's own
`bin/test-*` excepted). `harness: template` files are offered only when
missing locally, never overwritten, since you fill them in.

```bash
# Pin to a specific release
AGENT_HARNESS_TAG=v0.1.0 agent-harness sync

# Use a local clone (no network required)
AGENT_HARNESS_UPSTREAM=../agent-harness agent-harness sync
```

## CLI tooling

All three subcommands are implemented and available in `v0.1.0`:

| Command | Description |
|---|---|
| `agent-harness init <target-dir>` | Bootstrap a new project from this template |
| `agent-harness sync` | Interactively pull `harness: reusable` updates and missing templates from upstream |
| `agent-harness check` | Verify every agent/rule/workflow/script carries a `harness:` tag |

## Source

Extracted from a production algorithmic trading system.
on 2026-04-26. The `harness:` frontmatter on each source file was the
strip filter — `reusable` and `template` files came along; `project`
files stayed behind.

## License

MIT. See `LICENSE`.
