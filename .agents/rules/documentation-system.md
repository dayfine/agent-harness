---
harness: reusable
---

# Documentation System

A three-tier doc protocol for agent-driven repos: `CLAUDE.md` (operational
instructions, repo root), `CONTEXT.md` (per-directory orientation,
human-authored), `DEEP_DIVE.md` (per-directory exhaustive reference,
model-generated and regenerable).

The tiers serve different audiences and have different update cadences.
Mixing them — e.g. putting architecture in `CLAUDE.md`, or hand-editing
`DEEP_DIVE.md` — breaks the system.

## CLAUDE.md (repo root, sometimes subsystem root)

**Purpose:** operational instructions for agents working in this repo.

**Contains:**
- How to run tests, builds, linters (exact commands).
- Build system specifics and query patterns.
- Style conventions and forbidden patterns.
- Where docs live and how to use them (the doc protocol below).
- Pointer to the deep-dive generation prompt at
  `docs/conventions/deep_dive_prompt.md`.

**Excludes:** architecture, domain knowledge, per-directory specifics,
glossary. Those belong in `CONTEXT.md` / `DEEP_DIVE.md` / `docs/cross_cutting/`.

**Stays lean.** Read on every interaction; competes with the task for
attention.

**Doc protocol section (required in `CLAUDE.md`):**

```
When working in a directory:
1. Read CONTEXT.md files from repo root down to the target directory.
2. If DEEP_DIVE.md exists in the target, read it before reading source.
3. If DEEP_DIVE.md disagrees with source, trust source and flag drift.
4. Never edit DEEP_DIVE.md directly — it is regenerated.
5. Edit CONTEXT.md to shape future regenerations.
```

## CONTEXT.md (per directory, human-authored, stable)

**Purpose:** orientation. The "why" the model can't infer.

**Length:** 200–400 words. One page max.

**Required sections:**

- **What this is** — one plain sentence, no jargon.
- **Why it exists as its own module** — 2–3 sentences. The boundary
  rationale.
- **Components** — list subdirectories, ordered by importance, marked
  **central** vs supporting, one sentence each.
- **How it's used** — 1–2 most important callers with paths.
- **What it is NOT** — common misconceptions. Optional but high-value.
- **Stability** — one line. "Stable." / "Active redesign." / "Legacy."

**Placement rule:** a directory gets a `CONTEXT.md` only when there's
something to say that isn't covered by its parent's `CONTEXT.md`. Don't
preemptively populate.

**Updated by humans in code review.** Changes rarely.

Skeleton: `docs/conventions/CONTEXT.template.md`.

## DEEP_DIVE.md (per directory, model-generated, regenerable)

**Purpose:** exhaustive cited reference.

**Generation:** see `docs/conventions/deep_dive_prompt.md` for the full
prompt (Steps 0–6, output structure, hard rules, self-check).

**Output structure:**

1. Purpose (uses `CONTEXT.md` framing verbatim).
2. Mental Model (written LAST, after inventory).
3. Public Surface (bullets with `path:line` and callers).
4. Inbound Dependencies (grouped by top-level package).
5. Outbound Dependencies (first-party / third-party / stdlib).
6. **Subdirectory Deep Dives** — one subsection per subdir, length
   proportional to subdir size.
7. Top-Level Glue (brief, last).
8. Data Flow (one numbered path with citations).
9. Invariants (cited from comments / asserts only).
10. Sharp Edges (cited from TODO / HACK / FIXME only).
11. Tests (location, command, coverage gaps).
12. Context Drift (contradictions between `CONTEXT.md` and code).
13. Generation Metadata (date, VCS SHA, files-read count).

**Hard rules:**

- Every factual claim outside Purpose / Mental Model needs a `path:line`
  citation.
- No invention. Missing info → "Not found in scanned scope."
- No filler words: robust, scalable, efficient, clean, modern, elegant.
- No "etc.", "and so on", "among others" — complete the list or state the
  count.
- `<!-- HUMAN: -->` blocks must be preserved across regenerations.
- No file trees, no exhaustive API listings.

Skeleton: `docs/conventions/DEEP_DIVE.template.md`.

## Update protocol

- **`CLAUDE.md` and `CONTEXT.md`:** human edits in code review. Rare.
- **`DEEP_DIVE.md`:** regenerated automatically when (a) >20% of files
  changed, (b) build config changed, (c) `CONTEXT.md` changed, (d) >30 days
  elapsed, or (e) manually triggered. PR opens automatically; human
  reviews diff and merges.
- **Never** hand-edit `DEEP_DIVE.md` outside `<!-- HUMAN: -->` blocks.
  Hand edits get destroyed by regeneration, which makes regeneration stop
  happening, which makes the doc rot forever.
- **Staleness signal:** Generation Metadata records the VCS SHA. CI
  compares to HEAD and warns if the directory has changed substantially
  since.
- **Drift signal:** accumulating Context Drift entries mean either the
  code or `CONTEXT.md` is wrong. Treat as debt.

## Coverage policy

- Not every directory needs a `DEEP_DIVE.md`. Pick by: high agent
  traffic, high onboarding cost, high blast radius, complex non-obvious
  domain logic.
- Many directories need only a `CONTEXT.md`. Many need nothing.
- Cross-directory concerns (multi-package flows, shared invariants) go
  in `docs/cross_cutting/`, not in any single deep dive.
- Maintain `docs/index.md` auto-generated from `CONTEXT.md` files for
  discoverability.
