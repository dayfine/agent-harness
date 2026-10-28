#!/bin/sh
# Offline tests for dev/lib/codex-review.sh and dev/lib/codex-push.sh.
# No network, no real codex: library functions are sourced with
# CODEX_REVIEW_LIB=1, and the end-to-end case runs against stub gh / codex.
#   sh bin/test-codex-review.sh
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); }
bad()  { FAIL=$((FAIL + 1)); echo "FAIL: $1"; }
check() { if eval "$2"; then ok; else bad "$1"; fi; }

CODEX_REVIEW_LIB=1 . "$ROOT/dev/lib/codex-review.sh"
unset CODEX_REVIEW_LIB  # some shells keep a prefix assignment on `.`
SHA=0123456789abcdef0123456789abcdef01234567

good() {
  cat > "$1" <<EOF
Reviewed SHA: $SHA
## Codex review — t
| # | Check | Status | Notes |
## Verdict
${2:-APPROVED}
EOF
}

good "$T/r1"
check "valid report passes" 'validate_report "$T/r1" "$SHA" 2>/dev/null'
good "$T/r2" NEEDS_REWORK
check "NEEDS_REWORK passes" 'validate_report "$T/r2" "$SHA" 2>/dev/null'
good "$T/r3"; sed -i.bak '1s/.*/Reviewed SHA: deadbeef/' "$T/r3"
check "wrong SHA fails" '! validate_report "$T/r3" "$SHA" 2>/dev/null'
good "$T/r4"; printf '## Structural QC\n' >> "$T/r4"
check "gate heading fails" '! validate_report "$T/r4" "$SHA" 2>/dev/null'
good "$T/r5" MAYBE
check "bad verdict token fails" '! validate_report "$T/r5" "$SHA" 2>/dev/null'
good "$T/r6"; printf '## Verdict\nNEEDS_REWORK\n' >> "$T/r6"
check "two Verdict headings fail" '! validate_report "$T/r6" "$SHA" 2>/dev/null'
good "$T/r7"; sed -i.bak 's/^## Codex review — t/## Review/' "$T/r7"
check "wrong first heading fails" '! validate_report "$T/r7" "$SHA" 2>/dev/null'
good "$T/r8"; printf '## Security QC\n' >> "$T/r8"
check "custom gate heading regex" '! CODEX_REVIEW_GATE_HEADINGS="security qc" validate_report "$T/r8" "$SHA" 2>/dev/null'

check "md only is docs-only" 'is_docs_only "$(printf "a.md\ndocs/b.md")"'
check "code is not docs-only" '! is_docs_only "$(printf "a.md\nsrc/x.ml")"'
check "empty list is not docs-only" '! is_docs_only ""'
check "custom globs" 'CODEX_REVIEW_DOCS_GLOBS="*.md notes/*" is_docs_only "$(printf "notes/x.txt\na.md")"'
check "glob chars do not expand" '(cd "$T" && touch zz.md && ! is_docs_only "src/*")'

d1=$(sample_draw 5 "$SHA"); d2=$(sample_draw 5 "$SHA")
check "draw is deterministic" '[ "$d1" = "$d2" ]'
check "p=1 always samples" 'should_sample 5 "$SHA" 1'
check "p=0 never samples" '! should_sample 5 "$SHA" 0'

L="$T/log/r.log"
check "absent log counts 0" '[ "$(daily_count "$L")" = 0 ]'
record_run "$L" 5 "$SHA"; record_run "$L" 6 "$SHA"
finish_run "$L" 5 "$SHA" "in=1 out=2"
check "finish_run completes the line" 'grep -qx "5 $SHA in=1 out=2" "$L"'
check "count unchanged by finish_run" '[ "$(daily_count "$L")" = 2 ]'
printf '%s\n' '{"type":"turn.completed","usage":{"input_tokens":10,"cached_input_tokens":4,"output_tokens":3,"reasoning_output_tokens":1}}' 'noise' > "$T/ev"
check "usage summed" '[ "$(usage_fields "$T/ev")" = "in=10 cached=4 out=3 reasoning=1" ]'
printf '{"type":"error"}\n' > "$T/ev2"
check "no usage is na, not zero" '[ "$(usage_fields "$T/ev2")" = "tokens=na events=1" ]'

printf 'Check FOO_RULE.\n' > "$T/add"
build_prompt 5 "$SHA" t o/r origin/main "$T/add" > "$T/p"
check "prompt pins the SHA" 'grep -q "detached checkout of exactly $SHA" "$T/p"'
check "prompt uses the base" 'grep -q "git diff origin/main...HEAD" "$T/p"'
check "prompt carries the addendum" 'grep -q FOO_RULE "$T/p"'

# --- end to end against stubs: a git repo, stub gh and codex on PATH ---
R="$T/repo"; B="$T/bin"; mkdir -p "$R/dev/lib" "$B"
cp "$ROOT/dev/lib/codex-review.sh" "$R/dev/lib/"
git -C "$R" init -q -b main && git -C "$R" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
HEAD_SHA=$(git -C "$R" rev-parse HEAD)
git -C "$R" remote add origin "$R"
git -C "$R" update-ref refs/pull/7/head "$HEAD_SHA"
cat > "$B/gh" <<EOF
#!/bin/sh
case "\$*" in
  *"pr view"*) echo '{"headRefOid":"$HEAD_SHA","title":"t","files":[{"path":"src/x.ml"}],"labels":[]}' ;;
  *"api -X POST"*) echo "\$*" > "$T/posted"; echo 99 ;;
  *) echo "unexpected gh \$*" >&2; exit 1 ;;
esac
EOF
cat > "$B/codex" <<EOF
#!/bin/sh
echo "\$*" > "$T/codex-args"
while [ \$# -gt 0 ]; do [ "\$1" = -o ] && out=\$2; shift; done
printf 'Reviewed SHA: %s\n## Codex review — t\n## Verdict\nAPPROVED\n' "$HEAD_SHA" > "\$out"
echo '{"type":"turn.completed","usage":{"input_tokens":5,"output_tokens":2}}'
EOF
chmod +x "$B/gh" "$B/codex"
run() { (cd "$R" && PATH="$B:$PATH" CODEX_REVIEW_REPO=o/r CODEX_REVIEW_BASE=origin/main REPORT_DIR="$T/rep" sh dev/lib/codex-review.sh "$@"); }
check "e2e posts" 'run 7 --force >"$T/out" 2>&1 && grep -q "posted review 99" "$T/out"'
check "codex ran read-only" 'grep -q -- "exec -s read-only --ephemeral" "$T/codex-args"'
check "post pinned to SHA" 'grep -q "commit_id=$HEAD_SHA" "$T/posted"'
check "worktree removed" '[ -z "$(ls "$R/.claude/worktrees" 2>/dev/null)" ]'
check "usage logged" 'grep -q "7 $HEAD_SHA in=5 cached=0 out=2" "$R"/dev/_tmp/codex/reviews-*.log'
check "reader disagreement blocks post" 'rm -f "$T/posted"; ! CODEX_REVIEW_READER="echo rework" run 7 --force >/dev/null 2>&1 && [ ! -f "$T/posted" ]'
check "off switch" 'CODEX_REVIEW=off run 7 | grep -q disabled'
check "cap holds" 'CODEX_REVIEW_MAX_PER_DAY=1 CODEX_REVIEW_SAMPLE=1 run 7 | grep -q "daily cap"'

# --- codex-push.sh ---
P="$ROOT/dev/lib/codex-push.sh"
check "push refuses args" '! (cd "$R" && sh "$P" origin 2>/dev/null)'
check "push refuses non-codex branch" '! (cd "$R" && CODEX_PUSH_DRY_RUN=1 sh "$P" 2>/dev/null)'
git -C "$R" switch -q -c codex/1-x
check "push dry-runs codex branch" '[ "$(cd "$R" && CODEX_PUSH_DRY_RUN=1 sh "$P")" = "git push -u origin HEAD:refs/heads/codex/1-x" ]'

echo "codex-review tests: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
