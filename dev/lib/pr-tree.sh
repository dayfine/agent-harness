#!/bin/sh
# harness: reusable
# pr-tree.sh — print the stacked-PR tree and the review/send queue.
#
# Works for a fork-based workflow: PRs are prepared as stacked PRs on a
# fork (each based on its parent's branch) and sent upstream one or two at a
# time, because upstream PRs must target the default branch.
#
#   sh dev/lib/pr-tree.sh [--config FILE] [--fork OWNER/REPO]
#                         [--upstream OWNER/REPO] [--author LOGIN]
#                         [--limit N] [--json]
#
# Settings come from flags, else from the config file (default
# dev/pr-tree.json, project layer), else from the current repo:
#
#   {
#     "fork": "me/project",          // where stacked PRs live
#     "upstream": "org/project",     // where PRs are sent; omit if none
#     "author": "me",                // upstream PRs by this login
#     "limit": 2,                    // max open upstream PRs at once
#     "order": [51, 37, 38, 53],     // optional send order (fork PR numbers)
#     "exclude": [39, 42]            // optional: never queue these (still in the tree)
#   }
#
# Output:
#   Tree   — every open PR, nested under the PR whose branch it is based on.
#            A fork PR and the upstream PR made from the same branch share a
#            line ("#16 ⇄ U#1628").
#   Queue  — 1. Review now: open upstream PRs, with review state.
#            2. Send next: fork PRs not yet upstream whose parents have all
#               merged (based on the default branch), in config order, as
#               many as there are free upstream slots; then what comes after.
#
# Needs gh (authenticated) and python3. Read-only: it never edits a PR.

set -eu

exec python3 - "$@" <<'PY'
import argparse, json, os, subprocess, sys

ap = argparse.ArgumentParser(prog="pr-tree.sh")
ap.add_argument("--config", default="dev/pr-tree.json")
ap.add_argument("--fork")
ap.add_argument("--upstream")
ap.add_argument("--author")
ap.add_argument("--limit", type=int)
ap.add_argument("--json", action="store_true")
a = ap.parse_args()

cfg = {}
if os.path.exists(a.config):
    with open(a.config) as f:
        cfg = json.load(f)

def gh(*args):
    return subprocess.check_output(["gh", *args], text=True)

fork = a.fork or cfg.get("fork") or gh("repo", "view", "--json", "nameWithOwner", "--jq", ".nameWithOwner").strip()
upstream = a.upstream or cfg.get("upstream")
author = a.author or cfg.get("author") or fork.split("/")[0]
limit = a.limit if a.limit is not None else cfg.get("limit", 2)
order = cfg.get("order", [])
exclude = set(cfg.get("exclude", []))

FIELDS = "number,title,headRefName,baseRefName,isDraft,reviewDecision,latestReviews,url,headRepositoryOwner"

def prs(repo, extra=()):
    return json.loads(gh("pr", "list", "--repo", repo, "--state", "open", "--limit", "200",
                         "--json", FIELDS, *extra))

def default_branch(repo):
    return gh("repo", "view", repo, "--json", "defaultBranchRef", "--jq", ".defaultBranchRef.name").strip()

fork_prs = prs(fork)
fork_default = default_branch(fork)
up_prs, up_default = [], None
if upstream:
    up_prs = [p for p in prs(upstream, ("--author", author))
              if (p.get("headRepositoryOwner") or {}).get("login") == fork.split("/")[0]]
    up_default = default_branch(upstream)

# One node per head branch: the fork PR and/or the upstream PR made from it.
nodes = {}
for p in fork_prs:
    nodes.setdefault(p["headRefName"], {})["fork"] = p
for p in up_prs:
    nodes.setdefault(p["headRefName"], {})["up"] = p

def base_of(n):
    # The fork PR carries the stacking; an upstream-only PR sits on main.
    return (n.get("fork") or n["up"])["baseRefName"]

children = {}
roots = []
for head, n in nodes.items():
    base = base_of(n)
    if base in nodes and base != head:
        children.setdefault(base, []).append(head)
    else:
        roots.append(head)

def num(head):
    n = nodes[head]
    return (n.get("fork") or n["up"])["number"]

def review_state(p):
    # reviewDecision is empty when the repo requires no review, so fall back
    # to each reviewer's latest review.
    decision = p.get("reviewDecision") or ""
    latest = {r.get("state") for r in p.get("latestReviews") or []}
    if decision == "CHANGES_REQUESTED" or "CHANGES_REQUESTED" in latest:
        return "changes requested"
    if decision == "APPROVED" or "APPROVED" in latest:
        return "approved"
    if latest:
        return "reviewed"
    return "awaiting review"

def label(head):
    n = nodes[head]
    parts = []
    if "fork" in n:
        parts.append(f"#{n['fork']['number']}")
    if "up" in n:
        u = n["up"]
        state = review_state(u)
        parts.append(f"U#{u['number']} ({state})")
    title = (n.get("fork") or n["up"])["title"]
    base = base_of(n)
    note = ""
    if base not in nodes and base not in (fork_default, up_default):
        note = f"  ⚠ base {base} has no open PR (merged or deleted?)"
    return f"{' ⇄ '.join(parts)}  {title}{note}"

def walk(head, prefix, last, out):
    out.append(f"{prefix}{'└── ' if last else '├── '}{label(head)}")
    kids = sorted(children.get(head, []), key=num)
    for i, k in enumerate(kids):
        walk(k, prefix + ("    " if last else "│   "), i == len(kids) - 1, out)

tree = []
by_base = {}
for r in roots:
    by_base.setdefault(base_of(nodes[r]), []).append(r)
for base in sorted(by_base):
    tree.append(base)
    rs = sorted(by_base[base], key=num)
    for i, r in enumerate(rs):
        walk(r, "", i == len(rs) - 1, tree)

# Queue.
review_now = sorted((h for h, n in nodes.items() if "up" in n), key=num)
ready = [h for h, n in nodes.items()
         if "up" not in n and "fork" in n and n["fork"]["baseRefName"] == fork_default
         and n["fork"]["number"] not in exclude]
rank = {n: i for i, n in enumerate(order)}
ready.sort(key=lambda h: (rank.get(nodes[h]["fork"]["number"], len(rank)), num(h)))
slots = max(0, limit - len(review_now)) if upstream else len(ready)

if a.json:
    print(json.dumps({"tree": tree, "review_now": [label(h) for h in review_now],
                      "send_next": [label(h) for h in ready[:slots]],
                      "after_that": [label(h) for h in ready[slots:]],
                      "free_slots": slots}, ensure_ascii=False, indent=2))
    sys.exit(0)

print(f"## PR tree ({fork}" + (f" → {upstream}" if upstream else "") + ")\n")
print("```")
print("\n".join(tree) if tree else "(no open PRs)")
print("```\n")
print("## Queue\n")
if upstream:
    print(f"**Review now** (open upstream: {len(review_now)} of {limit}):")
    for h in review_now:
        print(f"- {label(h)}")
    if not review_now:
        print("- none")
    print()
print(f"**Send next** ({slots} free slot{'s' if slots != 1 else ''}):")
for h in ready[:slots]:
    print(f"- {label(h)}")
if not ready[:slots]:
    print("- none" + (" (no free slot)" if ready else " (no PR has all its parents merged)"))
if ready[slots:]:
    print("\n**After that** (parents merged, waiting for a slot):")
    for h in ready[slots:]:
        print(f"- {label(h)}")
PY
