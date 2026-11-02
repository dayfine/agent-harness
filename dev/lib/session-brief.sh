#!/bin/sh
# harness: reusable
# session-brief.sh -- session ramp-up and handoff guard, run from Claude Code hooks.
#
# Usage:
#   session-brief.sh brief        SessionStart (startup|clear): prints the newest handoff
#                                 doc, plus main CI and an optional gate-status table, so a
#                                 fresh session starts briefed.
#   session-brief.sh precompact   PreCompact: warns (never blocks) when no handoff doc is
#                                 dated today, so a /compact does not stand in for the
#                                 committed handoff.
#
# The newest doc is picked by the date in its file name, not by mtime: a fresh checkout,
# worktree or cloud clone stamps every file with the checkout time. The date is the first
# YYYY-MM-DD in the file name. Of two docs with the same date, the longer name wins
# (<D>-eod.md beats <D>.md).
#
# Environment:
#   HANDOFF_GLOB             handoff docs, relative to the repo root
#                            (default dev/notes/next-session-priorities-*.md)
#   HANDOFF_TZ               time zone that defines "today" (default UTC)
#   GATE_STATUS_CMD          optional command whose output is shown under the brief
#                            (e.g. "sh dev/scripts/pr_gate_status.sh"); skipped when unset
#                            or when its first word is not an executable/file
#   SESSION_BRIEF_ROOT       repo root (default: two levels above this script)
#   SESSION_BRIEF_TODAY      YYYY-MM-DD to treat as today (tests)
#   SESSION_BRIEF_OFFLINE=1  skip the gh and GATE_STATUS_CMD calls
#   SESSION_BRIEF_MAX_LINES  cap on doc lines printed (default 150)
#   SESSION_BRIEF_STALE_DAYS age above which the brief warns (default 3)
#
# Always exits 0: a hook failure must never block a session start or a compaction.

REPO_ROOT=${SESSION_BRIEF_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}
HANDOFF_GLOB=${HANDOFF_GLOB:-dev/notes/next-session-priorities-*.md}
HANDOFF_TZ=${HANDOFF_TZ:-UTC}
TODAY=${SESSION_BRIEF_TODAY:-$(TZ=$HANDOFF_TZ date +%Y-%m-%d)}
MAX_LINES=${SESSION_BRIEF_MAX_LINES:-150}
STALE_DAYS=${SESSION_BRIEF_STALE_DAYS:-3}

# Newest handoff doc (repo-relative) by the date in its name; empty when there is none.
# Compared with the .md suffix stripped so a suffixed doc beats the plain one of the same date.
_newest_doc() {
  # shellcheck disable=SC2086  # the glob must expand
  newest=$(cd "$REPO_ROOT" 2>/dev/null && ls $HANDOFF_GLOB 2>/dev/null \
    | while read -r f; do
        d=$(basename "$f" | grep -o '[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}' | head -1)
        printf '%s %s %s\n' "${d:-0000-00-00}" "${f%.md}" "$f"
      done | sort | tail -1 | cut -d' ' -f3-)
  [ -n "$newest" ] && printf '%s\n' "$newest"
  return 0
}

# YYYY-MM-DD from a doc path; empty if the name carries no date.
_doc_date() {
  basename "$1" | grep -o '[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}' | head -1
}

# Whole days from date $1 to date $2 (both YYYY-MM-DD); empty if either fails to parse.
_days_between() {
  a=$(date -j -f %Y-%m-%d "$1" +%s 2>/dev/null || date -d "$1" +%s 2>/dev/null) || return 0
  b=$(date -j -f %Y-%m-%d "$2" +%s 2>/dev/null || date -d "$2" +%s 2>/dev/null) || return 0
  echo $(( (b - a) / 86400 ))
}

_gate_status() {
  [ -n "${GATE_STATUS_CMD:-}" ] || return 0
  first=${GATE_STATUS_CMD%% *}
  command -v "$first" >/dev/null 2>&1 || return 0
  echo
  echo "--- gate status ($GATE_STATUS_CMD) ---"
  (cd "$REPO_ROOT" && sh -c "$GATE_STATUS_CMD") 2>/dev/null || echo "(gate status command failed)"
}

_brief() {
  doc=$(_newest_doc)
  echo "=== Session brief ==="
  if [ -z "$doc" ]; then
    echo "No handoff doc found matching $HANDOFF_GLOB."
  else
    d=$(_doc_date "$doc")
    age=""
    [ -n "$d" ] && age=$(_days_between "$d" "$TODAY")
    echo "Newest handoff: $doc (dated ${d:-unknown}, ${age:-?} day(s) old)"
    if [ -n "$age" ] && [ "$age" -gt "$STALE_DAYS" ]; then
      echo "WARNING: handoff is stale (> $STALE_DAYS days). Verify its claims against main and GitHub before acting on it."
    fi
  fi
  if [ "${SESSION_BRIEF_OFFLINE:-}" != "1" ]; then
    if command -v gh >/dev/null 2>&1; then
      echo
      echo "--- main CI (latest run) ---"
      gh run list --branch main --limit 1 \
        --json status,conclusion,headSha \
        --jq '.[] | "\(.status) \(.conclusion) \(.headSha[0:9])"' 2>/dev/null \
        || echo "(gh unavailable)"
    fi
    _gate_status
  fi
  if [ -n "$doc" ]; then
    echo
    echo "--- $doc ---"
    head -n "$MAX_LINES" "$REPO_ROOT/$doc"
  fi
}

_precompact() {
  doc=$(_newest_doc)
  d=""
  [ -n "$doc" ] && d=$(_doc_date "$doc")
  if [ "$d" = "$TODAY" ]; then
    exit 0
  fi
  msg="No handoff dated $TODAY (newest: ${d:-none}). Compaction keeps this session going, but the next session reads the newest doc matching $HANDOFF_GLOB. Write one if the plan changed."
  printf '{"systemMessage": "%s"}\n' "$msg"
}

case "${1:-}" in
  brief) _brief ;;
  precompact) _precompact ;;
  *) echo "usage: session-brief.sh brief|precompact" >&2 ;;
esac
exit 0
