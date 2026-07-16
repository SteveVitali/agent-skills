#!/bin/bash
# claude-sessions.sh — snapshot & restore running Claude Code sessions
# ---------------------------------------------------------------------------
# CLAUDE CODE SPECIFIC. This tool is tied to Claude Code (it reads
# ~/.claude/projects and invokes `claude --resume`) but is otherwise
# repo/company agnostic.
#
# WHY
# Claude Code does not record which sessions are "currently running", and a
# machine shutdown kills every session process. This tool lets you capture the
# set of running sessions to a snapshot file *before* shutting down, then
# restore them (reopen a terminal tab per session, resuming each) after reboot.
#
# HOW RUNNING SESSIONS ARE DETECTED
#   1. live `claude` processes            (pgrep -x claude)
#   2. each process's working directory   (lsof -p <pid> -d cwd)
#   3. the most-recently-modified .jsonl transcript in the matching project
#      folder ~/.claude/projects/<mangled-cwd>/  (mangling: each run of
#      non-alphanumeric chars in the abs path becomes '-')
# When several sessions share one directory, the N newest transcripts are
# assigned to the N processes there. (On macOS/BSD `pgrep` excludes its own
# ancestors, so the session you are typing in is auto-excluded.)
#
# LAYOUT & FRAGILITY NOTE
# Claude Code's transcript layout is version-dependent: older versions write
# <project>/<session-id>.jsonl, newer ones <project>/sessions/<session-id>.jsonl
# (with subagent transcripts nested deeper — deliberately not matched here).
# Both locations are checked. Anthropic documents the transcript entry format
# as internal and subject to change on any release, so all parsing here
# degrades gracefully (missing/unparseable fields become empty strings).
#
# SUBCOMMANDS
#   snapshot [--all]      Capture running sessions to the snapshot file.
#                         Default: sessions in the current repo's worktrees.
#                         --all: every running Claude session on the machine.
#   restore  [--dry-run] [--fork]
#                         Reopen + resume every session in the snapshot file.
#                         Uses iTerm2 if present, else Terminal.app.
#                         --dry-run: just print the commands.
#                         --fork: resume with --fork-session (new session ids;
#                         safe when the originals may still be running).
#   list     [--repo|--here|--all]   Live table (read-only), no snapshot.
#   print    [--repo|--here|--all]   Live `cd ... && claude --resume ...` lines.
#
# SNAPSHOT FILE
#   Canonical location:
#     ${XDG_STATE_HOME:-$HOME/.local/state}/claude-sessions-snapshot.json
#   Machine-level state (one snapshot covers all repos/worktrees).
#   Override with CLAUDE_SESSIONS_SNAPSHOT.
#
# ENV
#   CLAUDE_CONFIG_DIR            Override ~/.claude.
#   CLAUDE_SESSIONS_SNAPSHOT     Override the snapshot file path.
#
# Compatible with macOS system bash 3.2.
# ---------------------------------------------------------------------------
set -u

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
PROJECTS_DIR="$CLAUDE_DIR/projects"

CMD=""
FILTER_MODE="repo"   # repo | here | all   (default repo for snapshot/list/print)
DRY_RUN=0
FORK=0

for arg in "$@"; do
  case "$arg" in
    snapshot|restore|list|print) CMD="$arg" ;;
    --all)     FILTER_MODE="all" ;;
    --repo)    FILTER_MODE="repo" ;;
    --here)    FILTER_MODE="here" ;;
    --dry-run) DRY_RUN=1 ;;
    --fork)    FORK=1 ;;
    -h|--help)
      sed -n '2,/^set -u/p' "$0" | sed 's/^# \{0,1\}//; /^set -u/d'
      exit 0 ;;
    *) echo "Unknown argument: $arg" >&2; exit 2 ;;
  esac
done

[ -z "$CMD" ] && { echo "Usage: claude-sessions.sh {snapshot|restore|list|print} [--repo|--here|--all] [--dry-run] [--fork]" >&2; exit 2; }

# --- Resolve the canonical snapshot file path -------------------------------
resolve_snapshot_path() {
  if [ -n "${CLAUDE_SESSIONS_SNAPSHOT:-}" ]; then
    printf '%s\n' "$CLAUDE_SESSIONS_SNAPSHOT"; return
  fi
  printf '%s/claude-sessions-snapshot.json\n' "${XDG_STATE_HOME:-$HOME/.local/state}"
}
SNAPSHOT_FILE=$(resolve_snapshot_path)

# --- Build allowed cwd prefixes for the active filter -----------------------
ALLOWED_PREFIXES=""
build_prefixes() {
  case "$FILTER_MODE" in
    all)  ALLOWED_PREFIXES="" ;;
    here) ALLOWED_PREFIXES="$PWD" ;;
    repo)
      if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        local wt
        wt=$(git worktree list --porcelain 2>/dev/null | awk '/^worktree /{print substr($0,10)}')
        [ -z "$wt" ] && wt=$(git rev-parse --show-toplevel 2>/dev/null)
        ALLOWED_PREFIXES="$wt"
      else
        echo "--repo: not inside a git work tree (use --all or --here)." >&2; exit 2
      fi
      ;;
  esac
}

cwd_allowed() {
  [ "$FILTER_MODE" = "all" ] && return 0
  local cwd="$1" p
  for p in $ALLOWED_PREFIXES; do
    case "$cwd" in
      "$p"|"$p"/*) return 0 ;;
    esac
  done
  return 1
}

# --- Collect running sessions, resolved. Emits: pid|cwd|sid|branch|summary --
collect_running() {
  build_prefixes
  local tmp
  tmp=$(mktemp "${TMPDIR:-/tmp}/cc_sessions.XXXXXX")
  pgrep -x claude | while read -r pid; do
    [ -z "$pid" ] && continue
    cwd=$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | awk '/^n/{print substr($0,2)}')
    [ -z "$cwd" ] && continue
    cwd_allowed "$cwd" || continue
    printf '%s|%s\n' "$pid" "$cwd"
  done | sort -t'|' -k2 > "$tmp"

  local prev="" n=0
  while IFS='|' read -r pid cwd; do
    if [ "$cwd" = "$prev" ]; then n=$((n+1)); else n=1; prev="$cwd"; fi
    local mangled projdir file sid branch summary
    mangled=$(printf '%s' "$cwd" | sed 's/[^a-zA-Z0-9]/-/g')
    projdir="$PROJECTS_DIR/$mangled"
    # Layout varies by Claude Code version: transcripts live either directly in
    # the project dir or under a sessions/ subdir. Check both, newest first.
    file=$(ls -t "$projdir"/*.jsonl "$projdir"/sessions/*.jsonl 2>/dev/null | sed -n "${n}p")
    [ -z "$file" ] && continue
    sid=$(basename "$file" .jsonl)
    branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null)
    summary=$(head -1 "$file" 2>/dev/null | python3 -c '
import sys, json
try:
    o = json.loads(sys.stdin.readline())
    print((o.get("summary") or "")[:120])
except Exception:
    print("")
' 2>/dev/null)
    printf '%s|%s|%s|%s|%s\n' "$pid" "$cwd" "$sid" "$branch" "$summary"
  done < "$tmp"
  rm -f "$tmp"
}

# --- Choose a terminal launcher: iterm2 | terminal | none -------------------
detect_launcher() {
  if [ -d "/Applications/iTerm.app" ] && command -v osascript >/dev/null 2>&1; then
    echo "iterm2"
  elif [ -d "/Applications/Utilities/Terminal.app" ] || [ -d "/System/Applications/Utilities/Terminal.app" ]; then
    command -v osascript >/dev/null 2>&1 && echo "terminal" || echo "none"
  else
    echo "none"
  fi
}

# Open every command as a pane in ONE new iTerm2 window, arranged as a
# 2-column grid (2 sessions per row). $1 = path to a file of NUL-delimited
# commands. (The Python program is supplied via the heredoc on stdin, so the
# command data must come from a file argument, not stdin.)
# The AppleScript is generated by Python so pane references and the grid
# geometry are tracked explicitly (iTerm2 splits form a binary tree, so a
# precise grid needs per-pane bookkeeping).
open_iterm_grid() {
  python3 - "$1" <<'PY' | /usr/bin/osascript
import sys

with open(sys.argv[1], "rb") as fh:
    cmds = [c for c in fh.read().decode("utf-8", "replace").split("\0") if c != ""]
if not cmds:
    sys.exit(0)

def esc(s):
    # Escape for an AppleScript double-quoted string literal.
    return s.replace("\\", "\\\\").replace('"', '\\"')

# Target: a true 2-column grid (2 sessions per row). iTerm2 splits form a
# binary tree, so to keep rows equal-height we must build the rows FIRST as a
# single stacked column of full-width panes, THEN split each row vertically to
# create its right column. (Splitting a half-width pane horizontally instead
# would make one pane span two rows.)
import math
n = len(cmds)
rows = math.ceil(n / 2)

lines = ['tell application "iTerm2"', "  activate",
         "  set newWindow to (create window with default profile)",
         "  set row0 to (current session of newWindow)"]

# 1) Stack full-width rows: row0 (already exists), row1, row2, ... by
#    horizontally splitting the previous row's pane.
for r in range(1, rows):
    lines.append("  tell row%d to set row%d to (split horizontally with default profile)" % (r - 1, r))

# 2) For each row, left pane = rowR (cmd 2R), right pane = split vertically (cmd 2R+1).
for r in range(rows):
    left_idx = 2 * r
    right_idx = 2 * r + 1
    lines.append('  tell row%d to write text "%s"' % (r, esc(cmds[left_idx])))
    if right_idx < n:
        lines.append("  tell row%d to set row%dR to (split vertically with default profile)" % (r, r))
        lines.append('  tell row%dR to write text "%s"' % (r, esc(cmds[right_idx])))

lines.append("end tell")
print("\n".join(lines))
PY
}

open_terminal_tab() {
  # $1 = shell command; Terminal.app cannot make arbitrary panes, so use tabs.
  local cmd="$1"
  /usr/bin/osascript <<OSA
tell application "Terminal"
  activate
  do script "$cmd"
end tell
OSA
}

case "$CMD" in
  list)
    printf '%-7s  %-34s  %-36s  %-28s  %s\n' "PID" "CWD" "SESSION ID" "BRANCH" "SUMMARY"
    printf '%-7s  %-34s  %-36s  %-28s  %s\n' \
      "-------" "----------------------------------" \
      "------------------------------------" "----------------------------" "-------"
    collect_running | while IFS='|' read -r pid cwd sid branch summary; do
      short_cwd=$(printf '%s' "$cwd" | sed "s#^$HOME#~#")
      printf '%-7s  %-34s  %-36s  %-28s  %s\n' "$pid" "$short_cwd" "$sid" "$branch" "$summary"
    done
    ;;

  print)
    collect_running | while IFS='|' read -r pid cwd sid branch summary; do
      printf 'cd %s && claude --resume %s\n' "$(printf '%q' "$cwd")" "$sid"
    done
    ;;

  snapshot)
    rows=$(collect_running)
    if [ -z "$rows" ]; then
      echo "No running sessions matched (scope=$FILTER_MODE). Snapshot not written."
      exit 0
    fi
    mkdir -p "$(dirname "$SNAPSHOT_FILE")"
    # Keep one generation of backup so a scoped snapshot can't silently
    # clobber an earlier (e.g. --all) snapshot beyond recovery.
    [ -f "$SNAPSHOT_FILE" ] && cp "$SNAPSHOT_FILE" "$SNAPSHOT_FILE.prev"
    printf '%s\n' "$rows" | SCOPE="$FILTER_MODE" python3 -c '
import sys, json, os, datetime
sessions = []
for line in sys.stdin:
    line = line.rstrip("\n")
    if not line:
        continue
    parts = line.split("|", 4)
    if len(parts) < 5:
        continue
    pid, cwd, sid, branch, summary = parts
    sessions.append({
        "session_id": sid,
        "cwd": cwd,
        "branch": branch,
        "summary": summary,
    })
doc = {
    "snapshot_at": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
    "scope": os.environ.get("SCOPE", "repo"),
    "count": len(sessions),
    "sessions": sessions,
}
print(json.dumps(doc, indent=2))
' > "$SNAPSHOT_FILE"
    n=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["count"])' "$SNAPSHOT_FILE" 2>/dev/null)
    echo "Wrote $n session(s) (scope=$FILTER_MODE) to $SNAPSHOT_FILE"
    [ -f "$SNAPSHOT_FILE.prev" ] && echo "Previous snapshot kept at $SNAPSHOT_FILE.prev"
    ;;

  restore)
    if [ ! -f "$SNAPSHOT_FILE" ]; then
      echo "No snapshot file at $SNAPSHOT_FILE. Run 'snapshot' first." >&2
      exit 1
    fi
    launcher=$(detect_launcher)
    if [ "$DRY_RUN" = "0" ] && [ "$launcher" = "none" ]; then
      echo "No supported terminal (iTerm2/Terminal.app) found. Showing commands instead:" >&2
      DRY_RUN=1
    fi

    # Build the resume commands from the snapshot, skipping sessions whose cwd
    # is gone. Python emits cwd<TAB>sid pairs (one per line); bash assembles the
    # shell command with proper quoting via printf %q and writes NUL-delimited
    # commands to a temp file (bash variables cannot hold NUL bytes).
    CMDFILE=$(mktemp "${TMPDIR:-/tmp}/cc_restore.XXXXXX")
    trap 'rm -f "$CMDFILE"' EXIT
    python3 -c '
import json, sys, os
doc = json.load(open(sys.argv[1]))
for s in doc.get("sessions", []):
    cwd = s.get("cwd",""); sid = s.get("session_id","")
    if not cwd or not sid:
        continue
    if not os.path.isdir(cwd):
        sys.stderr.write("Skipping (cwd gone): %s\n" % cwd)
        continue
    sys.stdout.write("%s\t%s\n" % (cwd, sid))
' "$SNAPSHOT_FILE" | while IFS="$(printf '\t')" read -r cwd sid; do
      if [ "$FORK" = "1" ]; then
        printf 'cd %s && claude --resume %s --fork-session\0' "$(printf '%q' "$cwd")" "$sid"
      else
        printf 'cd %s && claude --resume %s\0' "$(printf '%q' "$cwd")" "$sid"
      fi
    done > "$CMDFILE"

    if [ ! -s "$CMDFILE" ]; then
      echo "No restorable sessions in snapshot (all cwds gone?)."
      exit 0
    fi

    if [ "$DRY_RUN" = "1" ]; then
      tr '\0' '\n' < "$CMDFILE"
      exit 0
    fi

    case "$launcher" in
      iterm2)
        echo "Restoring sessions as a 2-column pane grid in a new iTerm2 window..."
        open_iterm_grid "$CMDFILE"
        ;;
      terminal)
        echo "iTerm2 not found; restoring sessions as Terminal.app tabs..."
        while IFS= read -r -d '' cmd; do
          open_terminal_tab "$cmd"
        done < "$CMDFILE"
        ;;
    esac
    ;;
esac
