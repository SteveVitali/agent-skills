---
id: claude-hibernate
description: "Hibernate running Claude Code sessions before shutdown, wake them after reboot"
inputs:
  - name: mode
    required: true
    description: "'hibernate' (capture running sessions to the snapshot file) or 'wake' (reopen + resume every session in it)."
---

# Claude Hibernate

> **Claude Code specific.** Unlike the other skills in this repo (which are
> agent-agnostic), this one is tied to Claude Code: it reads
> `~/.claude/projects` and invokes `claude --resume`. It is otherwise
> repo/company agnostic — it works on any machine and any project.

Claude Code does not record which sessions are "currently running", and a
machine shutdown kills every session. This skill is OS hibernation for those
sessions: write state to disk before power-off, restore it at boot. Two modes,
decoupled by the snapshot file so waking survives a full power-off:

- **`hibernate`** — capture running sessions to the snapshot file (before
  shutdown). `--dry-run` previews the table of what would be captured.
- **`wake`** — reopen + resume every session in the snapshot file (after
  reboot). `--dry-run` prints the resume commands; `--fork` resumes with
  fresh session ids; `--live` sources currently-running sessions instead of
  the file.

Everything else — scope filters, previews, paste-able command output — is a
flag on one of these two modes.

## How running sessions are detected

The helper script `scripts/claude-hibernate.sh` combines three signals:

1. **Live processes** — `pgrep -x claude`. (On macOS/BSD, `pgrep` excludes its
   own ancestors, so the session you are typing in is auto-excluded.)
2. **Working directory** — `lsof -p <pid> -d cwd` maps each process to its cwd.
3. **Transcript** — the newest `.jsonl` in the matching
   `~/.claude/projects/<mangled-cwd>/` folder is that process's session. The
   transcript layout is version-dependent — older Claude Code versions write
   `<project>/<id>.jsonl`, newer ones `<project>/sessions/<id>.jsonl` — so the
   script checks both locations. When several sessions share one directory, the
   N newest transcripts map to the N processes there.

`hibernate` records this to the snapshot file; `wake` reads *only* the file
(the live processes are gone by then — except with `--live`, which re-runs
the detection instead).

## Snapshot file

Canonical location: `${XDG_STATE_HOME:-~/.local/state}/claude-hibernate.json`
— machine-level state, covering sessions across all repos/worktrees. Override
with `CLAUDE_HIBERNATE_FILE`.

Each entry records `session_id`, `cwd`, `branch`, and `summary`, plus a
top-level `snapshot_at` timestamp, `scope`, and `count`. Writing a new snapshot
keeps one generation of backup at `<snapshot>.prev`, so a repo-scoped snapshot
cannot irrecoverably clobber an earlier `--all` one.

## Mode: hibernate (before shutdown)

```bash
scripts/claude-hibernate.sh hibernate            # this repo's worktrees (default)
scripts/claude-hibernate.sh hibernate --all      # every Claude session on the machine
scripts/claude-hibernate.sh hibernate --here     # sessions under $PWD only
scripts/claude-hibernate.sh hibernate --dry-run  # preview table; writes nothing
```

Writes the snapshot file (keeping one `.prev` backup generation) and reports
the count captured. Confirm the count looks right before powering off.

## Mode: wake (after reboot)

```bash
scripts/claude-hibernate.sh wake             # opens a pane per session, resuming each
scripts/claude-hibernate.sh wake --dry-run   # just print the resume commands first
scripts/claude-hibernate.sh wake --fork      # resume with --fork-session (new ids)

# Source LIVE sessions instead of the snapshot file:
scripts/claude-hibernate.sh wake --live --dry-run  # paste-able `cd ... && claude --resume ...` lines
scripts/claude-hibernate.sh wake --live --fork     # open forked duplicates of running sessions
```

`wake` reopens the sessions in **iTerm2** as a **2-column pane grid** (two
sessions per row) in a single new window. If iTerm2 is not installed it falls
back to **Terminal.app** tabs (Terminal cannot make arbitrary panes); if
neither is available it prints the commands to paste manually. Sessions whose
`cwd` no longer exists are skipped with a notice. `--resume <id>` must run from
the original directory; the script always `cd`s there first. With `--fork`,
each resume gets `--fork-session`, branching into a fresh session id instead of
writing back into the original transcript — use it whenever the original
processes might still be alive. For the same reason, `wake --live` refuses to
run without `--dry-run` or `--fork`.

## Recommended procedure

1. **Before shutdown:** run `hibernate` (or `hibernate --all`). Confirm the
   reported count looks right.
2. **After reboot:** run `wake --dry-run` and eyeball the commands, then
   run `wake` to open the panes.

## Caveats

- **Unsupported surface**: Anthropic's session docs state the transcript entry
  format "is internal to Claude Code and changes between versions, so scripts
  that parse these files directly can break on any release." This tool touches
  that surface as lightly as possible — filenames for session ids, first-line
  `summary` on a best-effort basis (falls back to empty) — but a Claude Code
  update can still break detection; re-verify with `hibernate --dry-run` after
  upgrades.
- The newest-transcript-per-cwd mapping is a heuristic — reliable in practice,
  only theoretically ambiguous when two sessions in one directory write at the
  same instant.
- `wake`'s pane/tab automation is macOS-only (iTerm2/Terminal via
  `osascript`). Many panes in one window get cramped; `wake` is intended for
  a post-reboot wake where the original sessions are gone. Waking while the
  originals are still running means two `claude` processes attach to the
  same session id — pass `--fork` to avoid that.
- Respects `CLAUDE_CONFIG_DIR` and `CLAUDE_HIBERNATE_FILE` overrides.
