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

# run <memory dir> <today> <args...>; sets OUT and RC. Root has no conf unless a test writes one.
run() {
  m=$1; d=$2; shift 2
  RC=0
  OUT=$(DREAM_ROOT="$T/root" MEMORY_DIR="$m" DREAM_TODAY="$d" sh "$SCRIPT" "$@" 2>&1) || RC=$?
}

# store <dir> <n>: n memory files plus a small index, all dated well before any stamp
store() {
  mkdir -p "$1"
  i=0
  while [ "$i" -lt "$2" ]; do
    printf 'm\n' > "$1/m$i.md"; touch -t 202601010000 "$1/m$i.md"; i=$((i + 1))
  done
  printf 'index\n' > "$1/MEMORY.md"
}

# stamp <dir> <date>: a pass on <date>, with the stamp's mtime after the existing files
stamp() { printf '%s\n' "$2" > "$1/.last-dream"; touch -t 202606010000 "$1/.last-dream"; }

mkdir -p "$T/root/dev"
echo "memory-dream-due:"

store "$T/a" 3
run "$T/a" 2026-11-12 check
code "never consolidated is due" "$RC" 0
has "first-pass reason" "$OUT" "reason=first-pass"

stamp "$T/a" 2026-11-10
run "$T/a" 2026-11-12 check
code "inside the floor is not due" "$RC" 10
has "reports days and churn" "$OUT" "days=2 churn=0"

run "$T/a" 2026-11-24 check
code "ceiling makes it due" "$RC" 0
has "ceiling reason" "$OUT" "reason=ceiling"

run "$T/a" 2026-11-15 check
code "quiet store between floor and ceiling is not due" "$RC" 10

i=0
while [ "$i" -lt 15 ]; do printf 'n\n' > "$T/a/new$i.md"; i=$((i + 1)); done
run "$T/a" 2026-11-15 check
code "churn after the floor makes it due" "$RC" 0
has "churn reason and count" "$OUT" "reason=churn days=5 churn=15"
run "$T/a" 2026-11-11 check
code "churn inside the floor is not due" "$RC" 10

store "$T/b" 1
stamp "$T/b" 2026-11-10
head -c 20000 /dev/zero | tr '\0' 'x' > "$T/b/MEMORY.md"
run "$T/b" 2026-11-14 check
code "index near its cap makes it due" "$RC" 0
has "index reason" "$OUT" "reason=index"

printf 'DREAM_MIN_DAYS=1\nDREAM_MAX_DAYS=3\n' > "$T/root/dev/memory-dream.conf"
run "$T/a" 2026-11-13 check
code "conf file sets the ceiling" "$RC" 0
has "conf values shown" "$OUT" "floor 1d, ceiling 3d"
DREAM_MAX_DAYS=30 DREAM_ROOT="$T/root" MEMORY_DIR="$T/b" DREAM_TODAY=2026-11-13 \
  DREAM_INDEX_PCT=100 sh "$SCRIPT" check >/dev/null 2>&1 && rc=0 || rc=$?
code "environment overrides the conf file" "$rc" 10
rm "$T/root/dev/memory-dream.conf"

run "$T/a" 2026-11-20 stamp
has "stamp records today" "$(cat "$T/a/.last-dream")" "2026-11-20"
run "$T/a" 2026-11-20 check
code "freshly stamped store is not due" "$RC" 10
has "stamp resets churn" "$OUT" "churn=0"

run "$T/missing" 2026-11-20 check
code "missing store exits 1" "$RC" 1
run "$T/a" 2026-11-20 bogus
code "unknown command exits 1" "$RC" 1

echo
echo "memory-dream-due: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
