# <Directory Name>

<!--
  CONTEXT.md skeleton. Copy into the target directory and fill in.
  Length: 200-400 words. One page max.
  See .agents/rules/documentation-system.md for the full rules.
-->

## What this is

<One plain sentence, no jargon. What this directory is, in terms a new
contributor would understand on day one.>

## Why it exists as its own module

<2-3 sentences. The boundary rationale — why is this its own directory
rather than folded into a sibling? What does it protect, hide, or
isolate?>

## Components

<List immediate subdirectories, ordered by importance, marked
**central** vs supporting, one sentence each.>

- **`<subdir-1>/`** — central. <One sentence on what it owns.>
- **`<subdir-2>/`** — central. <One sentence.>
- `<subdir-3>/` — supporting. <One sentence.>

## How it's used

<1-2 most important callers, with paths. Not an exhaustive list —
just the load-bearing ones a reader needs to know about.>

- `<path/to/caller-1>` — <how it consumes this module>.
- `<path/to/caller-2>` — <how it consumes this module>.

## What it is NOT

<Optional but high-value. Common misconceptions, things this module is
mistaken for, scope boundaries.>

- Not <a thing people assume>.
- Not <another thing>.

## Stability

<One line.> Stable. / Active redesign. / Legacy.
