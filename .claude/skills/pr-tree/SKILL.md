---
name: pr-tree
description: Print the stacked-PR tree (full picture) and the queue (what to review now and what to send upstream next). Use when the user asks for the PR tree, PR status, the queue, or what to send next.
harness: reusable
---

# PR tree and queue

Run the script and show its output as is:

```sh
sh dev/lib/pr-tree.sh                 # settings from dev/pr-tree.json
sh dev/lib/pr-tree.sh --config path/to/pr-tree.json
```

- **Tree:** every open PR, nested under the PR whose branch it is based on.
  A fork PR and the upstream PR opened from the same branch share one line
  (`#16 ⇄ U#1628 (approved)`). A `⚠` marks a PR whose base branch has no open
  PR (its parent merged or was deleted), so it needs a rebase.
- **Queue:**
  - *Review now*: open upstream PRs and their review state.
  - *Send next*: fork PRs not yet upstream whose parents have all merged,
    in the config's `order`, one per free upstream slot (`limit` minus open
    upstream PRs).
  - *After that*: the rest of the ready PRs, waiting for a slot.

The script only reads. After printing, add at most three lines: what changed
since the last tree you showed, which PR a pending merge unblocks, and
anything flagged with `⚠`. Don't open, edit or send PRs from this skill;
sending upstream is the user's call unless the project's rules say otherwise.

## Config (project layer)

`dev/pr-tree.json` in the consuming repo; every key is optional:

```json
{
  "fork": "me/project",
  "upstream": "org/project",
  "author": "me",
  "limit": 2,
  "order": [51, 37, 38],
  "exclude": [39]
}
```

Without `upstream`, every ready PR is listed under *Send next*. Without
`order`, ready PRs are listed by number. Needs `gh` (authenticated) and
`python3`.
