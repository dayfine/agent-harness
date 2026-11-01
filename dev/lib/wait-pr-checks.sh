#!/bin/sh
# harness: reusable
# wait-pr-checks.sh — wait for a PR's checks, bounded, with no model in the loop.
#
# Meant to be run by the dispatcher as a harness-tracked background task, or as
# a chain-runner step, never by a subagent at the end of its turn (nothing
# wakes a subagent). See .agents/rules/long-chain-ownership.md §Waiting for CI.
#
# usage: sh dev/lib/wait-pr-checks.sh <PR> [-R owner/repo]
# env:   WAIT_INTERVAL seconds between polls (default 60)
#        WAIT_MAX_POLLS poll cap (default 60, i.e. an hour at the default)
#        GH (default gh) — the gh executable, for tests
# exit:  0 all checks passed
#        10 a check failed (a decision: fix, re-run or flag; chain-runner's
#           decision code)
#        1 still pending after WAIT_MAX_POLLS polls, or gh kept erroring
#        2 usage
set -eu

[ $# -ge 1 ] || { echo "usage: wait-pr-checks.sh <PR> [-R owner/repo]" >&2; exit 2; }
GH=${GH:-gh}
interval=${WAIT_INTERVAL:-60}
max=${WAIT_MAX_POLLS:-60}
errors=0

i=0
while [ "$i" -lt "$max" ]; do
  i=$((i + 1))
  set +e
  out=$("$GH" pr checks "$@" 2>&1)
  rc=$?
  set -e
  # gh pr checks: 0 all passed, 8 some pending, 1 a failure (or a gh error).
  case "$rc" in
    0) echo "checks passed (poll $i)"; exit 0 ;;
    8) : ;;
    *)
      if printf '%s\n' "$out" | grep -q -E '[[:space:]](fail|cancel)'; then
        printf '%s\n' "$out" | grep -E '[[:space:]](fail|cancel)'
        exit 10
      fi
      errors=$((errors + 1))
      [ "$errors" -lt 3 ] || { echo "gh failed 3 times: $out" >&2; exit 1; }
      ;;
  esac
  [ "$i" -ge "$max" ] || sleep "$interval"
done
echo "still pending after $max polls" >&2
exit 1
