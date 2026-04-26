#!/usr/bin/env bash
# Run a command in the Trading dev environment.
#
# Usage:
#   dev/lib/run-in-env.sh dune build
#   dev/lib/run-in-env.sh dune runtest trading/backtest/test/
#
# Locally (default): wraps with `docker exec` into trading-1-dev,
# cd's to the workspace, and sources opam env.
#
# In GHA / devcontainer: set TRADING_IN_CONTAINER=1 and the script
# runs natively (cd + opam env, no docker wrapping).
#
# Project root resolution (in-container path):
#   GHA:   ${GITHUB_WORKSPACE}/trading  — repo checks out at GITHUB_WORKSPACE;
#          the dune workspace root is one level deeper at trading/.
#   Local container / other: resolve relative to this script's location.
#          The script lives at <repo-root>/dev/lib/; climb two levels to reach
#          the repo root, then descend into trading/ (the dune workspace root).
#
# Both paths verify that dune-workspace exists at the resolved root and fail
# loudly if it doesn't — this catches path mismatches rather than silently
# running dune in the wrong directory.

set -euo pipefail

CONTAINER_NAME="${TRADING_CONTAINER_NAME:-trading-1-dev}"

if [ $# -eq 0 ]; then
  echo "Usage: dev/lib/run-in-env.sh <command> [args...]" >&2
  exit 1
fi

if [ -n "${TRADING_IN_CONTAINER:-}" ]; then
  # --- In-container path (GHA or devcontainer) ---

  if [ -n "${GITHUB_WORKSPACE:-}" ]; then
    # GHA: the repo is checked out at $GITHUB_WORKSPACE (e.g. /__w/trading/trading).
    # The dune workspace root is one level deeper at trading/.
    PROJECT_ROOT="${GITHUB_WORKSPACE}/trading"
  else
    # Devcontainer / fallback: resolve relative to this script's location.
    # The script lives at <repo-root>/dev/lib/run-in-env.sh.
    # Climb two levels to reach the repo root, then descend into trading/.
    script_dir="$(cd "$(dirname "$0")" && pwd)"
    PROJECT_ROOT="$(cd "${script_dir}/../.." && pwd)/trading"
  fi

  # Fail loudly rather than run dune in the wrong directory.
  if [ ! -f "${PROJECT_ROOT}/dune-workspace" ]; then
    echo "run-in-env.sh: no dune-workspace at ${PROJECT_ROOT}" >&2
    echo "  (expected dune workspace root; check PROJECT_ROOT derivation)" >&2
    echo "  PROJECT_ROOT=${PROJECT_ROOT}" >&2
    exit 1
  fi

  cd "$PROJECT_ROOT"
  eval "$(opam env)"
  exec "$@"
else
  # --- Local path: delegate to docker exec ---

  # The container mounts the repo at /workspaces/trading-1/.
  # The dune workspace root is at /workspaces/trading-1/trading/ (has dune-workspace).
  DOCKER_TRADING_ROOT="/workspaces/trading-1/trading"

  # Forward EODHD_API_KEY if set.
  DOCKER_ENV_FLAGS=""
  if [ -n "${EODHD_API_KEY:-}" ]; then
    DOCKER_ENV_FLAGS="-e EODHD_API_KEY"
  fi
  exec docker exec $DOCKER_ENV_FLAGS "$CONTAINER_NAME" bash -c \
    "cd $DOCKER_TRADING_ROOT && eval \$(opam env) && $*"
fi
