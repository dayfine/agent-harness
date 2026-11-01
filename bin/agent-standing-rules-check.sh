#!/bin/sh
# harness: reusable
# Pin the standing-rules block in dispatched agents' definitions.
#
# Dispatch briefs carry only the task; the rules that hold for every dispatch
# live once in each agent's definition (.agents/rules/standing-rules.md). That
# is safe only while each definition still carries them. This check fails when
# a listed agent's definition loses the block or a required phrase.
#
# usage: sh bin/agent-standing-rules-check.sh [ROOT]
#   ROOT defaults to the current directory. Reads ROOT/.agents/standing-rules.conf
#   (lines: <agent> <role>...; roles all|build|review) and checks
#   ROOT/.agents/agents/<agent>.md. No conf file: nothing to check, exit 0.
# Exit: 0 ok, 1 a rule is missing, 2 bad conf.
set -eu

ROOT=${1:-$PWD}
CONF="$ROOT/.agents/standing-rules.conf"
AGENTS="$ROOT/.agents/agents"

if [ ! -f "$CONF" ]; then
  echo "agent-standing-rules-check: no $CONF; nothing to check"
  exit 0
fi

FAILED=0
CHECKED=0

need() { # file, agent, fixed string
  if ! grep -qF -- "$3" "$1"; then
    echo "FAIL: $2: standing rule missing: $3" >&2
    FAILED=$((FAILED + 1))
  fi
}

check_role() { # file, agent, role
  case "$3" in
    all)
      need "$1" "$2" "## Standing rules — the dispatch brief does not repeat these"
      need "$1" "$2" "<!-- standing-rules"
      need "$1" "$2" "Never background a long command and end the turn"
      need "$1" "$2" "Every wait loop has an iteration cap"
      ;;
    build)
      need "$1" "$2" "Never end with an unpushed commit."
      need "$1" "$2" "the dispatcher waits for CI"
      ;;
    review) need "$1" "$2" "Post first, then verify" ;;
    *)
      echo "agent-standing-rules-check: $CONF: unknown role '$3' for $2" >&2
      exit 2
      ;;
  esac
}

while read -r agent roles; do
  case "$agent" in ''|'#'*) continue ;; esac
  if [ -z "$roles" ]; then
    echo "agent-standing-rules-check: $CONF: no roles for $agent" >&2
    exit 2
  fi
  f="$AGENTS/$agent.md"
  if [ ! -f "$f" ]; then
    echo "FAIL: $agent: $f not found" >&2
    FAILED=$((FAILED + 1))
    continue
  fi
  for role in $roles; do check_role "$f" "$agent" "$role"; done
  CHECKED=$((CHECKED + 1))
done < "$CONF"

[ "$FAILED" -eq 0 ] || exit 1
echo "OK: agent-standing-rules-check — $CHECKED agent definitions carry their standing rules."
