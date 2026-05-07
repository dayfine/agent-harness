# DEEP_DIVE.md Generation Prompt

The exact prompt body the model uses to (re)generate a directory's
`DEEP_DIVE.md`. Edit per language / build system in your consuming
project. The meta-rules (purpose, placement, update cadence) live in
`.agents/rules/documentation-system.md`.

---

You are generating `DEEP_DIVE.md` for a target directory. Follow Steps
0–6 in order. Do not skip steps. Do not invent. Cite every factual
claim.

## Step 0 — Read context

Read `CONTEXT.md` from repo root down to the target directory. If the
target's `CONTEXT.md` is missing, **STOP and report**. Do not proceed
without it — orientation is a prerequisite, not optional.

## Step 1 — Subdirectory census FIRST

List immediate subdirectories with file count and total line count,
sorted descending by line count. This list is your priority order.

Output format:

```
| Subdir | Files | Lines |
|--------|-------|-------|
| <name> | <n>   | <n>   |
```

## Step 2 — Top-level file census SECOND

Classify each top-level file as one of:

- re-export
- registration
- glue
- shared types
- entry point
- substantive (rare — double-check before assigning this)

## Step 3 — Allocate budget proportionally

- Top 3 subdirs: ~60% of reading.
- Remaining subdirs: ~30%.
- Top-level files: ~10%.
- Read at least 2 files from every subdir over 200 lines.
- Output the allocation as a table BEFORE writing prose.

## Step 4 — Read build files before source

Read `BUILD` / `package.json` / `Cargo.toml` / `pyproject.toml` /
equivalent first. They give the authoritative dependency contract;
source imports can lie or be transitively shadowed.

## Step 5 — Reverse-dependency search

Use the build system's reverse-dep query if available (e.g. `bazel
query 'rdeps(//..., //target/...)'`), else `grep` for imports of the
target package across the repo. Record up to 20 distinct callers,
grouped by top-level package.

## Step 6 — Symbol census

`grep` for all public symbols defined in the target. Every symbol must
either appear in the doc or be marked "internal helper." Coverage gap
is a generation failure.

---

## Output structure

Write the doc in this exact order:

1. **Purpose** — uses `CONTEXT.md` framing verbatim.
2. **Mental Model** — written LAST, after the inventory is complete.
3. **Public Surface** — bullets with `path:line` and callers.
4. **Inbound Dependencies** — grouped by top-level package.
5. **Outbound Dependencies** — first-party / third-party / stdlib.
6. **Subdirectory Deep Dives** — one subsection per subdir, length
   proportional to subdir size from Step 1.
7. **Top-Level Glue** — brief, last.
8. **Data Flow** — one numbered path with citations.
9. **Invariants** — cited from comments / asserts only.
10. **Sharp Edges** — cited from TODO / HACK / FIXME only.
11. **Tests** — location, command, coverage gaps.
12. **Context Drift** — contradictions between `CONTEXT.md` and code.
13. **Generation Metadata** — date, VCS SHA, files-read count.

## Hard rules

- Every factual claim outside Purpose / Mental Model needs a
  `path:line` citation.
- No invention. Missing info → "Not found in scanned scope."
- No filler words: robust, scalable, efficient, clean, modern,
  elegant.
- No "etc.", "and so on", "among others" — complete the list or state
  the count.
- `<!-- HUMAN: -->` blocks must be preserved verbatim across
  regenerations.
- No file trees. No exhaustive API listings.

## Self-check before finishing

- **File coverage:** 100% of source files mentioned by path.
- **Symbol coverage:** ≥80% of public symbols accounted for.
- **Subdirectory balance:** longest subsection / shortest non-trivial
  subsection < 10×.
- **Top-Level Glue** section shorter than any single subdirectory
  subsection.
- **Citation density:** 9/10 random factual sentences have `path:line`.

If any check fails, fix before writing the file.
