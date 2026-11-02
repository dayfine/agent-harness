#!/bin/sh
# Tests for dev/lib/session-brief.sh. Offline: no gh, no network.
# Run with: sh bin/test-session-brief.sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/../dev/lib/session-brief.sh"
PASS=0
FAIL=0
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

ok() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL: $1 -- $2"; FAIL=$((FAIL + 1)); }
has() { if printf '%s\n' "$2" | grep -q -- "$3"; then ok "$1"; else bad "$1" "expected '$3' in: $2"; fi; }
hasnt() { if printf '%s\n' "$2" | grep -q -- "$3"; then bad "$1" "unexpected '$3' in: $2"; else ok "$1"; fi; }

# run <mode> <today> <root>
run() {
  SESSION_BRIEF_OFFLINE=1 SESSION_BRIEF_TODAY="$2" SESSION_BRIEF_ROOT="$3" sh "$SCRIPT" "$1"
}

mkdir -p "$T/r/dev/notes" "$T/empty" "$T/eod/dev/notes"
printf 'NEWER-BODY\n' > "$T/r/dev/notes/next-session-priorities-2026-11-02.md"
sleep 1
printf 'OLDER-BODY\n' > "$T/r/dev/notes/next-session-priorities-2026-10-13.md"

echo "session-brief:"
out=$(run brief 2026-11-02 "$T/r")
has "picks newest by name, not mtime" "$out" "next-session-priorities-2026-11-02.md (dated 2026-11-02, 0 day"
has "prints the newest doc body" "$out" "NEWER-BODY"
hasnt "ignores the later-touched older doc" "$out" "OLDER-BODY"
hasnt "fresh doc is not stale" "$out" "WARNING: handoff is stale"
has "stale doc warns" "$(run brief 2026-11-10 "$T/r")" "WARNING: handoff is stale"

out=$(run precompact 2026-11-02 "$T/r")
if [ -z "$out" ]; then ok "precompact silent with today's doc"; else bad "precompact silent" "$out"; fi
has "precompact warns without today's doc" "$(run precompact 2026-11-03 "$T/r")" \
  '"systemMessage": "No handoff dated 2026-11-03 (newest: 2026-11-02)'

printf 'MORNING-BODY\n' > "$T/eod/dev/notes/next-session-priorities-2026-08-24.md"
printf 'EOD-BODY\n' > "$T/eod/dev/notes/next-session-priorities-2026-08-24-eod.md"
out=$(run brief 2026-08-24 "$T/eod")
has "suffixed -eod doc beats plain same-date doc" "$out" "EOD-BODY"
hasnt "superseded plain doc not printed" "$out" "MORNING-BODY"

has "brief with no docs" "$(run brief 2026-11-02 "$T/empty")" "No handoff doc found"
has "precompact with no docs" "$(run precompact 2026-11-02 "$T/empty")" "newest: none"

# HANDOFF_GLOB override
mkdir -p "$T/g/notes"
printf 'HANDOFF-BODY\n' > "$T/g/notes/handoff-2026-01-05.md"
out=$(HANDOFF_GLOB='notes/handoff-*.md' run brief 2026-01-05 "$T/g")
has "HANDOFF_GLOB override" "$out" "HANDOFF-BODY"

# HANDOFF_TZ: default today comes from the zone (Kiritimati is a day ahead of Pago Pago)
a=$(SESSION_BRIEF_OFFLINE=1 SESSION_BRIEF_ROOT="$T/empty" HANDOFF_TZ=Pacific/Kiritimati sh "$SCRIPT" precompact)
b=$(SESSION_BRIEF_OFFLINE=1 SESSION_BRIEF_ROOT="$T/empty" HANDOFF_TZ=Pacific/Pago_Pago sh "$SCRIPT" precompact)
if [ "$a" != "$b" ]; then ok "HANDOFF_TZ changes today"; else bad "HANDOFF_TZ" "same output: $a"; fi

# GATE_STATUS_CMD: shown when set and runnable, skipped when missing; offline skips it
printf '#!/bin/sh\necho GATE-TABLE\n' > "$T/r/gate.sh"
out=$(SESSION_BRIEF_TODAY=2026-11-02 SESSION_BRIEF_ROOT="$T/r" GATE_STATUS_CMD="sh gate.sh" sh "$SCRIPT" brief)
has "gate command output shown" "$out" "GATE-TABLE"
out=$(SESSION_BRIEF_TODAY=2026-11-02 SESSION_BRIEF_ROOT="$T/r" GATE_STATUS_CMD="no-such-cmd-xyz" sh "$SCRIPT" brief)
hasnt "missing gate command skipped" "$out" "gate status"
out=$(GATE_STATUS_CMD="sh gate.sh" run brief 2026-11-02 "$T/r")
hasnt "offline skips gate command" "$out" "GATE-TABLE"

# always exits 0, including bad usage
if sh "$SCRIPT" bogus >/dev/null 2>&1; then ok "exit 0 on bad usage"; else bad "exit code" "non-zero"; fi

echo "session-brief: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
