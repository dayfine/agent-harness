# agent-harness

Template / scaffolding for agentic coding harnesses built on
[Claude Code](https://docs.claude.com/en/docs/claude-code/overview).

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
.claude/
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
.github/workflows/
  orchestrator.yml             — daily orchestrator dispatch via claude-code-action
  image.yml                    — build & publish CI + devcontainer images
  deps-update.yml              — weekly dependency-snapshot freshness check
  health-deep-weekly.yml       — weekly deep health-scanner dispatch
dev/
  agent-feature-workflow.md    — shared workflow doc every feat-agent reads at session start
  lib/run-in-env.sh            — shell wrapper that execs commands inside the devcontainer
  plans/README.md              — conventions for `dev/plans/<feature>-<YYYY-MM-DD>.md` files
  status/_index.md             — skeleton index of tracked work
```

## Three-layer model

Every `.claude/agents/*.md` and `.claude/rules/*.md` carries a
`harness:` frontmatter field. There are three values:

| Layer        | Meaning                                                          | Lives in            |
|--------------|------------------------------------------------------------------|---------------------|
| `reusable`   | Ship as-is. Generic across any project.                          | this repo           |
| `template`   | Skeleton each consuming project copies and fills in.             | this repo (with `<TODO>` placeholders) |
| `project`    | Project-specific. Domain rules, tool lists, lint names, etc.     | the consuming repo  |

The QC agents are split along the **methodology / authority seam**:

- The `.md` under `.claude/agents/qc-{structural,behavioral}.md` describes
  the generic review protocol (when it runs, how it formats findings,
  how it pass/fails). It is `harness: reusable`.
- The companion `.claude/rules/qc-{structural,behavioral}-authority.md`
  in the consuming project lists the project's specific lint names,
  architecture constraints, domain references, test framework, etc.
  Those files are `harness: project` and live only in your repo.

## How to consume this harness

There is no published CLI yet (planned: `bin/agent-harness init` — see
"Planned tooling" below). For now, manual steps:

1. Clone this repo's contents into your new project's root.
2. Delete the harness-only `LICENSE` and `README.md` if you want your
   own; keep the `.claude/`, `.github/workflows/`, and `dev/` trees.
3. Replace `<TODO>` placeholders in:
   - `.claude/agents/feat-agent-template.md` — copy to
     `.claude/agents/feat-<your-feature>.md` per active track and fill in.
   - `.claude/agents/lead-orchestrator.md` Configuration block — set
     repo URL, container image, track names, feat-agent names, branch
     conventions.
   - `.github/workflows/orchestrator.yml` — secret names, image refs,
     branch patterns, cron slots.
   - `dev/status/_index.md` — add one row per active track.
4. Write your project-specific authority files for QC:
   - `.claude/rules/qc-structural-authority.md` — your lints, build
     gates, architecture constraints. `harness: project`.
   - `.claude/rules/qc-behavioral-authority.md` — your domain
     references, test conventions. `harness: project`.
5. Write any `feat-<name>.md` agents your project needs (one per track).
   These are `harness: project`.
6. Adjust `dev/agent-feature-workflow.md` for your toolchain. The
   shipped version assumes OCaml + Dune + jj + Docker; edit to match
   your stack.

## Updating from upstream

There is no automated sync. If this harness gets a generic improvement,
manually cherry-pick the file change into your project (or vice versa).
Drift is expected and acceptable for 1–2 consuming projects.

If multiple projects share this harness and drift becomes painful, a
selective-sync CLI (`agent-harness sync --reusable-only`) is the next
step — see "Planned tooling".

## Planned tooling

Not yet implemented; tracked in the source repo's plan
`dev/plans/harness-template-extraction-2026-04-26.md`:

- `bin/agent-harness init <target-dir>` — clones this template into a
  target dir, drops any leaked `harness: project` files, prompts for
  `<TODO>` placeholder values.
- `bin/agent-harness sync --reusable-only` — diffs each
  `harness: reusable` file in the target against this upstream and
  presents per-file y/n/skip merges.
- `bin/agent-harness check` — verifies every `.claude/agents/*.md` and
  `.claude/rules/*.md` carries a `harness:` frontmatter line.

## Source

Extracted from [`dayfine/trading`](https://github.com/dayfine/trading)
on 2026-04-26 per the bootstrap plan
`dev/plans/harness-template-extraction-2026-04-26.md` §Phase 2.

The `harness:` frontmatter on each source file was the strip filter —
`reusable` and `template` files came along; `project` files stayed
behind. See that plan for the full history of why the harness was split
this way and what's still TODO (CLI, settings.json template, license
decision for consuming projects, second-project bootstrap test).

## License

MIT. See `LICENSE`.
