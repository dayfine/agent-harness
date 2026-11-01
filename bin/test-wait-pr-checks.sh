#!/bin/sh
# Tests for dev/lib/wait-pr-checks.sh with a fake gh.
# Run with: sh bin/test-wait-pr-checks.sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WAIT="$SCRIPT_DIR/../dev/lib/wait-pr-checks.sh"
PASS=0
FAIL=0
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

# Fake gh: replays one "<rc> <output>" line per call from $T/script.
cat > "$T/gh" <<'GH'
#!/bin/sh
n=$(cat "$FAKE/n" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$FAKE/n"
line=$(sed -n "${n}p" "$FAKE/script"); [ -n "$line" ] || line=$(tail -n 1 "$FAKE/script")
printf '%s\n' "${line#* }"
exit "${line%% *}"
GH
chmod +x "$T/gh"

case_() { # label, expected rc, expected calls, script lines...
  label=$1; want=$2; calls=$3; shift 3
  rm -f "$T/n"; printf '%s\n' "$@" > "$T/script"
  set +e
  FAKE=$T GH=$T/gh WAIT_INTERVAL=0 WAIT_MAX_POLLS=4 sh "$WAIT" 7 > "$T/out" 2>&1
  rc=$?
  set -e
  if [ "$rc" = "$want" ] && [ "$(cat "$T/n")" = "$calls" ]; then
    echo "  PASS: $label"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $label (rc $rc want $want, calls $(cat "$T/n") want $calls)"; FAIL=$((FAIL + 1))
  fi
}

echo "wait-pr-checks:"
case_ "pending then pass" 0 3 "8 build	pending" "8 build	pending" "0 build	pass"
case_ "a failed check is a decision" 10 2 "8 build	pending" "1 build	fail	1m"
case_ "a cancelled check is a decision" 10 1 "1 build	cancel	1m"
case_ "pending forever stops at the cap" 1 4 "8 build	pending"
case_ "gh errors stop after 3" 1 3 "1 HTTP 502"
case_ "one gh error is tolerated" 0 2 "1 HTTP 502" "0 build	pass"
set +e; sh "$WAIT" > /dev/null 2>&1; rc=$?; set -e
if [ "$rc" = 2 ]; then echo "  PASS: no PR: exit 2"; PASS=$((PASS + 1)); else echo "  FAIL: no PR: rc $rc"; FAIL=$((FAIL + 1)); fi

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
