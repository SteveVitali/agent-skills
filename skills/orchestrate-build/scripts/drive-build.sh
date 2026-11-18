#!/usr/bin/env bash
# drive-build.sh — the universal headless loop for orchestrate-build.
#
# The loop is deterministic control flow (no LLM context, so nothing rots). Each iteration invokes a FRESH
# top-level agent process to execute exactly ONE unit of the build (SETUP, the single next ticket via
# implement-spec, or CAPSTONE), which updates the durable ledger and exits. The loop re-reads the ledger and
# repeats until DONE / BLOCKED / paused. Intelligence stays in fresh contexts; sequencing stays here.
#
# Harness-agnostic: the ONLY harness-specific atom is the headless-invocation command — chosen with --harness,
# discovered from PATH, or passed with --agent-cmd. Works with Claude Code, Codex CLI, Devin CLI, Cursor CLI,
# Gemini CLI, Goose, or any CLI that runs a prompt non-interactively and exits.
#
# Usage:
#   drive-build.sh --ledger <path> [--skill <name>] [--harness <name>] [--model <id>] [--effort <level>] [--yolo]
#                  [--agent-cmd "<cmd>"] [--worktree <path>] [--log-dir <path>] [--max-iters <n>]
#                  [--no-ci-gate] [--ci-interval <s>] [--ci-max-wait <s>] [--print-prompt]
#                  [--no-usage] [--usage-cmd "<cmd>"]
#
#   --ledger      Path to the seeded build ledger (required).
#   --skill       The driving skill each fresh unit follows (default: orchestrate-build). The
#                 prompt names this skill; e.g. --skill synthesize-spec drives docs/research-ledger.md
#                 (whose next-unit pointer is `nextUnit`) the same way. Resolved under the skills root.
#   --harness     claude | codex | devin | cursor | gemini | goose — the CLI to run (default: the first of
#                 claude, goose, codex, gemini, devin, cursor-agent on PATH). With --agent-cmd it names the
#                 harness for usage measurement (default: inferred from the command's first word).
#   --model / --effort  The model id and reasoning effort for every unit (default: the CLI's own default):
#                   claude -> --model M --effort E          codex  -> -m M -c model_reasoning_effort=E
#                   devin  -> --model M-E (Devin model ids carry the effort, e.g. swe-2-high)
#                   cursor -> --model M                     gemini -> -m M          (no effort flag: a note)
#   --yolo        Enable UNATTENDED WRITES by appending the CLI's autonomy flag. Off by default: without it,
#                 headless CLIs do not prompt — they silently DENY edits/commands, so a ticket makes no changes
#                 and the loop stops at the no-progress guard. Per-CLI mapping (not with --agent-cmd):
#                   claude -> --permission-mode bypassPermissions   goose  -> GOOSE_MODE=auto
#                   codex  -> --sandbox workspace-write -c sandbox_workspace_write.network_access=true
#                             -c approval_policy=never   (workspace writes; network on, for git push and gh)
#                   devin  -> --permission-mode dangerous --respect-workspace-trust false
#                   cursor -> --force                               gemini -> --approval-mode yolo
#                 Prefer configuring autonomy out-of-band (settings allowlist, GOOSE_MODE, a scoped --agent-cmd)
#                 when you want a tighter posture than blanket bypass.
#   --agent-cmd   Override the invocation (e.g. "claude -p --permission-mode acceptEdits"). Must accept the
#                 prompt as a TRAILING POSITIONAL argument. With --agent-cmd you own the autonomy posture and the
#                 flags; --yolo, --model and --effort are ignored, and usage is read from the harness's store.
#   --worktree    Directory to run each invocation in. Default: the ledger's buildWorktree.
#                 A committed ledger outside <toplevel>/docs/build (a monorepo subproject) exports
#                 BUILD_MEMORY_ROOT=<its toplevel-relative dir> to every unit and names it in the prompt
#                 (BM-ROOT-03); a BUILD_MEMORY_ROOT already in the environment is kept.
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
#   --no-usage    Do not measure usage and run each CLI in its plain text mode.
#   --usage-cmd   For a harness with no adapter: after each unit run this shell command with BUILD_TRACE_UNIT,
#                 _ITER, _RUN, _SINCE, _UNTIL, _CWD, _OUTPUT and _HARNESS set; every JSON line it prints is
#                 appended to usage.jsonl as is.
#
# Usage (BM-TRACE-01): after every unit one build-dispatch/1 line — harness, session ids, wall time, exit code,
# tokens, compactions, cost and turns where the CLI reports them — is appended to the gitignored
# <log-dir>/usage.jsonl by build-memory/scripts/build-trace.py dispatch-usage (python3). The CLI is run in its
# structured mode where it has one, the raw output kept in iter-NNN-<unit>.jsonl (stderr in .log) and its final
# text printed as before: claude `--output-format stream-json --verbose`, codex `exec --json`, cursor
# `--output-format stream-json`, gemini `--output-format json`; devin keeps its text output and writes
# `--export iter-NNN-<unit>.atif.json`. The session the output names (or, for an --agent-cmd, the session found
# in the harness's store by worktree and time window) is then measured from the store: Claude Code transcripts,
# Codex rollouts, the Devin session database.
# Every unit runs with stdin closed (`codex exec` otherwise waits on it), without the parent session's harness
# variables (CLAUDE_CODE_SESSION_ID, CLAUDE_EFFORT, CODEX_THREAD_ID, AI_AGENT, … — a nested harness would
# otherwise read the outer session's), and with BUILD_TRACE_DISPATCH=headless and BUILD_TRACE_RUN=<run id>/iter-NNN
# (an operator-set value is kept), so the trace line the worker appends at close joins its usage.jsonl line.
#
# Exit codes: 0 = DONE, cleanly paused, gate-pending, or (--print-prompt) prompt printed;
#             2 = BLOCKED / off-enum projectStatus / CI not green / no-progress (human needed);
#             3 = iteration cap; 1 = usage.
#
# Compatible with bash 3.2+ (macOS default): C-style for-loops and indexed arrays only — no
# associative arrays, no mapfile/readarray.

set -euo pipefail

LEDGER="" ; AGENT_CMD="" ; MAX_ITERS=100 ; WORKTREE="" ; LOG_DIR="" ; YOLO=0 ; SKILL_NAME="orchestrate-build"
CI_GATE=auto ; CI_INTERVAL=60 ; CI_MAX_WAIT=2700 ; PRINT_PROMPT=0 ; USAGE=1 ; STREAM=0 ; EXPORT=0
HARNESS="" ; MODEL="" ; EFFORT="" ; USAGE_CMD="" ; PROMPT_FLAG=""

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
    --no-usage)  USAGE=0; shift ;;
    --usage-cmd) USAGE_CMD="${2:-}"; shift 2 ;;
    --harness)   HARNESS="${2:-}"; shift 2 ;;
    --model)     MODEL="${2:-}"; shift 2 ;;
    --effort)    EFFORT="${2:-}"; shift 2 ;;
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

# The memory root (BM-ROOT-03). A committed-mode ledger outside <toplevel>/docs/build (a monorepo subproject's
# sub/proj/docs/build) is exported as BUILD_MEMORY_ROOT (toplevel-relative, so each worktree resolves its own copy)
# to every unit, and the prompt names it; an operator-set BUILD_MEMORY_ROOT is kept. The default layout is unchanged.
MEM_REL="" ; MEM_PROMPT=""
if grep -qF '<!-- build-memory: v2 -->' "$(dirname "$LEDGER")/README.md" 2>/dev/null; then
  _ld="$(cd "$(dirname "$LEDGER")" && pwd -P)"; _lt="$(git -C "$_ld" rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -n "$_lt" ]; then case "$_ld" in "$_lt"/*) MEM_REL="${_ld#"$_lt"/}" ;; esac; fi
  if [ "$MEM_REL" = "docs/build" ]; then MEM_REL=""; fi
fi
if [ -n "${BUILD_MEMORY_ROOT:-}" ]; then MEM_REL="$BUILD_MEMORY_ROOT"; elif [ -n "$MEM_REL" ]; then export BUILD_MEMORY_ROOT="$MEM_REL"; fi
if [ -n "$MEM_REL" ]; then
  export BUILD_MEMORY_ROOT
  MEM_PROMPT=" The build memory root is '$MEM_REL' (BUILD_MEMORY_ROOT=$MEM_REL is exported to you; a relative value \
resolves against the worktree toplevel): every docs/build, docs/tickets and docs/adr path in the skills means \
<memory root>, <memory root>/../tickets and <memory root>/../adr, so the validator runs as \
\`BUILD_MEMORY_ROOT=$MEM_REL check-build-memory.sh .\` and the closeout \`git add\` names paths under it."
fi

# Never-fail ledger reader: prints the value or empty; tolerates leading whitespace + trailing inline comments.
# (Must not fail under `set -e`: a missing key is normal, not an error.)
status_val() {
  local line
  line="$(grep -m1 -E "^[[:space:]]*${1}:" "$LEDGER" 2>/dev/null)" || true
  [ -n "$line" ] || return 0
  printf '%s\n' "$line" | sed -E "s/^[[:space:]]*${1}:[[:space:]]*//; s/[[:space:]]*#.*$//; s/[[:space:]]*$//"
}

# The harness: its name (claude | codex | devin | cursor | gemini | goose) and CLI binary.
harness_of() {   # harness_of <command word> → harness name, or empty
  case "$(basename "$1")" in
    claude) echo claude ;; codex) echo codex ;; devin) echo devin ;; cursor-agent) echo cursor ;;
    gemini) echo gemini ;; goose) echo goose ;; *) echo "" ;;
  esac
}
cli_of() { case "$1" in cursor) echo cursor-agent ;; *) echo "$1" ;; esac; }
case "$HARNESS" in
  ""|claude|codex|devin|cursor|gemini|goose) : ;;
  claude-code) HARNESS=claude ;;
  *) echo "drive-build.sh: --harness '$HARNESS' is not one of claude|codex|devin|cursor|gemini|goose" >&2; exit 1 ;;
esac

# Build the base agent argv (everything up to, but not including, the per-unit flags and the trailing prompt).
BASE_ARGV=() ; AUTONOMY_NOTE=""
if [ "$PRINT_PROMPT" -eq 1 ]; then
  BASE_ARGV=(manual)                                  # no agent CLI: the operator starts the session
elif [ -n "$AGENT_CMD" ]; then
  read -r -a BASE_ARGV <<< "$AGENT_CMD"
  [ -n "$HARNESS" ] || HARNESS="$(harness_of "${BASE_ARGV[0]}")"
  [ "$YOLO" -eq 1 ] && echo "drive-build.sh: note: --yolo is ignored with --agent-cmd; bake autonomy into your command." >&2
  { [ -n "$MODEL" ] || [ -n "$EFFORT" ]; } && echo "drive-build.sh: note: --model/--effort are ignored with --agent-cmd; put them in your command." >&2
else
  if [ -z "$HARNESS" ]; then
    for c in claude goose codex gemini devin cursor-agent; do
      if command -v "$c" >/dev/null 2>&1; then HARNESS="$(harness_of "$c")"; break; fi
    done
    [ -n "$HARNESS" ] || { echo "drive-build.sh: no supported agent CLI (claude|goose|codex|gemini|devin|cursor-agent) on PATH; pass --harness or --agent-cmd" >&2; exit 1; }
  fi
  command -v "$(cli_of "$HARNESS")" >/dev/null 2>&1 || { echo "drive-build.sh: --harness $HARNESS: '$(cli_of "$HARNESS")' is not on PATH" >&2; exit 1; }
  NOEFFORT=0
  case "$HARNESS" in
    claude)
      BASE_ARGV=(claude -p) ; AUTONOMY_NOTE="--permission-mode bypassPermissions"
      [ "$YOLO" -eq 1 ] && BASE_ARGV+=(--permission-mode bypassPermissions)
      [ -n "$MODEL" ] && BASE_ARGV+=(--model "$MODEL")
      [ -n "$EFFORT" ] && BASE_ARGV+=(--effort "$EFFORT")
      if [ "$USAGE" -eq 1 ]; then BASE_ARGV+=(--output-format stream-json --verbose); STREAM=1; fi ;;
    codex)
      BASE_ARGV=(codex exec)
      AUTONOMY_NOTE="--sandbox workspace-write -c sandbox_workspace_write.network_access=true -c approval_policy=never"
      [ "$YOLO" -eq 1 ] && BASE_ARGV+=(--sandbox workspace-write -c sandbox_workspace_write.network_access=true -c approval_policy=never)
      [ -n "$MODEL" ] && BASE_ARGV+=(-m "$MODEL")
      [ -n "$EFFORT" ] && BASE_ARGV+=(-c "model_reasoning_effort=$EFFORT")
      if [ "$USAGE" -eq 1 ]; then BASE_ARGV+=(--json); STREAM=1; fi ;;
    devin)
      BASE_ARGV=(devin) ; AUTONOMY_NOTE="--permission-mode dangerous --respect-workspace-trust false"
      [ "$YOLO" -eq 1 ] && BASE_ARGV+=(--permission-mode dangerous --respect-workspace-trust false)
      if [ -n "$MODEL" ]; then
        DM="$MODEL"
        if [ -n "$EFFORT" ]; then
          case "$DM" in *-minimal|*-low|*-medium|*-high|*-xhigh|*-max) echo "drive-build.sh: note: --model $DM already names an effort; --effort $EFFORT ignored" >&2 ;; *) DM="$DM-$EFFORT" ;; esac
        fi
        BASE_ARGV+=(--model "$DM")
      elif [ -n "$EFFORT" ]; then NOEFFORT=1; fi
      [ "$USAGE" -eq 1 ] && EXPORT=1
      PROMPT_FLAG="-p" ;;                             # devin takes the prompt after -p (per-unit flags go first)
    cursor)
      BASE_ARGV=(cursor-agent -p) ; AUTONOMY_NOTE="--force"
      [ "$YOLO" -eq 1 ] && BASE_ARGV+=(--force)
      [ -n "$MODEL" ] && BASE_ARGV+=(--model "$MODEL")
      [ -n "$EFFORT" ] && NOEFFORT=1
      if [ "$USAGE" -eq 1 ]; then BASE_ARGV+=(--output-format stream-json); STREAM=1; fi ;;
    gemini)
      BASE_ARGV=(gemini) ; AUTONOMY_NOTE="--approval-mode yolo"
      [ "$YOLO" -eq 1 ] && BASE_ARGV+=(--approval-mode yolo)
      [ -n "$MODEL" ] && BASE_ARGV+=(-m "$MODEL")
      [ -n "$EFFORT" ] && NOEFFORT=1
      if [ "$USAGE" -eq 1 ]; then BASE_ARGV+=(--output-format json); STREAM=1; fi
      PROMPT_FLAG="-p" ;;                             # gemini takes the prompt after -p
    goose)
      BASE_ARGV=(goose run --no-session -q) ; AUTONOMY_NOTE="GOOSE_MODE=auto"
      [ "$YOLO" -eq 1 ] && BASE_ARGV=(env GOOSE_MODE=auto "${BASE_ARGV[@]}")
      { [ -n "$MODEL" ] || [ -n "$EFFORT" ]; } && echo "drive-build.sh: note: --model/--effort are not mapped for goose; set them in its config" >&2
      PROMPT_FLAG="-t" ;;                             # goose takes the prompt after -t
  esac
  [ "$NOEFFORT" -eq 1 ] && echo "drive-build.sh: note: --effort has no $HARNESS flag here; pass a model id that carries it (--model)" >&2
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
if [ -n "$MEM_REL" ]; then echo "drive-build: memory root=$MEM_REL (BUILD_MEMORY_ROOT, exported to every unit)"; fi
echo "drive-build: agent=[${BASE_ARGV[*]}] harness=${HARNESS:-<unknown>} yolo=$YOLO worktree=${WORKTREE:-<none>} logs=$LOG_DIR max-iters=$MAX_ITERS ci-gate=$CI_NOTE"

# Dispatch usage (BM-TRACE-01): one build-dispatch/1 line per unit, appended to the gitignored
# <log-dir>/usage.jsonl. Never fatal: a missing python3, an unknown harness or an unreadable store is a note, and
# the raw output stays in place.
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
TRACE_DISPATCH_SET="${BUILD_TRACE_DISPATCH:-}" ; TRACE_RUN_SET="${BUILD_TRACE_RUN:-}"
TRACE_PY="$SKILLS_ROOT/build-memory/scripts/build-trace.py"
UCWD="$(cd "${WORKTREE:-.}" 2>/dev/null && pwd -P || pwd -P)"
# The parent session's harness variables never reach a unit: a nested harness would read the outer session's.
SCRUB=(env -u CLAUDECODE -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CODE_ENTRYPOINT -u CLAUDE_CODE_CHILD_SESSION
       -u CLAUDE_CODE_SESSION_ATTENDED -u CLAUDE_CODE_MESSAGING_SOCKET -u CLAUDE_CODE_MESSAGING_TOKEN
       -u CLAUDE_CODE_EXECPATH -u CLAUDE_EFFORT -u CLAUDE_PID -u CODEX_THREAD_ID -u CODEX_SESSION_ID
       -u CODEX_TOOL_CALL_ID -u CODEX_CI -u AI_AGENT -u CHISEL_SESSION_DB -u DEVIN_TRACEPARENT)
record_usage() {   # record_usage <unit> <iter> <exit code> <since> <until>
  local out line ins outs sess
  [ "$USAGE" -eq 1 ] || return 0
  if [ -n "$USAGE_CMD" ]; then
    BUILD_TRACE_UNIT="$1" BUILD_TRACE_ITER="$2" BUILD_TRACE_RUN="$RUN_ID/iter-$ITER" BUILD_TRACE_SINCE="$4" \
      BUILD_TRACE_UNTIL="$5" BUILD_TRACE_CWD="$UCWD" BUILD_TRACE_OUTPUT="$OUT_LOG" BUILD_TRACE_HARNESS="$HARNESS" \
      bash -c "$USAGE_CMD" < /dev/null 2>/dev/null | grep -E '^[[:space:]]*\{' >> "$LOG_DIR/usage.jsonl" || true
    return 0
  fi
  if [ -z "$HARNESS" ]; then
    echo "drive-build: note: usage not measured — unknown harness for '${BASE_ARGV[0]}' (pass --harness or --usage-cmd)" >&2
    return 0
  fi
  if ! command -v python3 >/dev/null 2>&1 || [ ! -f "$TRACE_PY" ]; then
    echo "drive-build: note: python3 or build-trace.py not found — usage not measured; raw output kept at $OUT_LOG" >&2
    return 0
  fi
  [ "$STREAM" -eq 1 ] && { python3 -I "$TRACE_PY" result --harness "$HARNESS" --output "$JLOG" 2>/dev/null || true; }
  out=(--output "$OUT_LOG"); [ "$EXPORT" -eq 1 ] && out+=(--export "$ELOG")
  if line="$(python3 -I "$TRACE_PY" dispatch-usage --harness "$HARNESS" --cwd "$UCWD" --since "$4" --until "$5" \
               "${out[@]}" --exit-code "$3" --ticket "$1" --iter "$2" --run "$RUN_ID" 2>/dev/null)" && [ -n "$line" ]; then
    printf '%s\n' "$line" >> "$LOG_DIR/usage.jsonl"
    sess="$(printf '%s' "$line" | sed -nE 's/.*"sessions":\[([^]]*)\].*/\1/p' | tr -d '"')"
    ins="$(printf '%s' "$line" | sed -nE 's/.*"usage":\{[^}]*"input_tokens":([0-9]+).*/\1/p')"
    outs="$(printf '%s' "$line" | sed -nE 's/.*"usage":\{[^}]*"output_tokens":([0-9]+).*/\1/p')"
    echo "drive-build: usage $1: harness=$HARNESS session=${sess:-?} input_tokens=${ins:-?} output_tokens=${outs:-?} → $LOG_DIR/usage.jsonl"
  else
    echo "drive-build: note: could not measure usage for $1 (raw output: $OUT_LOG)" >&2
  fi
}

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
write the operator digest (orchestrate-build §4, scripts/digest.sh). A ticket's closeout appends its trace line \
(implement-spec §6.5, build-memory/scripts/build-trace.py record; BM-TRACE-01).$MEM_PROMPT"

  if [ "$PRINT_PROMPT" -eq 1 ]; then
    echo "drive-build: checks passed — start ONE fresh session (any harness) with this prompt, then re-run --print-prompt:"
    echo "──8<──"
    printf '%s\n' "$PROMPT"
    echo "──8<──"
    exit 0
  fi

  ITER="$(printf '%03d' "$i")"
  LOG="$LOG_DIR/iter-${ITER}-${NEXT}.log" ; JLOG="$LOG_DIR/iter-${ITER}-${NEXT}.jsonl"
  ELOG="$LOG_DIR/iter-${ITER}-${NEXT}.atif.json"
  UNIT_ARGS=() ; [ "$EXPORT" -eq 1 ] && UNIT_ARGS=(--export "$ELOG")
  ARGV=( "${BASE_ARGV[@]}" ${UNIT_ARGS[@]+"${UNIT_ARGS[@]}"} ${PROMPT_FLAG:+"$PROMPT_FLAG"} "$PROMPT" )
  export BUILD_TRACE_DISPATCH="${TRACE_DISPATCH_SET:-headless}" BUILD_TRACE_RUN="${TRACE_RUN_SET:-$RUN_ID/iter-$ITER}"
  T_START="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  set +e
  if [ "$STREAM" -eq 1 ]; then
    # Structured output: stdout is the event stream (kept whole), stderr the diagnostics; the final text is printed after.
    if [ -n "$WORKTREE" ] && [ -d "$WORKTREE" ]; then ( cd "$WORKTREE" && "${SCRUB[@]}" "${ARGV[@]}" < /dev/null ) > "$JLOG" 2> "$LOG"
    else "${SCRUB[@]}" "${ARGV[@]}" < /dev/null > "$JLOG" 2> "$LOG"; fi
    rc=$?
    [ -s "$LOG" ] && cat "$LOG" >&2
  elif [ -n "$WORKTREE" ] && [ -d "$WORKTREE" ]; then
    ( cd "$WORKTREE" && "${SCRUB[@]}" "${ARGV[@]}" < /dev/null ) 2>&1 | tee "$LOG"
    rc=${PIPESTATUS[0]}
  else
    "${SCRUB[@]}" "${ARGV[@]}" < /dev/null 2>&1 | tee "$LOG"
    rc=${PIPESTATUS[0]}
  fi
  set -e
  T_END="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  OUT_LOG="$LOG"; [ "$STREAM" -eq 1 ] && OUT_LOG="$JLOG"
  record_usage "$NEXT" "$i" "$rc" "$T_START" "$T_END"

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
        echo "  See the agent transcript: $OUT_LOG" >&2
        exit 2 ;;
      *) echo "drive-build: unit '$NEXT' set blockedOn='$NEW_BLOCKED' (agent exit=$rc) — human needed. See $OUT_LOG." >&2
         exit 2 ;;
    esac
  fi
  [ "$rc" -eq 0 ] || echo "drive-build: note: agent exited $rc but the ledger advanced; continuing. See $OUT_LOG." >&2
done

echo "drive-build: hit --max-iters=$MAX_ITERS without reaching DONE. Re-run to continue." >&2
exit 3
