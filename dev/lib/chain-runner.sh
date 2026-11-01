#!/bin/sh
# harness: reusable
# chain-runner.sh — run a chain of shell steps without a model in the loop.
#
# The runner owns the sequence and all the waiting; an agent wakes only when
# the runner exits, and then reads one small file (handoff.md) instead of the
# logs. See .agents/rules/long-chain-ownership.md.
#
# usage:
#   sh dev/lib/chain-runner.sh run    <chain-file> <state-dir>
#   sh dev/lib/chain-runner.sh status <state-dir>
#   sh dev/lib/chain-runner.sh reset  <state-dir> <step-id>
#
# Chain file: one step per line, `<id> <shell command>`. Blank lines and
# lines starting with # are skipped. Ids are unique words ([A-Za-z0-9_.-]).
# Steps run in order, in the directory `run` was invoked from. Each step's output goes to
# <state-dir>/logs/<id>.log only.
#
# A step's exit code decides what happens next:
#   0                     step done; recorded in <state-dir>/done
#   10                    a decision is needed: stop, status `decision`
#   anything else / time  retry, up to CHAIN_MAX_ATTEMPTS attempts in total
#                         across runs; then stop, status `failed`
#
# Re-running `run` resumes: steps listed in <state-dir>/done are skipped.
# Attempts count across runs, so a failed step stays failed until `reset`
# clears its count (after someone has fixed the cause).
# Only one runner per state dir (a lock dir holding the pid; a lock whose
# pid is dead is taken over).
#
# Environment:
#   CHAIN_MAX_ATTEMPTS   attempts per step, default 2
#   CHAIN_STEP_TIMEOUT   seconds per attempt, default 0 (no limit)
#   CHAIN_TAIL_LINES     log lines quoted in handoff.md, default 20
#
# Exit: 0 chain done, 10 decision needed, 1 a step failed, 2 usage or
# chain-file error, 3 another runner holds the lock.
#
# handoff.md quotes the tail of the stopping step's log. Keep secrets and
# licensed data out of step output, or set CHAIN_TAIL_LINES=0.
set -eu

DECISION_RC=10

_die() { echo "chain-runner: $1" >&2; exit "${2:-2}"; }

_usage() {
  _die "usage: chain-runner.sh run <chain-file> <state-dir> | status <state-dir> | reset <state-dir> <step-id>"
}

# Print the chain's steps as `<id> <command>`, validated.
_steps() {
  awk '
    /^[[:space:]]*(#|$)/ { next }
    {
      id = $1
      if (id !~ /^[A-Za-z0-9_.-]+$/) { print "bad step id: " id > "/dev/stderr"; bad = 1; exit }
      if (seen[id]++) { print "duplicate step id: " id > "/dev/stderr"; bad = 1; exit }
      if (NF < 2) { print "step without a command: " id > "/dev/stderr"; bad = 1; exit }
      print
    }
    END { exit bad }
  ' "$1"
}

_lock() { # state-dir
  if mkdir "$1/lock" 2>/dev/null; then
    echo $$ > "$1/lock/pid"
    return 0
  fi
  pid=$(cat "$1/lock/pid" 2>/dev/null || echo "")
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    _die "another runner (pid $pid) holds $1/lock" 3
  fi
  echo $$ > "$1/lock/pid"
}

_unlock() { rm -rf "$STATE/lock"; }

_is_done() { grep -qx "$1" "$STATE/done" 2>/dev/null; }

_attempts() { cat "$STATE/attempts/$1" 2>/dev/null || echo 0; }

_done_count() { if [ -f "$STATE/done" ]; then wc -l < "$STATE/done" | tr -d " "; else echo 0; fi; }

# Run one attempt of a step; print its exit code (124 on timeout).
_attempt() { # id, command
  log="$STATE/logs/$1.log"
  echo "=== attempt $(($(_attempts "$1") + 1)) $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$log"
  # Job control puts the step in its own process group, so a timeout kills
  # everything the step started, not only its shell.
  set -m
  sh -c "$2" >> "$log" 2>&1 &
  child=$!
  set +m
  if [ "${CHAIN_STEP_TIMEOUT:-0}" -gt 0 ]; then
    i=0
    while kill -0 "$child" 2>/dev/null; do
      i=$((i + 1))
      if [ "$i" -gt "$CHAIN_STEP_TIMEOUT" ]; then
        kill -- "-$child" 2>/dev/null || kill "$child" 2>/dev/null || true
        wait "$child" 2>/dev/null || true
        echo "=== timed out after ${CHAIN_STEP_TIMEOUT}s" >> "$log"
        echo 124
        return 0
      fi
      sleep 1
    done
  fi
  set +e
  wait "$child"
  rc=$?
  set -e
  echo "=== exit $rc" >> "$log"
  echo "$rc"
}

_handoff() { # status, step id or "", note
  {
    echo "# Chain handoff"
    echo
    echo "- status: $1"
    echo "- chain: $CHAIN"
    echo "- at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    [ -z "$2" ] || echo "- step: $2 (attempts: $(_attempts "$2"))"
    echo "- done: $(_done_count) of $TOTAL steps"
    echo "- note: $3"
    if [ -n "$2" ] && [ "${CHAIN_TAIL_LINES:-20}" -gt 0 ]; then
      echo
      echo "## Last ${CHAIN_TAIL_LINES:-20} lines of logs/$2.log"
      echo
      echo '```'
      tail -n "${CHAIN_TAIL_LINES:-20}" "$STATE/logs/$2.log"
      echo '```'
    fi
  } > "$STATE/handoff.md"
  echo "$1" > "$STATE/status"
}

# Run one step to completion or its attempt cap. Returns the chain exit code
# for a stop, or 0 to continue.
_run_step() { # id, command
  max=${CHAIN_MAX_ATTEMPTS:-2}
  rc=none
  while [ "$(_attempts "$1")" -lt "$max" ]; do
    rc=$(_attempt "$1" "$2")
    echo $(($(_attempts "$1") + 1)) > "$STATE/attempts/$1"
    if [ "$rc" -eq 0 ]; then
      echo "$1" >> "$STATE/done"
      return 0
    fi
    if [ "$rc" -eq "$DECISION_RC" ]; then
      _handoff decision "$1" "step asked for a decision (exit $DECISION_RC)"
      return "$DECISION_RC"
    fi
  done
  _handoff failed "$1" "failed $(_attempts "$1") of $max attempts; last exit this run: $rc (reset the step to retry)"
  return 1
}

_run() { # chain-file, state-dir
  CHAIN=$1
  STATE=$2
  [ -f "$CHAIN" ] || _die "no chain file: $CHAIN"
  steps=$(_steps "$CHAIN") || _die "bad chain file: $CHAIN"
  TOTAL=$(printf '%s\n' "$steps" | grep -c . || true)
  mkdir -p "$STATE/logs" "$STATE/attempts"
  _lock "$STATE"
  trap _unlock EXIT
  echo running > "$STATE/status"
  printf '%s\n' "$steps" > "$STATE/steps"
  while read -r id cmd; do
    _is_done "$id" && continue
    set +e
    _run_step "$id" "$cmd" < /dev/null
    rc=$?
    set -e
    [ "$rc" -eq 0 ] || exit "$rc"
  done < "$STATE/steps"
  _handoff done "" "all steps done"
}

_status() { # state-dir
  [ -f "$1/status" ] || _die "no chain state in $1"
  cat "$1/status"
}

_reset() { # state-dir, step-id
  [ -d "$1/attempts" ] || _die "no chain state in $1"
  rm -f "$1/attempts/$2"
}

cmd=${1:-}
case "$cmd" in
  run) [ $# -eq 3 ] || _usage; _run "$2" "$3" ;;
  status) [ $# -eq 2 ] || _usage; _status "$2" ;;
  reset) [ $# -eq 3 ] || _usage; _reset "$2" "$3" ;;
  *) _usage ;;
esac
