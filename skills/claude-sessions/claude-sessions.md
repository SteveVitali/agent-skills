---
id: claude-sessions
description: "Snapshot running Claude Code sessions before shutdown, restore them after reboot"
---

# Claude Sessions: Snapshot & Restore

> **Claude Code specific.** Unlike the other skills in this repo (which are
> agent-agnostic), this one is tied to Claude Code: it reads
> `~/.claude/projects` and invokes `claude --resume`. It is otherwise
> repo/company agnostic — it works on any machine and any project.

Claude Code does not record which sessions are "currently running", and a
machine shutdown kills every session. This workflow captures the running set to
a **snapshot file** before you shut down, then restores them (one terminal tab
per session, each resumed) after you reboot.

Two verbs, decoupled so restore survives a full power-off:

- **`snapshot`** — capture running sessions to disk (do this before shutdown).
- **`restore`** — reopen + resume every session in the snapshot (after reboot).

Plus read-only `list` / `print` for ad-hoc inspection of live sessions.

## How running sessions are detected

The helper script `scripts/claude-sessions.sh` combines three signals:

1. **Live processes** — `pgrep -x claude`. (On macOS/BSD, `pgrep` excludes its
   own ancestors, so the session you are typing in is auto-excluded.)
2. **Working directory** — `lsof -p <pid> -d cwd` maps each process to its cwd.
3. **Transcript** — the newest `.jsonl` in the matching
   `~/.claude/projects/<mangled-cwd>/` folder is that process's session. The
   transcript layout is version-dependent — older Claude Code versions write
   `<project>/<id>.jsonl`, newer ones `<project>/sessions/<id>.jsonl` — so the
   script checks both locations. When several sessions share one directory, the
   N newest transcripts map to the N processes there.

`snapshot` records this to the snapshot file; `restore` reads *only* the file
(the live processes are gone by then).

## Snapshot file

Canonical location: `${XDG_STATE_HOME:-~/.local/state}/claude-sessions-snapshot.json`
— machine-level state, covering sessions across all repos/worktrees. Override
with `CLAUDE_SESSIONS_SNAPSHOT`.

Each entry records `session_id`, `cwd`, `branch`, and `summary`, plus a
top-level `snapshot_at` timestamp, `scope`, and `count`. Writing a new snapshot
keeps one generation of backup at `<snapshot>.prev`, so a repo-scoped snapshot
cannot irrecoverably clobber an earlier `--all` one.

## Usage

```bash
# --- Before shutting down: capture running sessions ---
scripts/claude-sessions.sh snapshot          # this repo's worktrees (default)
scripts/claude-sessions.sh snapshot --all    # every Claude session on the machine

# --- After reboot: bring them back ---
scripts/claude-sessions.sh restore           # opens a tab per session, resuming each
scripts/claude-sessions.sh restore --dry-run # just print the commands first
scripts/claude-sessions.sh restore --fork    # resume with --fork-session (new ids)

# --- Ad-hoc inspection (read-only, live) ---
scripts/claude-sessions.sh list              # table of running sessions (default: repo)
scripts/claude-sessions.sh list --all        # machine-wide
scripts/claude-sessions.sh print             # `cd ... && claude --resume ...` lines
```

`restore` reopens the sessions in **iTerm2** as a **2-column pane grid** (two
sessions per row) in a single new window. If iTerm2 is not installed it falls
back to **Terminal.app** tabs (Terminal cannot make arbitrary panes); if
neither is available it prints the commands to paste manually. Sessions whose
`cwd` no longer exists are skipped with a notice. `--resume <id>` must run from
the original directory; the script always `cd`s there first. With `--fork`,
each resume gets `--fork-session`, branching into a fresh session id instead of
writing back into the original transcript — use it whenever the original
processes might still be alive.

## Recommended procedure

1. **Before shutdown:** run `snapshot` (or `snapshot --all`). Confirm the
   reported count looks right.
2. **After reboot:** run `restore --dry-run` and eyeball the commands, then
   run `restore` to open the tabs.

## Caveats

- **Unsupported surface**: Anthropic's session docs state the transcript entry
  format "is internal to Claude Code and changes between versions, so scripts
  that parse these files directly can break on any release." This tool touches
  that surface as lightly as possible — filenames for session ids, first-line
  `summary` on a best-effort basis (falls back to empty) — but a Claude Code
  update can still break detection; re-verify with `list` after upgrades.
- The newest-transcript-per-cwd mapping is a heuristic — reliable in practice,
  only theoretically ambiguous when two sessions in one directory write at the
  same instant.
- `restore`'s pane/tab automation is macOS-only (iTerm2/Terminal via
  `osascript`). Many panes in one window get cramped; `restore` is intended for
  a post-reboot restore where the original sessions are gone. Restoring while
  the originals are still running means two `claude` processes attach to the
  same session id — pass `--fork` to avoid that.
- Respects `CLAUDE_CONFIG_DIR` and `CLAUDE_SESSIONS_SNAPSHOT` overrides.
