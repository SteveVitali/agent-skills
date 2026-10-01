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
#   drive-build.sh --ledger <path> [--skill <name>] [--yolo] [--agent-cmd "<cmd>"]
#                  [--worktree <path>] [--log-dir <path>] [--max-iters <n>]
#                  [--no-ci-gate] [--ci-interval <s>] [--ci-max-wait <s>] [--print-prompt]
#
#   --ledger      Path to the seeded build ledger (required).
#   --skill       The driving skill each fresh unit follows (default: orchestrate-build). The
#                 prompt names this skill; e.g. --skill synthesize-spec drives docs/research-ledger.md
#                 (whose next-unit pointer is `nextUnit`) the same way. Resolved under the skills root.
#   --yolo        Enable UNATTENDED WRITES by appending the discovered CLI's autonomy flag. Off by default:
#                 without it, headless CLIs do not prompt — they silently DENY edits/commands, so a ticket makes
#                 no changes and the loop stops at the no-progress guard. Per-CLI mapping (auto-discovery only):
#                   claude -> --permission-mode bypassPermissions   goose  -> GOOSE_MODE=auto
#                   codex  -> --sandbox workspace-write --ask-for-approval never (workspace writes, no network)
#                   gemini -> --approval-mode yolo
#                 Prefer configuring autonomy out-of-band (settings allowlist, GOOSE_MODE, a scoped --agent-cmd)
#                 when you want a tighter posture than blanket bypass.
#   --agent-cmd   Override the invocation (e.g. "claude -p --permission-mode acceptEdits"). Must accept the
#                 prompt as a TRAILING POSITIONAL argument. With --agent-cmd you own the autonomy posture; --yolo
#                 is ignored.
#   --worktree    Directory to run each invocation in. Default: the ledger's buildWorktree.
#   --log-dir     Where per-unit agent output is captured. Default: <ledger-dir>/drive-build-logs/.
#   --max-iters   Safety cap on iterations (default 100). Re-run to continue past it.
#   --ci-gate     (default with --skill orchestrate-build) Before every dispatch — and before reporting
#                 DONE or a pause — read the CI of the last landed ticket's PR and its open ancestors
#                 with ci-boundary.sh (BM-CI-01). Not green (fail / pending after the wait / unknown)
#                 → exit 2, nothing dispatched. A repo that declares no CI reads `none-declared` and
#                 passes. Other --skill ledgers (research rows, no PRs) default to off; --ci-gate
#                 forces it on.
#   --no-ci-gate  Explicit opt-out of that gate (printed in the log header). The prose rule still binds.
#   --ci-interval / --ci-max-wait  Poll interval and bounded wait passed to ci-boundary.sh
#                 (default 60 / 2700 seconds).
#   --print-prompt  The manual tier (a harness with no headless CLI): run the same checks (status enum,
#                 block, pause, CI gate), then print the fresh-session prompt for the next unit and exit
#                 0 without dispatching. Paste it into a new session of any harness; re-run after the unit.
#
# Exit codes: 0 = DONE, cleanly paused, gate-pending, or (--print-prompt) prompt printed;
#             2 = BLOCKED / off-enum projectStatus / CI not green / no-progress (human needed);
#             3 = iteration cap; 1 = usage.
#
# Compatible with bash 3.2+ (macOS default): C-style for-loops and indexed arrays only — no
# associative arrays, no mapfile/readarray.

set -euo pipefail

LEDGER="" ; AGENT_CMD="" ; MAX_ITERS=100 ; WORKTREE="" ; LOG_DIR="" ; YOLO=0 ; SKILL_NAME="orchestrate-build"
CI_GATE=auto ; CI_INTERVAL=60 ; CI_MAX_WAIT=2700 ; PRINT_PROMPT=0

usage() { grep -E '^#( |$)' "$0" | sed -E 's/^# ?//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --ledger)    LEDGER="${2:-}"; shift 2 ;;
    --skill)     SKILL_NAME="${2:-}"; shift 2 ;;
    --agent-cmd) AGENT_CMD="${2:-}"; shift 2 ;;
    --max-iters) MAX_ITERS="${2:-}"; shift 2 ;;
    --worktree)  WORKTREE="${2:-}"; shift 2 ;;
    --log-dir)   LOG_DIR="${2:-}"; shift 2 ;;
    --yolo)      YOLO=1; shift ;;
    --ci-gate)   CI_GATE=1; shift ;;
    --no-ci-gate) CI_GATE=0; shift ;;
    --ci-interval) CI_INTERVAL="${2:-}"; shift 2 ;;
    --ci-max-wait) CI_MAX_WAIT="${2:-}"; shift 2 ;;
    --print-prompt) PRINT_PROMPT=1; shift ;;
    -h|--help)   usage; exit 0 ;;
    *) echo "drive-build.sh: unknown arg: $1 (try --help)" >&2; exit 1 ;;
  esac
done

[ -n "$LEDGER" ] && [ -f "$LEDGER" ] || { echo "drive-build.sh: --ledger <existing file> required" >&2; exit 1; }
LEDGER="$(cd "$(dirname "$LEDGER")" && pwd)/$(basename "$LEDGER")"   # absolutize

# Absolute skills root, derived from this script's own location, so a fresh worker running in ANOTHER repo's
# worktree can still find the skill files (repo-relative "skills/..." paths would not resolve there).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DRIVER_SKILL="$SKILLS_ROOT/$SKILL_NAME/SKILL.md"
[ -f "$DRIVER_SKILL" ] || echo "drive-build.sh: warning: $SKILL_NAME SKILL not found at $DRIVER_SKILL" >&2

# Never-fail ledger reader: prints the value or empty; tolerates leading whitespace + trailing inline comments.
# (Must not fail under `set -e`: a missing key is normal, not an error.)
status_val() {
  local line
  line="$(grep -m1 -E "^[[:space:]]*${1}:" "$LEDGER" 2>/dev/null)" || true
  [ -n "$line" ] || return 0
  printf '%s\n' "$line" | sed -E "s/^[[:space:]]*${1}:[[:space:]]*//; s/[[:space:]]*#.*$//; s/[[:space:]]*$//"
}

# Build the base agent argv (everything up to, but not including, the trailing prompt).
BASE_ARGV=() ; AUTONOMY_NOTE=""
if [ "$PRINT_PROMPT" -eq 1 ]; then
  BASE_ARGV=(manual)                                  # no agent CLI: the operator starts the session
elif [ -n "$AGENT_CMD" ]; then
  read -r -a BASE_ARGV <<< "$AGENT_CMD"
  [ "$YOLO" -eq 1 ] && echo "drive-build.sh: note: --yolo is ignored with --agent-cmd; bake autonomy into your command." >&2
elif command -v claude >/dev/null 2>&1; then
  BASE_ARGV=(claude -p) ; AUTONOMY_NOTE="--permission-mode bypassPermissions"
  [ "$YOLO" -eq 1 ] && BASE_ARGV+=(--permission-mode bypassPermissions)
elif command -v goose >/dev/null 2>&1; then
  BASE_ARGV=(goose run --no-session -q) ; AUTONOMY_NOTE="GOOSE_MODE=auto"
  [ "$YOLO" -eq 1 ] && BASE_ARGV=(env GOOSE_MODE=auto "${BASE_ARGV[@]}")
  BASE_ARGV+=(-t)                                     # goose takes the prompt after -t
elif command -v codex >/dev/null 2>&1; then
  BASE_ARGV=(codex exec) ; AUTONOMY_NOTE="--sandbox workspace-write --ask-for-approval never"
  [ "$YOLO" -eq 1 ] && BASE_ARGV+=(--sandbox workspace-write --ask-for-approval never)
elif command -v gemini >/dev/null 2>&1; then
  BASE_ARGV=(gemini) ; AUTONOMY_NOTE="--approval-mode yolo"
  [ "$YOLO" -eq 1 ] && BASE_ARGV+=(--approval-mode yolo)
  BASE_ARGV+=(-p)                                     # gemini takes the prompt after -p
else
  echo "drive-build.sh: no supported agent CLI (claude|goose|codex|gemini) on PATH; pass --agent-cmd" >&2
  exit 1
fi

if [ "$PRINT_PROMPT" -ne 1 ] && [ "$YOLO" -ne 1 ] && [ -z "$AGENT_CMD" ]; then
  echo "drive-build.sh: WARNING — running WITHOUT --yolo. In headless mode these CLIs do not prompt; they" >&2
  echo "  silently DENY writes/commands, so tickets make no changes and the loop will stop at the no-progress" >&2
  echo "  guard. Enable unattended writes with --yolo (auto-maps to: ${AUTONOMY_NOTE}), or configure autonomy" >&2
  echo "  out-of-band and re-run." >&2
fi

[ -n "$WORKTREE" ] || WORKTREE="$(status_val buildWorktree)"
if [ -z "$LOG_DIR" ]; then
  LDIR="$(dirname "$LEDGER")"
  # Committed mode: logs belong under docs/build/logs/ (the one gitignored subtree), not beside the ledger.
  if [ -f "$LDIR/README.md" ] && grep -qF '<!-- build-memory: v2 -->' "$LDIR/README.md" 2>/dev/null; then
    LOG_DIR="$LDIR/logs/drive-build"
  else
    LOG_DIR="$LDIR/drive-build-logs"
  fi
fi
mkdir -p "$LOG_DIR"

if [ "$PRINT_PROMPT" -ne 1 ]; then
  # Single-driver lock (atomic mkdir), auto-released on exit — two loops on one ledger would corrupt state.
  LOCK="${LEDGER}.drive-lock"
  if ! mkdir "$LOCK" 2>/dev/null; then
    echo "drive-build.sh: another driver holds the lock ($LOCK). If it is stale, remove it and retry." >&2
    exit 1
  fi
  trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT
fi

if [ "$CI_GATE" = "auto" ]; then
  if [ "$SKILL_NAME" = "orchestrate-build" ]; then CI_GATE=1; CI_NOTE="on"
  else CI_GATE=0; CI_NOTE="off (--skill $SKILL_NAME has no PR boundaries; --ci-gate forces it)"; fi
elif [ "$CI_GATE" -eq 1 ]; then CI_NOTE="on"
else CI_NOTE="OFF (explicit opt-out --no-ci-gate)"; fi
LEDGER_HARNESS="$(status_val harness)"
echo "drive-build: ledger=$LEDGER harness(ledger)=${LEDGER_HARNESS:-<not recorded>}"
echo "drive-build: agent=[${BASE_ARGV[*]}] yolo=$YOLO worktree=${WORKTREE:-<none>} logs=$LOG_DIR max-iters=$MAX_ITERS ci-gate=$CI_NOTE"

# CI gate (BM-CI-01): the loop itself refuses to dispatch past a red, pending or unreadable PR.
# Runs whenever lastCompleted names a ticket not yet verified in this run — so a restart re-reads it.
VERIFIED=""
ci_gate() {   # ci_gate <ticket id> → 0 green / none-declared / not applicable, else 1
  local json="$LOG_DIR/ci-$1.json" wt=()
  [ -n "$WORKTREE" ] && [ -d "$WORKTREE" ] && wt=(--worktree "$WORKTREE")
  if bash "$SCRIPT_DIR/ci-boundary.sh" --ledger "$LEDGER" --ticket "$1" --stack ${wt[@]+"${wt[@]}"} \
       --interval "$CI_INTERVAL" --max-wait "$CI_MAX_WAIT" --json "$json"; then
    return 0
  fi
  echo "drive-build: CI not green for $1 — next unit NOT dispatched ($json)." >&2
  echo "  Record the blockedOn line above in the ledger (or let the next fresh unit record it); the fix is a ticket" >&2
  echo "  (an insert or a return pass), or the operator's verbatim waiver in GATE DECISIONS. Never a relaxed test." >&2
  return 1
}

for ((i = 1; i <= MAX_ITERS; i++)); do
  STATUS="$(status_val projectStatus | awk '{print $1}')" ; NEXT="$(status_val nextTicket)"
  [ -n "$NEXT" ] || NEXT="$(status_val nextUnit)"          # synthesize-spec ledgers use nextUnit
  PAUSED="$(status_val pauseRequested)" ; BLOCKED="$(status_val blockedOn)" ; PREV_RP="$(status_val returnPass)"
  LAST="$(status_val lastCompleted | awk '{print $1}')"

  case "$STATUS" in
    NOT_STARTED|IN_PROGRESS|DONE|PAUSED) : ;;
    BLOCKED) echo "drive-build: projectStatus=BLOCKED (blockedOn: ${BLOCKED:-?}) — human needed."; exit 2 ;;
    *) echo "drive-build: projectStatus='$STATUS' is not in the BM-LEDGER-02 enum (NOT_STARTED | IN_PROGRESS | BLOCKED | PAUSED | DONE) — human needed: correct the value in CURRENT STATE and re-run."; exit 2 ;;
  esac
  case "$BLOCKED" in
    ""|"(nothing)"|"nothing"|"none"|"(none)") : ;;
    *) echo "drive-build: blockedOn='$BLOCKED' — human needed."; exit 2 ;;
  esac
  if [ "$CI_GATE" -eq 1 ] && [ -n "$LAST" ] && [ "$LAST" != "$VERIFIED" ]; then
    case "$LAST" in
      "(none)"|none|"(nothing)") : ;;
      *) ci_gate "$LAST" || exit 2; VERIFIED="$LAST" ;;
    esac
  fi
  case "$STATUS" in
    DONE)    echo "drive-build: projectStatus=DONE — build complete."; exit 0 ;;
    PAUSED)  echo "drive-build: projectStatus=PAUSED — gate pending / operator pause; answer in LEDGER.md and re-run."; exit 0 ;;
  esac
  [ "$PAUSED" = "true" ] && { echo "drive-build: pauseRequested=true — stopping at ticket boundary."; exit 0; }
  [ -n "$NEXT" ] || { echo "drive-build: cannot read nextTicket — is the ledger's CURRENT STATE intact?" >&2; exit 1; }

  if [ "$PRINT_PROMPT" -eq 1 ]; then
    TIER="manual"; CONTINUATION="the operator starts the next fresh session"
  else
    TIER="headless"; CONTINUATION="this external loop drives continuation"
    echo "── iter $i/$MAX_ITERS · unit: $NEXT ──────────────────────────────"
  fi

  LEDGER_HARNESS="$(status_val harness)"
  PROMPT="You are a fresh session with no memory of prior sessions. Follow the $SKILL_NAME skill at \
'$DRIVER_SKILL' (its sibling skills implement-spec, decompose-spec and build-memory are under '$SKILLS_ROOT'). \
Operate on the ledger at '$LEDGER'. Execute EXACTLY ONE unit — the one named by the ledger's next-unit pointer \
('$NEXT') — per that skill's instructions (for orchestrate-build: if SETUP, run the SETUP checklist; if a ticket \
id, run that single ticket end-to-end by invoking implement-spec against the ticket's contract). Then update the \
ledger (advance CURRENT STATE, append a PHASE LOG entry) and STOP. Do NOT proceed to another unit and do NOT \
launch drive-build.sh — $CONTINUATION. Never fabricate green: on a REAL block set \
blockedOn and stop; a pending gate is a RETURN PASS row, not a block. Every date you write comes from \
\`date -u\` at that moment. Record your harness and model id as \`Harness: <harness>/<model-id>/$TIER\` in the \
run-ledger header. The ledger's CURRENT STATE \`harness:\` reads '${LEDGER_HARNESS:-<not recorded>}': if it names \
a different harness or model than yours, you are a harness switch (BM-HARNESS-01) — allowed only at this boundary \
and only on the operator's words: record a PHASE LOG \`harness-switch\` entry quoting them, or stop and ask. \
Before you stop on a block, a gate or a usage-limit event, or after the last row under a chain-table banner, \
write the operator digest (orchestrate-build §4, scripts/digest.sh)."

  if [ "$PRINT_PROMPT" -eq 1 ]; then
    echo "drive-build: checks passed — start ONE fresh session (any harness) with this prompt, then re-run --print-prompt:"
    echo "──8<──"
    printf '%s\n' "$PROMPT"
    echo "──8<──"
    exit 0
  fi

  ARGV=( "${BASE_ARGV[@]}" "$PROMPT" )
  LOG="$LOG_DIR/iter-$(printf '%03d' "$i")-${NEXT}.log"

  set +e
  if [ -n "$WORKTREE" ] && [ -d "$WORKTREE" ]; then
    ( cd "$WORKTREE" && "${ARGV[@]}" ) 2>&1 | tee "$LOG"
  else
    "${ARGV[@]}" 2>&1 | tee "$LOG"
  fi
  rc=${PIPESTATUS[0]}
  set -e

  # Progress = the ledger moved. If it didn't, diagnose (don't spin).
  NEW_STATUS="$(status_val projectStatus | awk '{print $1}')" ; NEW_NEXT="$(status_val nextTicket)" ; NEW_BLOCKED="$(status_val blockedOn)"
  [ -n "$NEW_NEXT" ] || NEW_NEXT="$(status_val nextUnit)"
  NEW_RP="$(status_val returnPass)"
  if [ "$NEW_NEXT" = "$NEXT" ] && [ "$NEW_STATUS" = "$STATUS" ]; then
    case "$NEW_BLOCKED" in
      ""|"(nothing)"|"nothing"|"none"|"(none)")
        # No progress and no real block. A gate that needs the operator shows up as a NEW returnPass entry
        # (or projectStatus=PAUSED, handled at the top) — that is a clean stop, not a failure.
        if [ -n "$NEW_RP" ] && [ "$NEW_RP" != "(none)" ] && [ "$NEW_RP" != "$PREV_RP" ]; then
          echo "drive-build: gate pending on '$NEXT' — answer in LEDGER.md GATE DECISIONS and re-run (returnPass: $NEW_RP)."
          exit 0
        fi
        echo "drive-build: unit '$NEXT' made no ledger progress (agent exit=$rc)." >&2
        echo "  Most common cause: writes were denied because autonomy is off — re-run with --yolo." >&2
        echo "  See the agent transcript: $LOG" >&2
        exit 2 ;;
      *) echo "drive-build: unit '$NEXT' set blockedOn='$NEW_BLOCKED' (agent exit=$rc) — human needed. See $LOG." >&2
         exit 2 ;;
    esac
  fi
  [ "$rc" -eq 0 ] || echo "drive-build: note: agent exited $rc but the ledger advanced; continuing. See $LOG." >&2
done

echo "drive-build: hit --max-iters=$MAX_ITERS without reaching DONE. Re-run to continue." >&2
exit 3
