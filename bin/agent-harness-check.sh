#!/bin/sh
# Frontmatter linter for the agent-harness layer model.
#
# Verifies every .agents/agents/*.md and .agents/rules/*.md file in the
# repository has a `harness:` field with a recognised value. Fails fast
# with the offending file paths if anything is missing or malformed.
#
# Run from the consuming project's root:
#   sh bin/agent-harness-check.sh
#
# Exit code: 0 on success, 1 on any violation.
#
# Recognised values:
#   reusable — ship as-is from the upstream agent-harness; do not edit.
#   template — skeleton; the consuming project fills in placeholders.
#   project  — domain / language / framework specific; do not export back
#              to the upstream harness.
#
# When a sync from upstream lands, run this check to confirm every file
# is still classified. Adding a new agent or rule without the field is
# the most common drift and the easiest to forget.

set -eu

repo_root() {
  if [ -d "$PWD/.git" ] || [ -d "$PWD/.jj" ]; then
    echo "$PWD"
    return
  fi
  cd "$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")" && pwd
}

REPO_ROOT="$(repo_root)"
PATTERNS=".agents/agents .agents/rules"
EXIT=0

# Collect candidate files. Both directories may not exist in a fresh
# project — that's fine, just means nothing to lint.
FILES=""
for d in $PATTERNS; do
  if [ -d "$REPO_ROOT/$d" ]; then
    set +e
    found=$(find "$REPO_ROOT/$d" -maxdepth 1 -type f -name "*.md" 2>/dev/null)
    set -e
    [ -n "$found" ] && FILES="$FILES
$found"
  fi
done

if [ -z "$FILES" ]; then
  echo "agent-harness-check: no .agents/agents or .agents/rules files to check."
  exit 0
fi

MISSING=""
INVALID=""
COUNT_REUSABLE=0
COUNT_TEMPLATE=0
COUNT_PROJECT=0

# shellcheck disable=SC2086  # word-splitting on FILES is intentional
for f in $FILES; do
  marker=$(awk '/^harness:[[:space:]]*/{print $2; exit}' "$f")
  case "$marker" in
    reusable) COUNT_REUSABLE=$((COUNT_REUSABLE + 1)) ;;
    template) COUNT_TEMPLATE=$((COUNT_TEMPLATE + 1)) ;;
    project)  COUNT_PROJECT=$((COUNT_PROJECT + 1)) ;;
    "")       MISSING="$MISSING $f" ;;
    *)        INVALID="$INVALID $f($marker)" ;;
  esac
done

if [ -n "$MISSING" ]; then
  echo "FAIL: agent-harness-check — missing harness: field in:" >&2
  for f in $MISSING; do echo "  $f" >&2; done
  EXIT=1
fi

if [ -n "$INVALID" ]; then
  echo "FAIL: agent-harness-check — invalid harness: value (must be reusable | template | project):" >&2
  for entry in $INVALID; do echo "  $entry" >&2; done
  EXIT=1
fi

if [ "$EXIT" -eq 0 ]; then
  total=$((COUNT_REUSABLE + COUNT_TEMPLATE + COUNT_PROJECT))
  echo "OK: agent-harness-check — $total files tagged ($COUNT_REUSABLE reusable, $COUNT_TEMPLATE template, $COUNT_PROJECT project)."
fi

exit "$EXIT"
