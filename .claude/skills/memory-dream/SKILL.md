---
name: memory-dream
description: Consolidate the agent memory store ("dreaming") - merge duplicates, verify claims against the current default branch, archive stale entries, promote recurring lessons into rules or skills, and trim the index under its cap. Use when memory-dream-due.sh says a pass is due, when the memory index nears its size limit, or when the user asks to consolidate, clean up, dedupe or "dream" over memories.
harness: reusable
---

# Memory consolidation pass

The rule, cadence and tiers are in `.agents/rules/memory-consolidation.md`. Read it first.

## 1. Is it due?

```sh
sh dev/lib/memory-dream-due.sh check    # exit 0 due, 10 not due; prints days, churn, index fill
```

Not due and the user did not ask: stop and report the line. Asked anyway: go on.

The memory directory is the `MEMORY_DIR` the script uses (by default
`~/.claude/projects/<repo path with / and . as ->/memory`).

## 2. First pass on a store, or a later one?

No `.last-dream` file in the store means first pass. **Propose only.** Write the plan to
`<memory dir>/.archive/<today>/PLAN.md`, then stop for approval. Later passes apply directly.

## 3. The pass

Work in this order; each step shrinks the next.

1. **Inventory.** List every memory with its `name`, `type` and description. Group by topic.
2. **Merge** same-fact memories into one file, keep every distinct detail and the latest date, and
   repoint `[[links]]` to the merged name.
3. **Verify** each memory that names a file, symbol, flag, script, issue or PR against the current
   default branch (`git grep`, `ls`, `gh issue view`). Update it, or retire it if the claim no longer
   holds. A memory you cannot check stays, marked unverified in the report.
4. **Retire** by moving, never deleting: `mv <file> <memory dir>/.archive/<today>/`. Remove its index
   line.
5. **Promote** a lesson that 3+ memories teach into a rule file or skill in the repo, on a branch, as a
   normal PR. Retire the memories with a one-line pointer memory to the new file. For a lesson true in
   any repo, propose it for the shared harness instead (see the rule's tiers). Never put private
   details in a public repo.
6. **Rewrite the index**: one line per remaining memory, ≤ ~150 characters, grouped by topic, under
   80 % of the cap.

## 4. Report and stamp

Write `<memory dir>/.archive/<today>/REPORT.md` with:
- counts merged / updated / retired / promoted / unverified;
- index bytes before and after;
- each retirement and its one-line reason.

Show the user the counts and any promotion PRs. Then run:

```sh
sh dev/lib/memory-dream-due.sh stamp
```

## Don'ts

- Do not run two passes on one store at once, or a pass while another session writes memories.
- Do not rewrite the meaning of a feedback memory the user gave. Merge its wording, keep its rule.
- Do not promote on one occurrence. A single lesson stays a memory until it recurs.
