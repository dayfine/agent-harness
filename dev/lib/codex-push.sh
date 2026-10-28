#!/bin/sh
# harness: reusable
# codex-push.sh — the only push Codex should run: publishes the current codex/*
# branch to origin, nothing else. Point Codex at it in AGENTS.md and deny raw
# `git push` in .codex/rules (see .claude/skills/codex-dispatch/SKILL.md).
# No refspec/remote arguments: publish only the current Codex branch to origin.
set -eu
refuse() { printf 'codex-push: %s\n' "$1" >&2; exit 1; }
[ "$#" -eq 0 ] || refuse 'takes no arguments'
branch=$(git symbolic-ref --quiet --short HEAD) || refuse 'requires an attached branch'
case "$branch" in
  codex/?*) ;;
  *) refuse 'current branch must start with codex/' ;;
esac
git check-ref-format "refs/heads/$branch" >/dev/null || refuse 'invalid branch ref'
case "${CODEX_PUSH_DRY_RUN:-0}" in
  1) printf 'git push -u origin HEAD:refs/heads/%s\n' "$branch" ;;
  0) git push -u origin "HEAD:refs/heads/$branch" ;;
  *) refuse 'CODEX_PUSH_DRY_RUN must be 0 or 1' ;;
esac
