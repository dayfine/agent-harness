#!/bin/sh
# Unit tests for agent-harness-sync.sh pure helper functions.
#
# Sources the sync script (main() is not called when sourced).
# Run with: sh bin/test-agent-harness-sync.sh

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Signal that we are sourcing the script, not running it directly
AGENT_HARNESS_SYNC_SOURCED=1
export AGENT_HARNESS_SYNC_SOURCED
. "$SCRIPT_DIR/agent-harness-sync.sh"

PASS=0
FAIL=0
TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

assert_eq() {
  label="$1"; expected="$2"; actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label"
    printf '    expected: |%s|\n' "$expected"
    printf '    actual:   |%s|\n' "$actual"
    FAIL=$((FAIL + 1))
  fi
}

assert_true() {
  label="$1"; shift
  if "$@" 2>/dev/null; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label"
    FAIL=$((FAIL + 1))
  fi
}

assert_false() {
  label="$1"; shift
  if ! "$@" 2>/dev/null; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label"
    FAIL=$((FAIL + 1))
  fi
}

# -----------------------------------------------------------------------
echo "=== has_frontmatter ==="
# -----------------------------------------------------------------------

f="$TMPDIR_TEST/with_fm.md"
printf -- '---\nharness: reusable\n---\n\nBody.\n' > "$f"
assert_true  "file with frontmatter"   has_frontmatter "$f"

f="$TMPDIR_TEST/no_fm.md"
printf '# Heading\n\nNo frontmatter.\n' > "$f"
assert_false "file without frontmatter" has_frontmatter "$f"

f="$TMPDIR_TEST/malformed_fm.md"
printf -- '---\nharness: reusable\nno closing delimiter\n' > "$f"
assert_false "malformed frontmatter (no closing ---)" has_frontmatter "$f"

# -----------------------------------------------------------------------
echo "=== get_frontmatter ==="
# -----------------------------------------------------------------------

f="$TMPDIR_TEST/fm.md"
printf -- '---\nharness: reusable\n---\n\nBody text.\n' > "$f"
result=$(get_frontmatter "$f")
assert_eq "extracts frontmatter block" "---
harness: reusable
---" "$result"

# -----------------------------------------------------------------------
echo "=== get_body ==="
# -----------------------------------------------------------------------

f="$TMPDIR_TEST/body.md"
printf -- '---\nharness: reusable\n---\n\nBody line 1.\nBody line 2.\n' > "$f"
result=$(get_body "$f")
assert_eq "extracts body after frontmatter" "
Body line 1.
Body line 2." "$result"

# -----------------------------------------------------------------------
echo "=== trailing newline preservation ==="
# -----------------------------------------------------------------------

f="$TMPDIR_TEST/newline.md"
printf -- '---\nharness: reusable\n---\n\nBody.\n' > "$f"
fm=$(get_frontmatter "$f")
body=$(get_body "$f")
reassembled=$(printf '%s' "$fm"; printf '%s' "$body")
original=$(cat "$f")
# Command substitution strips trailing newlines, so test preservation via
# build_merged which writes to an actual file (no stripping occurs).
fm_file="$TMPDIR_TEST/fm_only.md"
body_file="$TMPDIR_TEST/body_only.md"
merged_nl="$TMPDIR_TEST/merged_nl.md"
printf -- '---\nharness: reusable\n---\n\nBody.\n' > "$f"
# build_merged with identical frontmatter: output should equal input
build_merged "$f" "$f" "$merged_nl"
orig_bytes=$(wc -c < "$f" | tr -d ' ')
merged_bytes=$(wc -c < "$merged_nl" | tr -d ' ')
assert_eq "build_merged preserves trailing newline" "$orig_bytes" "$merged_bytes"

# -----------------------------------------------------------------------
echo "=== has_reusable_tag ==="
# -----------------------------------------------------------------------

f="$TMPDIR_TEST/reusable.md"
printf -- '---\nharness: reusable\n---\n\nBody.\n' > "$f"
assert_true  "md with harness: reusable"         has_reusable_tag "$f"

f="$TMPDIR_TEST/project.md"
printf -- '---\nharness: project\n---\n\nBody.\n' > "$f"
assert_false "md with harness: project"          has_reusable_tag "$f"

f="$TMPDIR_TEST/no_tag.md"
printf -- '# Just a heading\n\nNo frontmatter.\n' > "$f"
assert_false "md with no frontmatter"            has_reusable_tag "$f"

f="$TMPDIR_TEST/workflow.yml"
printf '# harness: reusable\nname: My Workflow\n' > "$f"
assert_true  "yml with # harness: reusable"      has_reusable_tag "$f"

f="$TMPDIR_TEST/script.sh"
printf '#!/bin/sh\n# harness: reusable\necho hello\n' > "$f"
assert_true  "sh with # harness: reusable"       has_reusable_tag "$f"

f="$TMPDIR_TEST/no_tag.yml"
printf 'name: My Workflow\non: push\n' > "$f"
assert_false "yml without tag"                   has_reusable_tag "$f"

# -----------------------------------------------------------------------
echo "=== build_merged ==="
# -----------------------------------------------------------------------

local_file="$TMPDIR_TEST/local.md"
upstream_file="$TMPDIR_TEST/upstream.md"
out_file="$TMPDIR_TEST/merged.md"

printf -- '---\nharness: reusable\ncustom_field: my-value\n---\n\nOLD body.\n' > "$local_file"
printf -- '---\nharness: reusable\n---\n\nNEW body.\n'                         > "$upstream_file"
build_merged "$local_file" "$upstream_file" "$out_file"
result=$(cat "$out_file")

assert_eq "merged: local frontmatter preserved" "---
harness: reusable
custom_field: my-value
---

NEW body." "$result"

# No-frontmatter local: use upstream verbatim
local_file2="$TMPDIR_TEST/local_nofm.md"
out_file2="$TMPDIR_TEST/merged_nofm.md"
printf '# Heading\n\nOld content.\n' > "$local_file2"
build_merged "$local_file2" "$upstream_file" "$out_file2"
result2=$(cat "$out_file2")
expected2=$(cat "$upstream_file")
assert_eq "merged: no local frontmatter uses upstream verbatim" "$expected2" "$result2"

# -----------------------------------------------------------------------
echo ""
echo "Results: $PASS passed, $FAIL failed."
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
