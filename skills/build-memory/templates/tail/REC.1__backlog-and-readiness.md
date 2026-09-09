<!--
  Template: tail ticket REC.1 (backlog + operational readiness). Filled by: decompose-spec at
  seed/extend. Placeholders filled on instantiation. An ordinary implement-spec contract whose
  body invokes reconcile-build (the way P22.x invoked refresh-repo-docs).
-->
# REC.1 — backlog and operational readiness

- **Sequence:** reconcile 1 · **Phase:** reconcile · **Kind:** reconcile
- **Tag:** reconcile
- **base_branch:** current checkout
- **Depends on:** GATE-ACCEPT
- **Run:** `implement-spec spec=docs/tickets/<file>.md live_verification=false`
- **Gate status:** none
- **Live stage:** none

## Goal
Turn everything the build left owed into one deduplicated backlog and an operational-readiness
picture, so nothing owed is lost and the path to production is explicit.

## Load (read these — do not re-read others)
- **Invoke `reconcile-build mode=backlog`** and follow it completely.
- `docs/build/COVERAGE_MATRIX.csv` (non-MET rows), `docs/tickets/DEFERRALS.md` (OPEN/PARTIAL),
  `docs/build/LEDGER.md § OPEN FINDINGS`, every ADR `## Revisit trigger`, and any
  spec-mandated register's deferred rows.

## In scope — deliverables
1. `docs/build/BACKLOG.csv` — columns `bl_id, title, type, sources, req_ids, package, blocks,
   landing, gate, size, status`; every OPEN/PARTIAL deferral, every ADR revisit trigger, every
   OPEN FINDINGS entry, every deferred register row, and every non-MET matrix row appears in
   exactly one `sources` cell.
2. `docs/build/BACKLOG.md` — grouped by `landing`.
3. `docs/build/OPERATIONAL_READINESS.md` — capability × {code, infra, human gate, owner}; a
   critical path with `ticket:` and `proof:` on every step; no TBD.
4. The backlog check script `reconcile-build` provides runs green.

## Out of scope
- Spec reconciliation (REC.2) and the integration plan (REC.3). Implementing backlog items.

## Acceptance criteria
- [ ] every non-MET matrix row, OPEN/PARTIAL deferral, OPEN FINDING and ADR revisit trigger appears in exactly one BACKLOG source cell *(deterministic)*
- [ ] `OPERATIONAL_READINESS.md` critical path has `ticket:` + `proof:` on every step and no TBD *(deterministic)*
- [ ] verification green; every new behaviour has a test that fails if it is removed; requirement ids stamped in the PR; anything not automatically verifiable is a `DEFERRALS.md` row with its compensating control; ADRs written for every deviation and owned decision; `BUILD_INDEX.md` row and `LEDGER.md` advanced. *(agentic — the universal phase-gate AC)*

## Requirement IDs to satisfy and stamp in the PR
The backlog/readiness ids of `{{spec_path}}` (matching `{{req_id_pattern}}`).

## Cross-cutting invariants
- Cited from `docs/tickets/00_MANIFEST.md § Cross-cutting invariants`.

## Notes
- This ticket owns `BACKLOG.csv`'s column set. Each source appears in exactly one item.
