<!--
  Template: docs/build/README.md — the memory-root marker file.
  Written by: build-memory init (or migrate, if absent). When: seed. MUST contain the marker
  line below verbatim — memory-root.sh keys committed mode on it. Do not delete the marker.
-->
# Build memory

<!-- build-memory: v2 -->

The committed record of **what happened** during this build. The layout contract — the tree,
the modes, who writes what — is `skills/build-memory/layout.md` (in the agent-skills repo);
this directory does not restate it.

- `LEDGER.md` — the machine-state file (`orchestrate-build` and `drive-build.sh` parse it).
- `BUILD_INDEX.md` — one row per landed chain row.
- `runs/<ID>.md` — the `implement-spec` run ledger for each ticket · `pr/<ID>.md` — its PR body.
- `readouts/GATE-G<k>.md` — gate readouts (append-only) · `planning/` — re-planning rounds.
- `tools/`, `fixtures/`, `reports/` — committed · `logs/` — the one gitignored subtree.

Everything here is a **historical record**: corrected by a new entry, never by editing an old
one. Run `check-build-memory.sh .` to validate.

<!-- migrate appends a "## Migration rename mapping" section below when adopting v2 from a legacy scratch dir. -->
