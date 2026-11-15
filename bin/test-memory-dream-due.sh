#!/bin/sh
# Tests for dev/lib/memory-dream-due.sh. Offline; works on a temp memory store.
# Run with: sh bin/test-memory-dream-due.sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/../dev/lib/memory-dream-due.sh"
PASS=0
FAIL=0
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

ok() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL: $1 -- $2"; FAIL=$((FAIL + 1)); }
has() { if printf '%s\n' "$2" | grep -q -- "$3"; then ok "$1"; else bad "$1" "expected '$3' in: $2"; fi; }
code() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "exit $2, expected $3"; fi; }

# Day 0 is the day of the last pass; every test date is an offset from it.
D0=$(date +%Y-%m-%d)
day() { date -j -v+"$1"d -f %Y-%m-%d "$D0" +%Y-%m-%d 2>/dev/null || date -d "$D0 + $1 days" +%Y-%m-%d; }

# run <memory dir> <day offset> <args...>; sets OUT and RC. Root has no conf unless a test writes one.
run() {
  m=$1; d=$(day "$2"); shift 2
  RC=0
  OUT=$(DREAM_ROOT="$T/root" MEMORY_DIR="$m" DREAM_TODAY="$d" sh "$SCRIPT" "$@" 2>&1) || RC=$?
}

# store <dir> <n>: n memory files plus a small index
store() {
  mkdir -p "$1"
  i=0
  while [ "$i" -lt "$2" ]; do printf 'm\n' > "$1/m$i.md"; i=$((i + 1)); done
  printf 'index\n' > "$1/MEMORY.md"
}

# stamp <dir>: a pass on day 0. Its mtime (the churn cutoff) is now, so callers sleep 1 between
# writing files and stamping when the order matters (find -newer compares whole seconds).
stamp() { printf '%s\n' "$D0" > "$1/.last-dream"; }

mkdir -p "$T/root/dev"
echo "memory-dream-due:"

store "$T/a" 3
store "$T/b" 1
run "$T/a" 2 check
code "never consolidated is due" "$RC" 0
has "first-pass reason" "$OUT" "reason=first-pass"

sleep 1
stamp "$T/a"
stamp "$T/b"
run "$T/a" 2 check
code "inside the floor is not due" "$RC" 10
has "reports days and churn" "$OUT" "days=2 churn=0"

run "$T/a" 14 check
code "ceiling makes it due" "$RC" 0
has "ceiling reason" "$OUT" "reason=ceiling"

run "$T/a" 5 check
code "quiet store between floor and ceiling is not due" "$RC" 10

sleep 1
i=0
while [ "$i" -lt 15 ]; do printf 'n\n' > "$T/a/new$i.md"; i=$((i + 1)); done
run "$T/a" 5 check
code "churn after the floor makes it due" "$RC" 0
has "churn reason and count" "$OUT" "reason=churn days=5 churn=15"
run "$T/a" 1 check
code "churn inside the floor is not due" "$RC" 10

head -c 20000 /dev/zero | tr '\0' 'x' > "$T/b/MEMORY.md"
run "$T/b" 4 check
code "index near its cap makes it due" "$RC" 0
has "index reason (index edits are not churn)" "$OUT" "reason=index days=4 churn=0"

printf 'DREAM_MIN_DAYS=1\nDREAM_MAX_DAYS=3\n' > "$T/root/dev/memory-dream.conf"
run "$T/a" 3 check
code "conf file sets the ceiling" "$RC" 0
has "conf values shown" "$OUT" "floor 1d, ceiling 3d"
DREAM_MAX_DAYS=30 DREAM_ROOT="$T/root" MEMORY_DIR="$T/b" DREAM_TODAY="$(day 3)" \
  DREAM_INDEX_PCT=100 sh "$SCRIPT" check >/dev/null 2>&1 && rc=0 || rc=$?
code "environment overrides the conf file" "$rc" 10
rm "$T/root/dev/memory-dream.conf"

run "$T/a" 10 stamp
has "stamp records today" "$(cat "$T/a/.last-dream")" "$(day 10)"
run "$T/a" 10 check
code "freshly stamped store is not due" "$RC" 10
has "stamp resets churn" "$OUT" "churn=0"

# DST: the one case that needs fixed dates. US clocks spring forward on 2028-03-12, so in local
# time 02-28 -> 03-13 is 13 days 23 hours. The ceiling must still fire at 14 days.
mkdir -p "$T/dst" && printf 2028-02-28 > "$T/dst/.last-dream"
TZ=America/New_York DREAM_ROOT="$T/root" MEMORY_DIR="$T/dst" DREAM_TODAY=2028-03-13 \
  sh "$SCRIPT" check >/dev/null 2>&1 && rc=0 || rc=$?
code "day count is not cut short by a DST change" "$rc" 0

run "$T/missing" 10 check
code "missing store exits 1" "$RC" 1
run "$T/a" 10 bogus
code "unknown command exits 1" "$RC" 1

echo
echo "memory-dream-due: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
