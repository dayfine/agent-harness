# Implementation plans

Prototype folder for agent-produced implementation plans. Populated by the
built-in `Plan` subagent when the lead-orchestrator triggers plan-first
dispatch for a high-risk task (see `.agents/agents/lead-orchestrator.md`
Step 3.5).

## File naming

One file per plan:

```
dev/plans/<feature-or-item>-<YYYY-MM-DD>.md
```

Examples:
- `backtest/stop-buffer-2026-04-15.md` — plan for the first stop-buffer tuning experiment
- `feature/drawdown-breaker-2026-04-20.md` — plan for the drawdown circuit breaker

## Shape

Each plan should contain:

1. **Context** — what is the task, what does the current code look like, what is the spec
2. **Approach** — the chosen design, with rejected alternatives named and briefly justified
3. **Files to change** — explicit list with per-file notes
4. **Risks / unknowns** — what could go wrong, what we aren't sure about
5. **Acceptance criteria** — what "done" looks like; must align with the feat-agent's checklist
6. **Out of scope** — explicit non-goals so the agent doesn't drift

Plans are short (aim ~100–300 lines). They are reviewed by a human before
the feat-agent executes.

## Lifecycle

```
[orchestrator detects high-risk task]
  → [Plan subagent] writes dev/plans/<name>-<date>.md
  → [human reviews] approves / requests changes / rejects
  → [feat-agent] reads approved plan as part of its pre-flight context
    (prompt includes "Approved plan: dev/plans/<name>-<date>.md")
  → [feat-agent] implements
  → [QC] reviews implementation against the plan's acceptance criteria
```

Archive decisions (architectural choices that survive the feature) belong
in `dev/decisions.md` after the plan is executed — do not rely on plan
files for long-term documentation. Plans are scaffolding, not history.

## When plan-first fires

See `.agents/agents/lead-orchestrator.md` §Step 3.5 for the trigger logic.
Current triggers:

1. **First deliverable from a new agent** — the agent's `dev/status/<track>.md`
   §Completed is empty
2. **Cross-cutting change** — agent's own status file says `plan_required: true`
   for the item, or the change is expected to touch > 5 files
3. **Previously-failed work** — item has a history of closed / rejected PR
   attempts in the status file
4. **Experiment design** — any item where the success criteria is empirical
   (e.g. a backtest experiment) rather than a unit-testable spec
