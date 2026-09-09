# Changelog

All notable changes to agent-skills are recorded here. Versioning is the plugin version in
`.claude-plugin/plugin.json`.

## 0.2.0 — Build memory v2

Build memory becomes a **committed, validated layout** every build skill reads and writes the same way, and the
lifecycle is covered end to end (brief → research → spec → decomposition → build → capstone → reconciliation →
docs → next round). **Opt-in and backward-compatible:** a repo activates the new layout only by a
`docs/build/README.md` marker (`<!-- build-memory: v2 -->`); a repo without it behaves exactly as 0.1.0
(gitignored scratch mode), and every existing input keeps its name and default.

### Added
- **`build-memory`** — owns the layout contract (`layout.md`), the templates, the validator, and migration.
  Modes: `init`, `check`, `migrate`, `adr-index`. Scripts: `memory-root.sh` (resolve committed vs scratch root
  from the current worktree), `check-build-memory.sh` (validate the layout; exit 0/1/2), `adr-index.sh`
  (regenerate the ADR index), `migrate-legacy-scratch.sh` (move a legacy scratch dir into `docs/build/`;
  dry-run by default, contents byte-identical). Self-test fixtures under `tests/`.
- **`synthesize-spec`** — the upstream half: a `docs/research-ledger.md` whose rows are executed in fresh
  contexts, then synthesis, fresh-context adversarial review, and operator ratification, handing off to
  `decompose-spec` via `docs/decomposition-prompt.md`. Modes: `plan`, `run`, `synthesize`, `review`, `ratify`.
- **`reconcile-build`** — the closeout procedures the tail `REC.*` tickets invoke. Modes: `backlog` (a single
  complete, non-duplicating backlog + operational readiness), `spec` (ticket-vs-spec + reconciliation plan),
  `integration` (a read-only merge dry-run, integration plan, release notes, next-round memo). Scripts:
  `check-backlog.sh`, `merge-dryrun.sh` (never merges).

### Changed
- **`decompose-spec`** — new inputs `mode` (seed | extend), `tail` (full | minimal), `sequence_prefix`; Phase 5
  now calls `build-memory init`, writes the state-only ledger and the v2 manifest, appends the standard tail
  rows, and runs the validator; the spec-amendment protocol is spelled out; committed mode defaults
  `tickets_dir` to `docs/tickets`.
- **`orchestrate-build`** — resolves the memory root and routes legacy ledgers; the ticket/marker **gate
  protocol** (a gate is a pause, not a block); the worker now closes its own ledger and the orchestrator only
  *confirms* the advance; the capstone is **the standard tail of tickets** (`CAP.*`/`GATE-ACCEPT`/`REC.*`/`DOC.*`),
  with the one-context procedure retained in `modes/legacy-capstone.md`. `drive-build.sh` gains `--skill`,
  parses `returnPass`/`manifest`, exits 0 on gate-pending, and logs under the gitignored `logs/` in committed mode.
- **`implement-spec`** — resolves the memory root; reads `DEFERRALS.md` and the ticket header (refusing
  skeletons); writes the committed `runs/<ID>.md` run ledger, ADRs, and `pr/<ID>.md`; a gate-pending live check
  is a deferral, never a fabricated pass; a new Phase 6.5 **closes the ticket** (BUILD_INDEX row + LEDGER advance
  + validator + `docs(build): close <ID>`). Scratch-mode behaviour is unchanged.
- **`agent-docs`** — the Doc Authoring Guidelines gain an optional **Build memory** section, generated for
  marked repos; the freshness detector reports a missing root-AGENTS.md "Build memory" section as a coverage gap.
- **`refresh-repo-docs`** — Phase 0 reads a `docs/README.md` mode table: generated → regenerate; frozen /
  historical / append-only → report-only (`docs/tickets/` and `docs/build/` default to historical).

### Compatibility
- No existing input renamed; no default changed outside committed mode; legacy ledgers still drive (on
  `nextTicket: CAPSTONE` a legacy ledger converts via `decompose-spec mode=extend`, or runs the retained
  one-context capstone under `legacy_capstone=true`).
- `build-memory migrate` adopts the layout for an in-flight build without renaming history or editing moved
  contents.

## 0.1.0 — Initial release

`implement-spec`, `decompose-spec`, `orchestrate-build`, `self-review`, `review-pr`, `address-pr-comments`,
`agent-docs`, `refresh-repo-docs`.
