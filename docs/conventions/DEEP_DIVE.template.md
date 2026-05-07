# <Directory Name> — Deep Dive

<!--
  DEEP_DIVE.md skeleton. This file is MODEL-GENERATED and REGENERABLE.
  Do not hand-edit outside <!-- HUMAN: --> blocks. See
  .agents/rules/documentation-system.md and
  docs/conventions/deep_dive_prompt.md.
-->

## Purpose

<Verbatim from CONTEXT.md "What this is" + "Why it exists as its own
module".>

## Mental Model

<Written LAST, after inventory. The compressed shape of the module —
what's in your head after reading it cold. 3-6 sentences.>

## Public Surface

- `<path/to/file>:<line>` — `<symbol>` — <one-line role>. Callers:
  `<caller-1>`, `<caller-2>`.
- `<path/to/file>:<line>` — `<symbol>` — <one-line role>. Callers:
  Not found in scanned scope.

## Inbound Dependencies

Grouped by top-level package.

- **`<top-level-pkg-a>`** — `<path>:<line>`, `<path>:<line>`.
- **`<top-level-pkg-b>`** — `<path>:<line>`.

## Outbound Dependencies

- **First-party:** `<pkg>`, `<pkg>`.
- **Third-party:** `<pkg>` (`<version-or-constraint>`), `<pkg>`.
- **Stdlib:** `<module>`, `<module>`.

## Subdirectory Deep Dives

### `<subdir-1>/` — central

<Length proportional to subdir size from the Step 1 census. Cite
`path:line` for every factual claim.>

### `<subdir-2>/` — central

<...>

### `<subdir-3>/` — supporting

<...>

## Top-Level Glue

<Brief. Shorter than any single subdirectory subsection. Re-exports,
registration, entry points.>

## Data Flow

One numbered path through the module, with citations.

1. <Caller> calls `<symbol>` (`<path>:<line>`).
2. `<symbol>` dispatches to `<symbol-2>` (`<path>:<line>`).
3. <...>

## Invariants

Cited from comments or asserts only.

- <Invariant statement> — `<path>:<line>`.

## Sharp Edges

Cited from TODO / HACK / FIXME only.

- `<path>:<line>` — <quoted comment, brief>.

## Tests

- **Location:** `<path>`.
- **Command:** `<exact command to run>`.
- **Coverage gaps:** <symbols / paths not under test, or "Not found in
  scanned scope.">.

## Context Drift

<Contradictions between CONTEXT.md and the code. Empty if clean.>

- `CONTEXT.md` says <X>, but `<path>:<line>` shows <Y>.

<!-- HUMAN: pinned notes go here. Preserved across regenerations. -->

## Generation Metadata

- **Date:** `<YYYY-MM-DD>`
- **VCS SHA:** `<sha>`
- **Files read:** `<count>`
