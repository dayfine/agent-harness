---
harness: reusable
---

# Worktree Isolation Integrity

## The problem

When a subagent is dispatched with `isolation: "worktree"`, its worktree is
**not** a clean checkout of `main@origin`. The isolated worktree inherits a
snapshot of the parent worktree's working copy at dispatch time — including any
uncommitted edits and any in-flight commits from concurrent agents on other
branches.

Consequences observed in practice:

1. **File leaks.** `jj new main@origin` can leave stray modifications in the
   working copy that originated in a sibling agent's branch, which then get
   auto-snapshotted into your commit.
2. **Ancestry leaks.** If your `@` is a descendant of another agent's
   in-flight commits at the time you create your branch, the PR diff against
   `main` will include those commits too — even if your single commit only
   touches the files you intended.

Both happened on 2026-04-16 while concurrent feat-weinstein and
harness-maintainer agents were running.

## The rule

Before committing, verify your working copy contains only the files your task
requires. Before pushing, verify the branch ancestry lands on `main@origin` and
not on a sibling agent's stack.

**Pre-commit checks:**

```bash
jj diff --stat   # expect only files listed in your task's "Files to touch"
```

If stray files appear, scrub them before staging your real changes:

```bash
jj restore <stray-path> --from main@origin
```

**Pre-push checks:**

```bash
# What commits are in your branch but not in main@origin?
jj log -r '::<your-bookmark> & ~::main@origin' --no-graph -T 'description.first_line() ++ "\n"'
```

You should see **only your own commits**. If you see commits from other agents
(e.g., `feat(stops):`, `feat(strategy):`), your branch is stacked on top of
their work. Rebase onto `main@origin`:

```bash
jj rebase -r <your-change-id> -d main@origin --ignore-immutable
jj git push -b <your-bookmark>   # force-update if remote diverges
```

**Post-push verification (when task allows network access):**

```bash
gh pr view <PR#> --json files --jq '.files[].path'
```

The file list must match your "Files to touch". If it doesn't, rebase and
force-push — do not hand off a contaminated PR for review.

## When to apply

- Every subagent dispatched with `isolation: "worktree"` while another agent is
  known to be running in the same repo.
- Any session where the dispatcher's pre-flight prompt calls out workspace
  contamination risk explicitly.
- Any time `jj diff --stat` surprises you at dispatch time.

## What this rule does NOT cover

- Shared-worktree dispatch (non-isolated) — that's a different hazard class
  (`@` collisions between parent and child). Use `isolation: "worktree"` plus
  this rule for most concurrent work.
- Git-mode dispatch inside `$TRADING_IN_CONTAINER` (GHA) — CI runners start
  from a fresh checkout, so contamination doesn't occur there.
