---
harness: reusable
---

# Memory consolidation ("dreaming") — curate the store on a cadence that tracks its churn

Agents write memories one at a time, in the moment, and almost never revisit them. Over months the
store fills with near-duplicates, entries whose file, flag or PR no longer exists, and lessons that
were learned again under a different name. Two costs follow:

- **The index has a hard cap.** Claude Code loads the per-project index (`MEMORY.md`) into every
  session and silently drops what is past its size limit (about 24 KB). The entries that fall off are
  the newest ones.
- **Wrong memories are worse than none.** A memory that names a function that was since renamed sends
  the next agent to the wrong place, with the authority of "we already knew this".

The fix is not a bigger or smarter store. Plain files in git hold the content well. What is missing is
a periodic pass that curates them.

## The pass

Run with the `memory-dream` skill (`.claude/skills/memory-dream/SKILL.md`). One agent, one store:

1. **Merge.** Memories that state the same fact or lesson become one file. Its body keeps every
   distinct detail and the latest date. Links (`[[name]]`) to the removed names are repointed.
2. **Verify.** Every memory that names a file, symbol, flag, script, issue or PR is checked against
   the repo's current default branch. Each one is still true, updated, or retired.
3. **Retire.** A memory that is superseded, wrong or about finished one-off work moves to
   `<memory dir>/.archive/<date>/`. Nothing is deleted outright, so a bad call can be undone.
4. **Promote.** A lesson that recurs (three or more memories, or one cited across several
   sessions) becomes a rule file or a skill in the repo. Its memories are then retired with a pointer to
   it. Rules and skills are reviewed and versioned; memories are not.
5. **Trim the index.** One line per memory, at most ~150 characters, grouped by topic, under 80 % of
   the cap.

The pass ends with a report: counts merged / updated / retired / promoted, the index size before and
after, and every retirement with its one-line reason. **The pass never runs unreviewed on a store
it has not consolidated before.** The first pass on a store produces the report and a proposed diff
only, and a human approves it. Later passes may apply changes directly but still write the report.

Then `sh dev/lib/memory-dream-due.sh stamp`.

## Cadence — configurable, and adaptive by default

`dev/lib/memory-dream-due.sh check` decides whether a pass is due. Exit 0 means due, 10 means not.
It is cheap and offline, so a SessionStart hook, a weekly review or a cron routine can call it and
run the pass only when it says so.

A pass is due when the store was never consolidated, or when:

| condition | meaning |
|---|---|
| days since the last pass ≥ `DREAM_MAX_DAYS` | ceiling: even a quiet store gets checked for staleness |
| days ≥ `DREAM_MIN_DAYS` and changed files ≥ `DREAM_CHURN` | a fast-moving store consolidates sooner |
| days ≥ `DREAM_MIN_DAYS` and index ≥ `DREAM_INDEX_PCT` % of its cap | the index is about to lose entries |

A store's churn rate sets its effective cadence. A repo in heavy development crosses the churn
threshold within days and consolidates near the floor. A stabilised repo rarely crosses it and
consolidates at the ceiling. Staleness still accrues there, because the code under its memories keeps
moving even when the memories do not.

Set the values per repo in `dev/memory-dream.conf` (`KEY=VALUE` lines). The environment overrides the
file. Starting points:

| repo | `DREAM_MIN_DAYS` | `DREAM_MAX_DAYS` | `DREAM_CHURN` |
|---|---|---|---|
| fast-moving (many sessions a day, memories added daily) | 2 | 7 | 10 |
| default | 3 | 14 | 15 |
| stabilised (occasional sessions) | 7 | 30 | 20 |

Tune from the reports. If passes keep finding little to merge or retire, raise the floor or the
churn threshold. If they keep finding a lot, lower them.

## Sharing across repos — three tiers, loaded on demand

| tier | holds | lives in | loaded |
|---|---|---|---|
| **local** | everything, including session-specific feedback | the per-project memory store | the index, every session |
| **repo** | durable project facts worth versioning | a committed snapshot in the repo | on demand, by path |
| **shared** | lessons true in any repo: VCS and PR tooling, agent stalls, waits, sandbox quirks | this harness repo (rules, skills), or a private notes repo | on demand: a skill trigger or a rule table entry |

- **Promote; do not copy.** A lesson moves to the shared tier as a rule or skill during a pass, and the
  per-repo memories that taught it are retired with a pointer. Two copies drift.
- **The shared tier is never loaded whole.** Every session already pays a fixed preamble of rules,
  memory index and tool schemas. A shared layer that loads in every repo multiplies that cost. Put it
  behind skill descriptions or a "when X, read Y" table, the way a repo's on-demand rules work.
- **Domain facts stay local.** A strategy finding or a map coordinate is true in one repo only.
- **Mind the visibility.** This harness repo may be public. Keep anything private (account names,
  internal URLs, personal paths, data terms) in a private notes repo, not here.

## Related

- `agent-liveness.md`: many feedback memories are stall lessons; promote them there.
- `standing-rules.md`: a promoted rule that every agent must carry goes into the standing block.
