#!/bin/sh
# agent-harness-sync — selectively sync harness: reusable files from upstream.
#
# Usage: agent-harness sync
#
# Environment variables:
#   AGENT_HARNESS_TAG       Upstream tag/branch to fetch (default: main)
#   AGENT_HARNESS_URL       Upstream git URL (default: dayfine/agent-harness on GitHub)
#   AGENT_HARNESS_UPSTREAM  Path to a local upstream clone (skips network fetch)
#
# harness: reusable

set -eu

# ---------------------------------------------------------------------------
# Pure helper functions (sourced by tests)
# ---------------------------------------------------------------------------

# has_frontmatter <file>
# Returns 0 if the file starts with --- and has a closing ---.
has_frontmatter() {
  [ "$(head -1 "$1")" = "---" ] && awk '/^---$/{c++} END{exit (c>=2 ? 0 : 1)}' "$1"
}

# get_frontmatter <file>
# Prints the YAML frontmatter block including both --- delimiters.
get_frontmatter() {
  awk '/^---$/{c++; print; if(c==2){exit}; next} c==1{print}' "$1"
}

# get_body <file>
# Prints everything after the closing --- delimiter.
get_body() {
  awk 'BEGIN{c=0} /^---$/{c++; next} c>=2{print}' "$1"
}

# has_reusable_tag <file>
# Returns 0 if the file is tagged harness: reusable.
has_reusable_tag() {
  f="$1"
  case "$f" in
    *.md)
      # Must be inside the YAML frontmatter block
      awk 'BEGIN{c=0;found=0} /^---$/{c++; if(c==2)exit; next} c==1 && /^harness:[[:space:]]*reusable/{found=1} END{exit (found ? 0 : 1)}' "$f"
      ;;
    *.sh|*.yml)
      # Must appear in the first 20 lines as a comment
      head -20 "$f" | grep -q '#[[:space:]]*harness:[[:space:]]*reusable'
      ;;
    *)
      return 1
      ;;
  esac
}

# build_merged <local_file> <upstream_file> <output_file>
# Writes local frontmatter + upstream body into output_file.
# Falls back to full upstream content when local has no frontmatter.
# Warns when frontmatter keys diverge.
build_merged() {
  local_file="$1"
  upstream_file="$2"
  out_file="$3"

  if [ -f "$local_file" ] && has_frontmatter "$local_file"; then
    # Warn if top-level keys in frontmatter differ
    local_keys=$(get_frontmatter "$local_file" | grep -v '^---$' | awk -F: '{print $1}' | sort)
    up_keys=$(get_frontmatter "$upstream_file" | grep -v '^---$' | awk -F: '{print $1}' | sort)
    if [ "$local_keys" != "$up_keys" ]; then
      echo "Warning: frontmatter keys diverge in $local_file — review manually." >&2
    fi

    get_frontmatter "$local_file" > "$out_file"
    get_body "$upstream_file"     >> "$out_file"
  else
    cp "$upstream_file" "$out_file"
  fi
}

# ---------------------------------------------------------------------------
# Main — only runs when this script is executed directly, not when sourced
# ---------------------------------------------------------------------------
main() {
  TAG="${AGENT_HARNESS_TAG:-main}"
  URL="${AGENT_HARNESS_URL:-https://github.com/dayfine/agent-harness.git}"
  LOCAL_UPSTREAM="${AGENT_HARNESS_UPSTREAM:-}"

  SYNCED=0
  SKIPPED=0

  # Temp dir used for clone; cleaned up on exit
  CLONE_DIR=""
  cleanup() { [ -n "$CLONE_DIR" ] && rm -rf "$CLONE_DIR"; }
  trap cleanup EXIT INT TERM

  # --- Resolve upstream directory ---
  if [ -n "$LOCAL_UPSTREAM" ]; then
    UPSTREAM_DIR="$(cd "$LOCAL_UPSTREAM" && pwd)"
    echo "Using local upstream: $UPSTREAM_DIR"
  else
    echo "Fetching upstream from $URL (ref: $TAG)..."
    CLONE_DIR="$(mktemp -d)"
    git clone -q --depth 1 -b "$TAG" "$URL" "$CLONE_DIR/upstream"
    UPSTREAM_DIR="$CLONE_DIR/upstream"
  fi

  # --- Collect reusable files (sorted for deterministic prompts) ---
  REUSABLE_FILES=""
  for d in ".agents/agents" ".agents/rules" ".github/workflows" "dev/lib"; do
    full_dir="$UPSTREAM_DIR/$d"
    [ -d "$full_dir" ] || continue
    found=$(find "$full_dir" -maxdepth 1 -type f \
              \( -name "*.md" -o -name "*.sh" -o -name "*.yml" \) 2>/dev/null | sort) || true
    for f in $found; do
      if has_reusable_tag "$f"; then
        rel=$(printf '%s' "$f" | sed "s|^$UPSTREAM_DIR/||")
        REUSABLE_FILES="$REUSABLE_FILES $rel"
      fi
    done
  done

  if [ -z "$(printf '%s' "$REUSABLE_FILES" | tr -d ' ')" ]; then
    echo "No reusable files found upstream."
    return
  fi

  # Scratch dir for merged files
  WORK_DIR="$(mktemp -d)"
  trap 'rm -rf "$WORK_DIR"; cleanup' EXIT INT TERM

  # --- Process each file ---
  for rel in $REUSABLE_FILES; do
    upstream_file="$UPSTREAM_DIR/$rel"

    # New file — doesn't exist locally
    if [ ! -f "$rel" ]; then
      printf '\nNew upstream file: %s\nCopy it to local? [y/N] ' "$rel"
      read -r choice
      case "$choice" in
        y|Y|yes|YES)
          mkdir -p "$(dirname "$rel")"
          cp "$upstream_file" "$rel"
          echo "Copied $rel."
          SYNCED=$((SYNCED + 1))
          ;;
        *)
          echo "Skipped $rel."
          SKIPPED=$((SKIPPED + 1))
          ;;
      esac
      continue
    fi

    # Build the merged candidate
    merged="$WORK_DIR/$(echo "$rel" | tr '/' '_')"
    build_merged "$rel" "$upstream_file" "$merged"

    # Skip if already in sync
    if diff -q "$rel" "$merged" > /dev/null 2>&1; then
      continue
    fi

    printf '\n--- Changes detected in %s ---\n' "$rel"
    diff -u "$rel" "$merged" || true

    while true; do
      printf '\nUpdate %s? [y/N/skip] ' "$rel"
      read -r choice
      case "$choice" in
        y|Y|yes|YES)
          cp "$merged" "$rel"
          echo "Updated $rel."
          SYNCED=$((SYNCED + 1))
          break
          ;;
        skip|SKIP)
          echo "Skipped $rel."
          SKIPPED=$((SKIPPED + 1))
          break
          ;;
        *)
          echo "Skipped $rel."
          SKIPPED=$((SKIPPED + 1))
          break
          ;;
      esac
    done
  done

  printf '\nSync complete. %d files updated, %d files skipped.\n' "$SYNCED" "$SKIPPED"
}

# Run main only when executed directly (not when sourced by tests).
# Tests set AGENT_HARNESS_SYNC_SOURCED=1 before sourcing this file.
if [ "${AGENT_HARNESS_SYNC_SOURCED:-0}" != "1" ]; then
  main "$@"
fi
