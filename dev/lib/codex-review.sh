#!/bin/sh
# harness: reusable
# codex-review.sh — run an ADVISORY Codex review of one PR and post it as a
# COMMENTED PR review whose first heading is "## Codex review — <title>".
#
# Codex is a second reviewer with a different failure profile; the merge
# decision stays with the project's own gates. So this script keeps Codex in
# the advisory seat:
#   - Codex runs `codex exec -s read-only --ephemeral` in a detached worktree
#     pinned to the PR head SHA (it cannot push, post or edit);
#   - the controller (this script) validates the report's shape and posts it;
#   - a report carrying a gate heading (default: Structural/Behavioral QC) is
#     refused, so an advisory review can never read as a gate verdict.
#
#   sh dev/lib/codex-review.sh <PR> [--no-post] [--dry-run] [--force]
#     --no-post   run and validate, print the report path, do not post
#     --dry-run   print the prompt and exit (no codex call)
#     --force     skip the sampling draw and the daily cap
#
# Settings: environment, else dev/codex-review.env (project layer, sourced if
# present; plain KEY=value lines), else the defaults below.
#   CODEX_REVIEW=off                 do nothing, exit 0 (the off switch)
#   CODEX_REVIEW_REPO                owner/repo (default: gh repo view)
#   CODEX_REVIEW_BASE                diff base ref (default: origin/<default branch>)
#   CODEX_REVIEW_SAMPLE              probability a call reviews (default 0.25)
#   CODEX_REVIEW_MAX_PER_DAY         daily cap on live runs (default 3)
#   CODEX_REVIEW_LOG_DIR             run log dir (default dev/_tmp/codex; keep it gitignored)
#   CODEX_REVIEW_WORKTREE_DIR        where the detached checkout goes (default .claude/worktrees)
#   CODEX_REVIEW_DOCS_GLOBS          space-separated case patterns; a PR whose every
#                                    path matches is skipped (default "*.md")
#   CODEX_REVIEW_PROMPT_ADDENDUM     file appended to the prompt: what to look for in
#                                    this repo (default .codex/review-prompt.md if present)
#   CODEX_REVIEW_GATE_HEADINGS       ERE of headings Codex must never use
#                                    (default "(qc[- ])?(structural|behavioral)")
#   CODEX_REVIEW_READER              optional command; called as `<cmd> REPORT SHA`, must
#                                    print the verdict the project's status reader sees
#                                    (ok | rework). Posting needs it to agree with the report.
#   CODEX_MODEL                      optional model override (-m)
#   REPORT_DIR                       where reports land (default /tmp)
#
# Labels (optional): review/codex-requested bypasses sampling;
# review/codex-required bypasses sampling and the cap.
#
# Budget: the draw is deterministic in "PR:SHA" (same tip, same answer), so the
# dispatcher may call this on every PR and let the script decide. Each live run
# appends "PR SHA in= cached= out= reasoning= wall=" to reviews-<date>.log (or
# "tokens=na events=N" when no turn completed, e.g. a quota hit). Pace hand-offs
# with dev/lib/codex-quota.sh first.
#
# Report shape (validated before posting):
#   line 1      : Reviewed SHA: <full head sha>
#   1st heading : ## Codex review — <PR title>
#   one         : ## Verdict, next non-blank line APPROVED | NEEDS_REWORK
#
# Needs gh (authenticated), jq, git, codex.
set -eu

# --- Library (sourced by bin/test-codex-review.sh with CODEX_REVIEW_LIB=1) ---

# validate_report FILE SHA -> 0 if the report has the advisory shape, else 1
# with one "codex-review: ..." line per defect on stderr.
validate_report() {
  _f=$1; _sha=$2; _bad=0
  _first=$(sed -n '1p' "$_f")
  if [ "$_first" != "Reviewed SHA: $_sha" ]; then
    echo "codex-review: first line must be 'Reviewed SHA: $_sha' (got: $_first)" >&2; _bad=1
  fi
  _heading=$(grep -m1 '^#\{1,4\} ' "$_f" || true)
  case "$_heading" in
    "## Codex review "*) ;;
    *) echo "codex-review: first heading must start with '## Codex review ' (got: $_heading)" >&2; _bad=1 ;;
  esac
  if grep -qiE "^#{1,4} +${CODEX_REVIEW_GATE_HEADINGS:-(qc[- ])?(structural|behavioral)}\b" "$_f"; then
    echo "codex-review: report carries a gate heading; refusing to post" >&2; _bad=1
  fi
  if [ "$(grep -cE '^#+ +Verdict[ :]*\r?$' "$_f")" != 1 ]; then
    echo "codex-review: exactly one '## Verdict' heading required" >&2; _bad=1
  fi
  _v=$(verdict_token "$_f")
  case "$_v" in
    APPROVED|NEEDS_REWORK) ;;
    *) echo "codex-review: '## Verdict' must be followed by APPROVED or NEEDS_REWORK (got: ${_v:-<none>})" >&2; _bad=1 ;;
  esac
  return $_bad
}

# verdict_token FILE -> the first non-blank line after the Verdict heading.
verdict_token() {
  awk 'f && NF {print; exit} /^#+ +Verdict[ :]*\r?$/ {f=1}' "$1" | tr -d ' \r'
}

# is_docs_only "<paths, one per line>" -> 0 when every path matches one of
# CODEX_REVIEW_DOCS_GLOBS; an advisory review of prose is wasted work.
is_docs_only() {
  _globs=${CODEX_REVIEW_DOCS_GLOBS:-*.md}
  [ -n "$1" ] || return 1
  set -f
  for _p in $1; do
    _hit=1
    for _g in $_globs; do
      # shellcheck disable=SC2254
      case "$_p" in $_g) _hit=0; break ;; esac
    done
    [ "$_hit" = 0 ] || { set +f; return 1; }
  done
  set +f
  return 0
}

# sample_draw PR SHA -> integer 0..9999, deterministic in (PR, SHA).
sample_draw() {
  printf '%s:%s' "$1" "$2" | cksum | awk '{ print $1 % 10000 }'
}
# should_sample PR SHA P -> 0 when this tip is in the sample (draw/10000 < P).
should_sample() {
  _d=$(sample_draw "$1" "$2")
  awk -v d="$_d" -v p="$3" 'BEGIN { exit !(d / 10000 < p + 0) }'
}
daily_count() { if [ -f "$1" ]; then grep -c . "$1"; else echo 0; fi; }
record_run() { mkdir -p "$(dirname "$1")" && printf '%s %s\n' "$2" "$3" >> "$1"; }
has_label() { printf '%s\n' "$1" | grep -qx "$2"; }

# usage_fields EVENTS -> token usage summed over turn.completed events of a
# `codex exec --json` stream; "tokens=na events=N" when none completed.
usage_fields() {
  [ -f "$1" ] || { echo "tokens=na events=0"; return 0; }
  jq -Rrs '
    [split("\n")[] | fromjson? | select(type == "object")] as $ev
    | [$ev[] | select(.type == "turn.completed" and (.usage | type) == "object") | .usage] as $u
    | if ($u | length) == 0 then "tokens=na events=\($ev | length)"
      else "in=\([$u[].input_tokens // 0] | add) cached=\([$u[].cached_input_tokens // 0] | add) out=\([$u[].output_tokens // 0] | add) reasoning=\([$u[].reasoning_output_tokens // 0] | add)"
      end' "$1"
}

# finish_run LOG PR SHA FIELDS -> completes the last "PR SHA" line of LOG.
finish_run() {
  [ -f "$1" ] || return 0
  _n=$(awk -v k="$2 $3" '$0 == k { n = NR } END { print n + 0 }' "$1")
  [ "$_n" -gt 0 ] || return 0
  awk -v n="$_n" -v f="$4" 'NR == n { $0 = $0 " " f } { print }' "$1" > "$1.tmp.$$" && mv "$1.tmp.$$" "$1"
}

# build_prompt PR SHA TITLE REPO BASE ADDENDUM_FILE -> the prompt on stdout.
# Everything is pinned to the detached checkout at SHA, never the live PR, so
# a push during the review cannot change what "Reviewed SHA" vouches for.
build_prompt() {
  cat <<PEOF
Review PR #$1 (head $2, title: $3) of $4 as an independent ADVISORY reviewer.
You are in a detached checkout of exactly $2. Read ONLY that checkout: the change is
'git diff $5...HEAD' and the file list is 'git diff --name-only $5...HEAD'
(do not use 'gh pr diff' or 'gh pr view': the live PR may have moved past this revision).
Look for: correctness defects, missing or weak tests for claims the diff makes, and drift
between docs / commit messages and the code. Read the repo's agent instructions
(AGENTS.md, CLAUDE.md and the rules they point to) and flag violations.
Do not run long builds, do not modify files, do not commit, push or post to GitHub.
PEOF
  if [ -n "$6" ] && [ -f "$6" ]; then
    echo; echo "Repository-specific review focus:"; cat "$6"; echo
  fi
  cat <<PEOF
Report format (machine-parsed; follow exactly):
  line 1: Reviewed SHA: $2
  first heading: ## Codex review — $3
  then a findings table (| # | Check | Status | Notes |), a '## Quality Score' (1-5),
  exactly ONE '## Verdict' heading whose next line is exactly APPROVED or NEEDS_REWORK
  (never inside a code fence, never repeated), and '## NEEDS_REWORK Items'
  (Finding / Location / Required fix) when applicable.
Never use the headings 'Structural QC', 'Behavioral QC' or 'qc-...': those name the
project's merge gates, and your review is advisory, not a gate.
PEOF
}

[ "${CODEX_REVIEW_LIB:-}" = 1 ] && return 0

# --- Main ---

ROOT=$(git rev-parse --show-toplevel)
# shellcheck disable=SC1091
[ -f "$ROOT/dev/codex-review.env" ] && . "$ROOT/dev/codex-review.env"

if [ "${CODEX_REVIEW:-on}" = off ]; then
  echo "codex-review: disabled (CODEX_REVIEW=off); nothing done"; exit 0
fi

PR=""; POST=1; DRY=0; FORCE=0
for a in "$@"; do
  case "$a" in
    --no-post) POST=0 ;;
    --dry-run) DRY=1 ;;
    --force)   FORCE=1 ;;
    -*) echo "codex-review: unknown flag $a" >&2; exit 2 ;;
    *) PR=$a ;;
  esac
done
[ "$DRY" = 0 ] || FORCE=1  # a dry run shows the prompt whatever the draw says
[ -n "$PR" ] || { echo "usage: sh dev/lib/codex-review.sh <PR> [--no-post] [--dry-run] [--force]" >&2; exit 2; }
for t in gh jq git; do
  command -v "$t" >/dev/null 2>&1 || { echo "codex-review: $t not on PATH" >&2; exit 2; }
done
[ "$DRY" = 1 ] || command -v codex >/dev/null 2>&1 || { echo "codex-review: codex not on PATH" >&2; exit 2; }

REPO=${CODEX_REVIEW_REPO:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}
BASE=${CODEX_REVIEW_BASE:-origin/$(gh repo view "$REPO" --json defaultBranchRef --jq .defaultBranchRef.name)}
ADDENDUM=${CODEX_REVIEW_PROMPT_ADDENDUM:-$ROOT/.codex/review-prompt.md}
META=$(gh pr view "$PR" --repo "$REPO" --json headRefOid,title,files,labels)
SHA=$(printf '%s' "$META" | jq -r .headRefOid)
TITLE=$(printf '%s' "$META" | jq -r .title)
FILES=$(printf '%s' "$META" | jq -r '.files[].path')
LABELS=$(printf '%s' "$META" | jq -r '.labels[].name')

if is_docs_only "$FILES"; then
  echo "codex-review: PR #$PR is docs-only; no advisory review"; exit 0
fi
RUN_LOG="${CODEX_REVIEW_LOG_DIR:-$ROOT/dev/_tmp/codex}/reviews-$(date +%F).log"
SAMPLE_P=${CODEX_REVIEW_SAMPLE:-0.25}; CAP=${CODEX_REVIEW_MAX_PER_DAY:-3}
if [ "$FORCE" = 0 ] && ! has_label "$LABELS" review/codex-requested && ! has_label "$LABELS" review/codex-required; then
  if ! should_sample "$PR" "$SHA" "$SAMPLE_P"; then
    echo "codex-review: PR #$PR at $SHA sampled out (p=$SAMPLE_P); --force or a review/codex-* label overrides"; exit 0
  fi
fi
if [ "$FORCE" = 0 ] && ! has_label "$LABELS" review/codex-required && [ "$(daily_count "$RUN_LOG")" -ge "$CAP" ]; then
  echo "codex-review: daily cap reached ($CAP live runs in $RUN_LOG); --force or review/codex-required overrides"; exit 0
fi

RUN_DIR="${REPORT_DIR:-/tmp}/codex-review-pr-$PR-$$"
mkdir -p "$RUN_DIR"
REPORT="$RUN_DIR/report-$SHA.md"
PROMPT="$RUN_DIR/prompt.txt"
build_prompt "$PR" "$SHA" "$TITLE" "$REPO" "$BASE" "$ADDENDUM" > "$PROMPT"
if [ "$DRY" = 1 ]; then cat "$PROMPT"; exit 0; fi

WT="$ROOT/${CODEX_REVIEW_WORKTREE_DIR:-.claude/worktrees}/codex-review-pr-$PR-$$"
cleanup() { git -C "$ROOT" worktree remove --force "$WT" >/dev/null 2>&1 || true; git -C "$ROOT" worktree prune >/dev/null 2>&1 || true; }
trap cleanup EXIT INT TERM
git -C "$ROOT" fetch -q origin "pull/$PR/head" "${BASE#origin/}"
git -C "$ROOT" worktree add --detach "$WT" "$SHA" >/dev/null
record_run "$RUN_LOG" "$PR" "$SHA"

MODEL_ARGS=""; [ -n "${CODEX_MODEL:-}" ] && MODEL_ARGS="-m $CODEX_MODEL"
T0=$(date +%s); RC=0
# -s read-only is explicit so a user config with workspace-write cannot make
# the reviewer writable. Plain `codex exec`, not `codex exec review`: the latter
# refuses a custom prompt alongside --base.
# shellcheck disable=SC2086
codex -C "$WT" exec -s read-only --ephemeral --json $MODEL_ARGS -o "$REPORT" "$(cat "$PROMPT")" \
  >"$REPORT.events.jsonl" 2>"$REPORT.stderr" || RC=$?
finish_run "$RUN_LOG" "$PR" "$SHA" "$(usage_fields "$REPORT.events.jsonl") wall=$(( $(date +%s) - T0 ))s"
[ "$RC" = 0 ] || { echo "codex-review: codex exec failed (stderr in $REPORT.stderr)" >&2; exit 1; }

validate_report "$REPORT" "$SHA" || { echo "codex-review: report at $REPORT did not validate; NOT posted" >&2; exit 1; }
if [ -n "${CODEX_REVIEW_READER:-}" ]; then
  case "$(verdict_token "$REPORT")" in APPROVED) want=ok ;; *) want=rework ;; esac
  got=$($CODEX_REVIEW_READER "$REPORT" "$SHA" || true)
  [ "$got" = "$want" ] || { echo "codex-review: the project reader reads '$got', the report says '$want'; NOT posted ($REPORT)" >&2; exit 1; }
fi
echo "codex-review: report validated: $REPORT"
[ "$POST" = 1 ] || { echo "codex-review: --no-post; not posted"; exit 0; }
# Captured, not piped: under POSIX sh a pipe returns the last command's status,
# so a failed post would exit 0.
ID=$(gh api -X POST "repos/$REPO/pulls/$PR/reviews" -f event=COMMENT -f commit_id="$SHA" -F body=@"$REPORT" --jq .id) \
  || { echo "codex-review: POST failed; report at $REPORT" >&2; exit 1; }
[ -n "$ID" ] || { echo "codex-review: POST returned no id; report at $REPORT" >&2; exit 1; }
echo "codex-review: posted review $ID on PR #$PR at $SHA"
