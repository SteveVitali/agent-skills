<!--
  Template: tail ticket DOC (docs refresh — the minimal tail's single docs row; tail=full uses
  DOC.1 + DOC.2 instead). Filled by: decompose-spec at seed/extend. Placeholders filled on
  instantiation. An ordinary implement-spec contract that invokes refresh-repo-docs, then agent-docs.
-->
# DOC — docs refresh (human-facing, then agent-facing)

- **Sequence:** docs · **Phase:** docs · **Kind:** docs
- **Tag:** docs
- **base_branch:** current checkout
- **Depends on:** GATE-ACCEPT
- **Run:** `implement-spec spec=docs/tickets/<file>.md live_verification=false`
- **Gate status:** none
- **Live stage:** none

## Goal
Converge {{build_name}}'s human-facing docs and its AGENTS.md hierarchy onto what the composed
build actually does, so a reader gets a correct result and a fresh agent can start cold.

## Load (read these — do not re-read others)
- **Invoke `refresh-repo-docs`** and follow it completely, honoring `docs/README.md`'s mode
  table (`generated` → fix source/regenerate; `frozen`/`historical`/`append-only` →
  report-only; `docs/tickets/` and `docs/build/` default to historical).
- **Then invoke `agent-docs`** (refresh mode) and follow it completely; `docs/build/README.md`
  (the marker) so the "Build memory" section is generated.
- `docs/build/BUILD_INDEX.md` and `docs/build/COVERAGE_MATRIX.csv` for what shipped.

## In scope — deliverables
1. README(s), `docs/` (living), CHANGELOG, guides, examples corrected against the composed
   build — stale fixed, cruft removed, gaps filled, every claim verified against the code.
2. The AGENTS.md hierarchy refreshed, including a "Build memory" section (where
   `docs/tickets`, `00_MANIFEST.md`, `DEFERRALS.md`, `BUILD_INDEX.md` and ADRs live; "read
   `DEFERRALS.md` first every run" as a Critical Gotcha; the append-only and stacked-PR rules).

## Out of scope
- Historical/frozen build memory (report-only, never rewritten). Architectural decisions.

## Acceptance criteria
- [ ] `refresh-repo-docs`' detector reports no broken references after the run *(deterministic)*
- [ ] `agent-docs`' freshness detector reports 0 critical issues; the "Build memory" section is present *(deterministic)*
- [ ] every changed claim is verified against the current code (no fabricated content) *(agentic)*
- [ ] *(live-read)* The artifact this row writes cites the live state it describes: the CI read of every open PR in the stack (`ci-boundary.sh` output once it ships — BM-CI-01; until then `gh pr checks <n>` with its `date -u`); where the build has a production surface, a probe-run record (id, `date -u`, result, sha256) no older than 24 h at the commit. A statement about production state with no such citation is removed, not written.
- [ ] verification green; every new behaviour has a test that fails if it is removed; requirement ids stamped in the PR; anything not automatically verifiable is a `DEFERRALS.md` row with its compensating control; ADRs written for every deviation and owned decision; `BUILD_INDEX.md` row and `LEDGER.md` advanced; operating clauses met — dates from the clock, PR checks read and recorded, AC layers stated, no living-record pins, protected records only appended, gate words verbatim, harness in the run-ledger header. *(agentic — the universal phase-gate AC)*

## Requirement IDs to satisfy and stamp in the PR
The docs ids of `{{spec_path}}`, if any (matching `{{req_id_pattern}}`).

## Cross-cutting invariants
- Cited from `docs/tickets/00_MANIFEST.md § Cross-cutting invariants`. Never hand-edit a
  generated doc; fix its source and regenerate.

## Operating clauses
- Cited from `docs/tickets/00_MANIFEST.md § Operating rules`; the gap table has one row per clause.

## Notes
- The last tail row of a minimal tail. After it lands and every gate is signed,
  `projectStatus: DONE` per BM-TAIL-03.
