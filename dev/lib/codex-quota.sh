#!/bin/sh
# harness: reusable
# codex-quota.sh [--guard PCT] [--weekly-guard PCT] [--max-age SEC] [--no-probe] [--no-log]
#
# Reads the Codex plan limits (5-hour and weekly windows) so the dispatcher can pace Codex hand-offs. Codex cloud and
# the Codex CLI share one account limit, and a cloud task cannot read it from its sandbox, so pacing happens here,
# before a task is handed out.
#
# How: every Codex CLI session writes a rollout log under $CODEX_HOME/sessions/YYYY/MM/DD/rollout-*.jsonl whose
# token_count events carry rate_limits.{primary,secondary}.{used_percent,window_minutes,resets_at} (primary = the
# 5-hour window, secondary = the weekly one). `codex exec --json` does not print them (checked on codex-cli 0.163.0),
# so this reads the newest rollout. If none is younger than --max-age (default 1800 s), it first runs one tiny
# `codex exec` ("reply ok") to refresh it, unless --no-probe. Each reading is appended to $CODEX_QUOTA_LOG (default
# ~/.codex-quota/log.csv: utc,five_hour_pct,weekly_pct,five_reset,weekly_reset).
#
# --guard PCT: exit 3 when the 5-hour window is at or above PCT (the user's pacing target is 70: hand out no new
# Codex task above 70 % of the window). --weekly-guard PCT: the same for the weekly window.
# Exit 0 ok, 2 usage, 3 over a guard, 4 the reading failed.
set -eu
CODEX_HOME=${CODEX_HOME:-$HOME/.codex}
CODEX_QUOTA_LOG=${CODEX_QUOTA_LOG:-$HOME/.codex-quota/log.csv}
GUARD=""; WGUARD=""; MAX_AGE=1800; PROBE=1; LOG=1
while [ $# -gt 0 ]; do
  case "$1" in
    --guard) [ $# -ge 2 ] || { echo "--guard needs a value" >&2; exit 2; }; GUARD=$2; shift ;;
    --weekly-guard) [ $# -ge 2 ] || { echo "--weekly-guard needs a value" >&2; exit 2; }; WGUARD=$2; shift ;;
    --max-age) [ $# -ge 2 ] || { echo "--max-age needs a value" >&2; exit 2; }; MAX_AGE=$2; shift ;;
    --no-probe) PROBE=0 ;;
    --no-log) LOG=0 ;;
    *) echo "usage: $0 [--guard PCT] [--weekly-guard PCT] [--max-age SEC] [--no-probe] [--no-log]" >&2; exit 2 ;;
  esac
  shift
done
command -v jq >/dev/null 2>&1 || { echo "codex-quota: jq not installed" >&2; exit 4; }

# newest rollout file with a numeric used_percent (a rate_limits record with numbers); prints "<mtime> <path>" or nothing
newest() {
  [ -d "$CODEX_HOME/sessions" ] || return 0
  find "$CODEX_HOME/sessions" -name 'rollout-*.jsonl' -type f 2>/dev/null | while IFS= read -r f; do
    grep -q '"used_percent":[0-9]' "$f" 2>/dev/null || continue
    m=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f")
    echo "$m $f"
  done | sort -n | tail -1
}

now=$(date -u +%s)
pick=$(newest)
age=$([ -n "$pick" ] && echo $((now - ${pick%% *})) || echo 999999999)
if [ "$age" -gt "$MAX_AGE" ] && [ "$PROBE" = 1 ]; then
  command -v codex >/dev/null 2>&1 || { echo "codex-quota: codex CLI not found and no fresh rollout" >&2; exit 4; }
  probe_dir=$(mktemp -d); trap 'rm -rf "$probe_dir"' EXIT
  (cd "$probe_dir" && codex exec --json --skip-git-repo-check -s read-only "Reply with the single word ok." \
    </dev/null >/dev/null 2>&1) || true
  pick=$(newest)
  age=$([ -n "$pick" ] && echo $((now - ${pick%% *})) || echo 999999999)
fi
[ -n "$pick" ] || { echo "codex-quota: no rollout with rate_limits under $CODEX_HOME/sessions" >&2; exit 4; }
file=${pick#* }

# the last rate_limits record with a numeric five-hour used_percent. Codex also writes records for other limit ids
# (limit_id "premium") whose primary/secondary are null; those are skipped.
read -r five weekly five_reset weekly_reset <<EOF
$(grep '"used_percent":[0-9]' "$file" | tail -1 | jq -r '[.. | objects | select(has("rate_limits")) | .rate_limits | select(.primary.used_percent != null)][-1]
  | "\(.primary.used_percent // "na") \(.secondary.used_percent // "na") \(.primary.resets_at // "na") \(.secondary.resets_at // "na")"')
EOF
[ "$five" != na ] && [ "$weekly" != na ] || { echo "codex-quota: rate_limits without used_percent in $file" >&2; exit 4; }

if [ "$LOG" = 1 ]; then
  mkdir -p "$(dirname "$CODEX_QUOTA_LOG")"
  [ -f "$CODEX_QUOTA_LOG" ] || echo "utc,five_hour_pct,weekly_pct,five_reset,weekly_reset" > "$CODEX_QUOTA_LOG"
  echo "$now,$five,$weekly,$five_reset,$weekly_reset" >> "$CODEX_QUOTA_LOG"
fi
awk -v five="$five" -v wk="$weekly" -v fr="$five_reset" -v wr="$weekly_reset" -v now="$now" -v age="$age" 'BEGIN {
  printf "codex five-hour: %.0f %% used", five; if (fr != "na") printf ", resets in %.1f h", (fr - now) / 3600; print ""
  printf "codex weekly: %.0f %% used", wk; if (wr != "na") printf ", resets in %.1f days", (wr - now) / 86400; print ""
  printf "reading age: %d s\n", age
}'
over() { awk -v v="$1" -v m="$2" 'BEGIN { exit !(v >= m) }'; }
if [ -n "$GUARD" ] && over "$five" "$GUARD"; then
  echo "codex-quota: five-hour $five % >= guard $GUARD %: hold new Codex hand-offs" >&2; exit 3
fi
if [ -n "$WGUARD" ] && over "$weekly" "$WGUARD"; then
  echo "codex-quota: weekly $weekly % >= guard $WGUARD %: hold new Codex hand-offs" >&2; exit 3
fi
exit 0
