#!/bin/sh
# Tests for agent-standing-rules-check.sh against fixture trees.
# Run with: sh bin/test-agent-standing-rules-check.sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECK="$SCRIPT_DIR/agent-standing-rules-check.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PASS=0
FAIL=0
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

expect_rc() { # label, expected rc, root
  set +e
  sh "$CHECK" "$3" >"$T/out" 2>&1
  rc=$?
  set -e
  if [ "$rc" = "$2" ]; then
    echo "  PASS: $1"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $1 (expected rc $2, got $rc)"; sed 's/^/    /' "$T/out"; FAIL=$((FAIL + 1))
  fi
}

expect_out() { # label, fixed string expected in the last run's output
  if grep -qF -- "$2" "$T/out"; then
    echo "  PASS: $1"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $1 (missing: $2)"; sed 's/^/    /' "$T/out"; FAIL=$((FAIL + 1))
  fi
}

fixture() { # dir, conf line; copies the shipped qc-structural (all + review)
  mkdir -p "$1/.agents/agents"
  cp "$REPO_ROOT/.agents/agents/qc-structural.md" "$1/.agents/agents/a.md"
  printf '# comment\n\n%s\n' "$2" > "$1/.agents/standing-rules.conf"
}

echo "agent-standing-rules-check:"

expect_rc "shipped definitions pass" 0 "$REPO_ROOT"

mkdir -p "$T/empty"
expect_rc "no conf file is not an error" 0 "$T/empty"

fixture "$T/ok" "a all review"
expect_rc "all + review roles pass" 0 "$T/ok"

fixture "$T/build" "a all build"
expect_rc "review agent listed as build fails" 1 "$T/build"
expect_out "names the missing build phrase" "Never end with an unpushed commit."

fixture "$T/drop" "a all review"
grep -vF "Never background a long command and end the turn" "$T/drop/.agents/agents/a.md" > "$T/x"
mv "$T/x" "$T/drop/.agents/agents/a.md"
expect_rc "dropping the no-waiting phrase fails" 1 "$T/drop"
expect_out "names the agent" "FAIL: a:"

fixture "$T/missing" "nope all"
expect_rc "listed agent without a definition fails" 1 "$T/missing"

fixture "$T/role" "a all bogus"
expect_rc "unknown role is a conf error" 2 "$T/role"

fixture "$T/noroles" "a"
expect_rc "agent with no roles is a conf error" 2 "$T/noroles"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
