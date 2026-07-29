#!/usr/bin/env bash
# drive-build.sh — the universal headless loop for orchestrate-build.
#
# The loop is deterministic control flow (no LLM context, so nothing rots). Each iteration invokes a FRESH
# top-level agent process to execute exactly ONE unit of the build (SETUP, the single next ticket via
# implement-spec, or CAPSTONE), which updates the durable ledger and exits. The loop re-reads the ledger and
# repeats until DONE / BLOCKED / paused. Intelligence stays in fresh contexts; sequencing stays here.
#
# Harness-agnostic: the ONLY harness-specific atom is the headless-invocation command, discovered from PATH or
# passed with --agent-cmd. Works with Claude Code, Goose, Codex CLI, Gemini CLI, or any CLI that runs a prompt
# non-interactively and exits.
#
# Usage:
#   drive-build.sh --ledger <path> [--agent-cmd "claude -p"] [--max-iters 100] [--worktree <path>]
#
# Exit codes: 0 = DONE or cleanly paused; 2 = BLOCKED (human needed); 3 = iteration cap hit; 1 = usage/error.

set -euo pipefail

LEDGER="" ; AGENT_CMD="" ; MAX_ITERS=100 ; WORKTREE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --ledger)    LEDGER="$2"; shift 2 ;;
    --agent-cmd) AGENT_CMD="$2"; shift 2 ;;
    --max-iters) MAX_ITERS="$2"; shift 2 ;;
    --worktree)  WORKTREE="$2"; shift 2 ;;
    -h|--help)   grep -E '^# ' "$0" | sed 's/^# //'; exit 0 ;;
    *) echo "drive-build.sh: unknown arg: $1" >&2; exit 1 ;;
  esac
done

[ -n "$LEDGER" ] && [ -f "$LEDGER" ] || { echo "drive-build.sh: --ledger <existing file> required" >&2; exit 1; }

# Read a `key: value` line from the ledger's CURRENT STATE block; strips inline comments and whitespace.
status_val() { grep -m1 "^${1}:" "$LEDGER" | sed "s/^${1}:[[:space:]]*//; s/[[:space:]]*#.*//; s/[[:space:]]*$//"; }

# Discover the headless agent command if not supplied. Each entry is "<binary>|<full invocation>".
if [ -z "$AGENT_CMD" ]; then
  for cand in "claude|claude -p" "goose|goose run -t" "codex|codex exec" "gemini|gemini -p"; do
    bin="${cand%%|*}"; inv="${cand##*|}"
    if command -v "$bin" >/dev/null 2>&1; then AGENT_CMD="$inv"; break; fi
  done
fi
[ -n "$AGENT_CMD" ] || { echo "drive-build.sh: no headless agent CLI found on PATH; pass --agent-cmd, or use dispatch=subagent/manual" >&2; exit 1; }

# Default the worktree from the ledger if not overridden; run every agent invocation there.
[ -n "$WORKTREE" ] || WORKTREE="$(status_val buildWorktree || true)"

echo "drive-build: ledger=$LEDGER  agent='$AGENT_CMD'  max-iters=$MAX_ITERS"

for ((i = 1; i <= MAX_ITERS; i++)); do
  STATUS="$(status_val projectStatus)"
  NEXT="$(status_val nextTicket)"
  PAUSED="$(status_val pauseRequested)"
  BLOCKED="$(status_val blockedOn)"

  case "$STATUS" in
    DONE) echo "drive-build: projectStatus=DONE — build complete."; exit 0 ;;
    BLOCKED) echo "drive-build: projectStatus=BLOCKED (blockedOn: $BLOCKED) — human needed."; exit 2 ;;
  esac
  if [ "$PAUSED" = "true" ]; then echo "drive-build: pauseRequested=true — stopping at ticket boundary."; exit 0; fi
  case "$BLOCKED" in ""|"(nothing)"|"none"|"(none)") : ;; *) echo "drive-build: blockedOn='$BLOCKED' — human needed."; exit 2 ;; esac
  [ -n "$NEXT" ] || { echo "drive-build: could not read nextTicket from ledger." >&2; exit 1; }

  echo "── iter $i/$MAX_ITERS · unit: $NEXT ─────────────────────────────"

  # Fresh top-level session, exactly ONE unit, then exit. Continuation is THIS loop, not the agent.
  PROMPT="You are a fresh session with no memory of prior sessions. Follow skills/orchestrate-build/SKILL.md \
against the build ledger at '$LEDGER'. Execute EXACTLY ONE unit — the one named by nextTicket ('$NEXT'): if \
SETUP, run the SETUP checklist; if a ticket id, run that single ticket end-to-end by invoking implement-spec \
per the ticket's contract; if CAPSTONE, run the capstone checklist. Update the ledger (advance CURRENT STATE, \
append a PHASE LOG entry) and then STOP. Do NOT proceed to any further unit — the external loop does that. \
Never fabricate green: on any block, set blockedOn in the ledger and stop."

  if [ -n "$WORKTREE" ] && [ -d "$WORKTREE" ]; then
    ( cd "$WORKTREE" && $AGENT_CMD "$PROMPT" )   # word-split $AGENT_CMD intentionally (e.g. "claude -p")
  else
    $AGENT_CMD "$PROMPT"
  fi

  # Guard against a no-progress spin: if nextTicket didn't move and we're not intentionally paused/blocked, stop.
  if [ "$(status_val nextTicket)" = "$NEXT" ] && [ "$(status_val projectStatus)" = "$STATUS" ]; then
    echo "drive-build: no ledger progress after unit '$NEXT' — stopping to avoid a spin. Inspect the ledger." >&2
    exit 2
  fi
done

echo "drive-build: hit --max-iters=$MAX_ITERS without reaching DONE. Re-run to continue." >&2
exit 3
