#!/bin/sh
# Tests for dev/lib/chain-runner.sh against scratch chains.
# Run with: sh bin/test-chain-runner.sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUNNER="$SCRIPT_DIR/../dev/lib/chain-runner.sh"
PASS=0
FAIL=0
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

ok() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
check() { # label, shell condition
  if eval "$2"; then ok "$1"; else bad "$1 [$2]"; fi
}

run() { # dir, then runner args; sets RC. Env for one run: RUN_ENV="X=1 Y=2"; run ...
  # (a `X=1 run` prefix would outlive the call: POSIX keeps assignments
  # made before a function call)
  d=$1; shift
  set +e
  # shellcheck disable=SC2086
  (cd "$d" && env ${RUN_ENV:-} sh "$RUNNER" "$@") > "$d/out" 2>&1
  RC=$?
  set -e
  RUN_ENV=
}

new() { # name, chain lines...; creates $T/<name> with chain.txt
  d="$T/$1"; shift
  mkdir -p "$d"
  printf '%s\n' "# a comment" "" "$@" > "$d/chain.txt"
  echo "$d"
}

echo "chain-runner:"

d=$(new ok "a echo one >> trace" "b echo two >> trace")
run "$d" run chain.txt st
check "all steps pass: exit 0" '[ "$RC" -eq 0 ]'
check "status done" '[ "$(cat "$d/st/status")" = done ]'
check "steps ran in order" '[ "$(cat "$d/trace" | tr "\n" " ")" = "one two " ]'
check "handoff says done" 'grep -q "status: done" "$d/st/handoff.md"'
check "step output went to its log" 'grep -q "exit 0" "$d/st/logs/a.log"'

d=$(new resume "a echo a >> trace" "b test -f fixed" "c echo c >> trace")
RUN_ENV="CHAIN_MAX_ATTEMPTS=1"; run "$d" run chain.txt st
check "failing step: exit 1" '[ "$RC" -eq 1 ]'
check "status failed" '[ "$(cat "$d/st/status")" = failed ]'
check "handoff names the step" 'grep -q "step: b (attempts: 1)" "$d/st/handoff.md"'
check "later steps did not run" '! grep -q c "$d/trace"'
touch "$d/fixed"
RUN_ENV="CHAIN_MAX_ATTEMPTS=1"; run "$d" run chain.txt st
check "attempts persist: still failed before reset" '[ "$RC" -eq 1 ] && grep -q "last exit this run: none" "$d/st/handoff.md"'
run "$d" reset st b
RUN_ENV="CHAIN_MAX_ATTEMPTS=1"; run "$d" run chain.txt st
check "after reset the chain finishes" '[ "$RC" -eq 0 ]'
check "done steps were not re-run" '[ "$(grep -c a "$d/trace")" -eq 1 ]'

d=$(new retry "a n=\$(cat n 2>/dev/null || echo 0); echo \$((n+1)) > n; [ \$n -ge 1 ]")
run "$d" run chain.txt st
check "flaky step passes on attempt 2" '[ "$RC" -eq 0 ] && [ "$(cat "$d/st/attempts/a")" = 2 ]'

d=$(new decide "a true" "b exit 10" "c true")
run "$d" run chain.txt st
check "exit 10: runner exits 10" '[ "$RC" -eq 10 ]'
check "status decision" '[ "$(cat "$d/st/status")" = decision ]'
check "decision step is not marked done" '! grep -qx b "$d/st/done"'
check "decision is not retried" '[ "$(cat "$d/st/attempts/b")" = 1 ]'

d=$(new slow "a sleep 3 && touch late")
RUN_ENV="CHAIN_STEP_TIMEOUT=1 CHAIN_MAX_ATTEMPTS=1"; run "$d" run chain.txt st
check "timeout: step fails" '[ "$RC" -eq 1 ] && grep -q "last exit this run: 124" "$d/st/handoff.md"'
sleep 3
check "timeout kills the whole step, not only its shell" '[ ! -f "$d/late" ]'

d=$(new quiet "a echo secret-ish; exit 3")
RUN_ENV="CHAIN_TAIL_LINES=0 CHAIN_MAX_ATTEMPTS=1"; run "$d" run chain.txt st
check "CHAIN_TAIL_LINES=0 quotes no log" '! grep -q secret-ish "$d/st/handoff.md"'
RUN_ENV="CHAIN_MAX_ATTEMPTS=1"; run "$d" reset st a
RUN_ENV="CHAIN_MAX_ATTEMPTS=1"; run "$d" run chain.txt st
check "default handoff quotes the log tail" 'grep -q secret-ish "$d/st/handoff.md"'

d=$(new dup "a true" "a true")
run "$d" run chain.txt st
check "duplicate id: exit 2" '[ "$RC" -eq 2 ]'
d=$(new nocmd "a")
run "$d" run chain.txt st
check "step without a command: exit 2" '[ "$RC" -eq 2 ]'

d=$(new locked "a true")
mkdir -p "$d/st/lock"; echo $$ > "$d/st/lock/pid"
run "$d" run chain.txt st
check "live lock holder: exit 3" '[ "$RC" -eq 3 ]'
sh -c 'exit 0' & dead=$!; wait "$dead"
echo "$dead" > "$d/st/lock/pid"
run "$d" run chain.txt st
check "dead lock holder is taken over" '[ "$RC" -eq 0 ] && [ ! -d "$d/st/lock" ]'

run "$T" bogus
check "unknown command: exit 2" '[ "$RC" -eq 2 ]'

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
