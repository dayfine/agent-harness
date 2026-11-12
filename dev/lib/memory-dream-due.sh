#!/bin/sh
# harness: reusable
# memory-dream-due.sh -- decide whether a memory consolidation pass ("dreaming") is due.
#
# Usage:
#   memory-dream-due.sh check    print one status line; exit 0 if a pass is due, 10 if not
#   memory-dream-due.sh stamp    record that a pass finished today (run after the pass)
#
# The cadence adapts to how fast the memory store changes, between a floor and a ceiling:
#
#   due  when  never consolidated
#        or    days since the last pass >= DREAM_MAX_DAYS                 (ceiling)
#        or    days >= DREAM_MIN_DAYS and churn >= DREAM_CHURN            (fast-moving store)
#        or    days >= DREAM_MIN_DAYS and index >= DREAM_INDEX_PCT % of cap (index near its cap)
#
# churn = memory files (*.md other than the index) added or changed since the last pass.
# A fast-moving repo crosses DREAM_CHURN within days and consolidates near the floor; a
# stable one rarely does and consolidates at the ceiling. See
# .agents/rules/memory-consolidation.md for presets.
#
# Settings: environment, else dev/memory-dream.conf (KEY=VALUE lines, sourced), else defaults.
#   MEMORY_DIR             memory store (default: the Claude Code per-project store,
#                          ~/.claude/projects/<repo path, / and . as ->/memory)
#   MEMORY_INDEX           index file name inside MEMORY_DIR (default MEMORY.md)
#   DREAM_MIN_DAYS         floor between passes (default 3)
#   DREAM_MAX_DAYS         ceiling between passes (default 14)
#   DREAM_CHURN            changed files that make a pass due after the floor (default 15)
#   DREAM_INDEX_CAP_BYTES  size past which the loader truncates the index (default 24000)
#   DREAM_INDEX_PCT        index fill that makes a pass due after the floor (default 80)
#   DREAM_ROOT             repo root (default: two levels above this script)
#   DREAM_TODAY            YYYY-MM-DD to treat as today (tests)
#
# State: MEMORY_DIR/.last-dream holds the date of the last pass; its mtime is the churn cutoff.
# Exit codes: 0 due, 10 not due, 1 usage or missing store.

REPO_ROOT=${DREAM_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}
# Optional per-repo config; a variable already set in the environment wins over it.
if [ -f "$REPO_ROOT/dev/memory-dream.conf" ]; then
  while IFS='=' read -r k v; do
    case "$k" in MEMORY_*|DREAM_*) ;; *) continue ;; esac
    eval "[ -n \"\${$k+x}\" ] || $k=\$v"
  done < "$REPO_ROOT/dev/memory-dream.conf"
fi

MEMORY_DIR=${MEMORY_DIR:-$HOME/.claude/projects/$(printf '%s' "$REPO_ROOT" | sed 's#[/.]#-#g')/memory}
MEMORY_INDEX=${MEMORY_INDEX:-MEMORY.md}
DREAM_MIN_DAYS=${DREAM_MIN_DAYS:-3}
DREAM_MAX_DAYS=${DREAM_MAX_DAYS:-14}
DREAM_CHURN=${DREAM_CHURN:-15}
DREAM_INDEX_CAP_BYTES=${DREAM_INDEX_CAP_BYTES:-24000}
DREAM_INDEX_PCT=${DREAM_INDEX_PCT:-80}
TODAY=${DREAM_TODAY:-$(date +%Y-%m-%d)}
STAMP="$MEMORY_DIR/.last-dream"

# Whole days from date $1 to date $2 (both YYYY-MM-DD); empty if either fails to parse.
# Parsed in UTC: in local time a span across a DST change is an hour off whole days and floors short.
_days_between() {
  a=$(TZ=UTC date -j -f %Y-%m-%d "$1" +%s 2>/dev/null || TZ=UTC date -d "$1" +%s 2>/dev/null) || return 0
  b=$(TZ=UTC date -j -f %Y-%m-%d "$2" +%s 2>/dev/null || TZ=UTC date -d "$2" +%s 2>/dev/null) || return 0
  echo $(( (b - a) / 86400 ))
}

# Memory files added or changed since the last pass (all of them when there is no stamp).
_churn() {
  if [ -f "$STAMP" ]; then
    find "$MEMORY_DIR" -maxdepth 1 -type f -name '*.md' ! -name "$MEMORY_INDEX" -newer "$STAMP" | wc -l
  else
    find "$MEMORY_DIR" -maxdepth 1 -type f -name '*.md' ! -name "$MEMORY_INDEX" | wc -l
  fi
}

_index_pct() {
  [ -f "$MEMORY_DIR/$MEMORY_INDEX" ] || { echo 0; return; }
  bytes=$(wc -c < "$MEMORY_DIR/$MEMORY_INDEX")
  echo $(( bytes * 100 / DREAM_INDEX_CAP_BYTES ))
}

_check() {
  churn=$(_churn | tr -d ' ')
  pct=$(_index_pct)
  last=""
  [ -f "$STAMP" ] && last=$(grep -o '[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}' "$STAMP" | head -1)
  days=""
  [ -n "$last" ] && days=$(_days_between "$last" "$TODAY")
  reason=""
  if [ -z "$days" ]; then
    reason="first-pass"
  elif [ "$days" -ge "$DREAM_MAX_DAYS" ]; then
    reason="ceiling"
  elif [ "$days" -ge "$DREAM_MIN_DAYS" ] && [ "$churn" -ge "$DREAM_CHURN" ]; then
    reason="churn"
  elif [ "$days" -ge "$DREAM_MIN_DAYS" ] && [ "$pct" -ge "$DREAM_INDEX_PCT" ]; then
    reason="index"
  fi
  status="due: no"
  [ -n "$reason" ] && status="due: yes reason=$reason"
  echo "$status days=${days:-never} churn=$churn index=${pct}% (floor ${DREAM_MIN_DAYS}d, ceiling ${DREAM_MAX_DAYS}d, churn ${DREAM_CHURN}, index ${DREAM_INDEX_PCT}%)"
  [ -n "$reason" ] && return 0
  return 10
}

if [ ! -d "$MEMORY_DIR" ]; then
  echo "memory-dream-due: no memory store at $MEMORY_DIR (set MEMORY_DIR)" >&2
  exit 1
fi

case "${1:-}" in
  check) _check; exit $? ;;
  stamp) echo "$TODAY" > "$STAMP" && echo "stamped $TODAY in $STAMP" ;;
  *) echo "usage: memory-dream-due.sh check|stamp" >&2; exit 1 ;;
esac
