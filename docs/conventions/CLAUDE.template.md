# <Project Name> — Agent Instructions

<!--
  CLAUDE.md skeleton for a CONSUMING PROJECT.
  Lives at the project repo root (and optionally at subsystem roots).
  Loaded on every agent interaction — keep lean. Architecture, domain,
  and per-directory specifics belong in CONTEXT.md / DEEP_DIVE.md, not
  here. See .agents/rules/documentation-system.md for the full rules.
-->

## What this repo is

<One paragraph. What the project does, who runs it, what it produces.>

## Build / test / lint

Exact commands an agent can copy-paste. No prose.

```bash
# build
<build_cmd>

# test (full suite)
<test_cmd>

# test (single target)
<single_test_cmd>

# lint
<lint_cmd>

# format
<format_cmd>
```

If commands run inside a container or env wrapper, document it once
here:

```bash
<env_wrapper_cmd> -- <build_cmd>
```

## Build system specifics

<Query patterns, target naming conventions, anything an agent needs
to navigate the build graph. Examples: `bazel query`, workspace
layout, monorepo path conventions, generated-code locations. Keep to
bullets.>

- <Pattern 1>.
- <Pattern 2>.

## Style conventions

<Forbidden patterns, required patterns, naming rules. Bullets, not
prose.>

- <Convention 1>.
- <Forbidden pattern 1>.

## Documentation system

This project uses the three-tier doc protocol from the agent-harness.
Full rules in `.agents/rules/documentation-system.md`; skeletons in
`docs/conventions/`; generation prompt at
`docs/conventions/deep_dive_prompt.md`.

When working in a directory:

1. Read `CONTEXT.md` files from repo root down to the target directory.
2. If `DEEP_DIVE.md` exists in the target, read it before reading
   source.
3. If `DEEP_DIVE.md` disagrees with source, trust source and flag
   drift.
4. Never edit `DEEP_DIVE.md` directly — it is regenerated.
5. Edit `CONTEXT.md` to shape future regenerations.

## Agent harness

This repo is wired to the `agent-harness` orchestration framework.
Auto-discover your role by reading the relevant playbook in
`.agents/agents/` (e.g. `lead-orchestrator.md`,
`feat-<your-track>.md`, `qc-structural.md`).
