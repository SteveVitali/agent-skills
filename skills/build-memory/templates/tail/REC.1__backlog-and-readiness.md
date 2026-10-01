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
   OPEN FINDINGS entry, every deferred register row, and every PARTIAL / MISSING /
   AT-RISK-INTEGRATION matrix row appears in exactly one `sources` cell (MET-ENGINEERED rows are
   homed through their owed-leg D-rows, WAIVED through their ADR; MET-DIFFERENTLY is not a source),
   in a row that is not `closed` while the source is owed.
2. `docs/build/BACKLOG.md` — grouped by `landing`, then the REC sweeps: a dated revisit-trigger
   sweep (every ADR: quiet / fired-unanswered / fired-answered / superseded / dormant, with
   `date -u`), a dated `## Round <n> review` section in the risk register when the project keeps
   one, and the two sums recomputed from the matrix beside CAP.3's headline.
3. `docs/build/OPERATIONAL_READINESS.md` — capability × {code, infra, human (owner, date), highest
   layer reached, proof}; a critical path with `ticket:` and `proof:` on every step; no TBD, and no
   production claim without a probe-run or `ci-boundary` citation no older than 24 h.
4. `check-backlog.sh` (reconcile-build) exits 0: complete, non-duplicating, live homes, verdicts
   consistent with DEFERRALS, sums equal to CAP.3's headline.

## Out of scope
- Spec reconciliation (REC.2) and the integration plan (REC.3). Implementing backlog items.

## Acceptance criteria
- [ ] every owed source (BM-VERDICT-01 gather rules) appears in exactly one BACKLOG source cell, in a live home, and `check-backlog.sh` exits 0 *(deterministic)*
- [ ] `BACKLOG.md` carries the dated revisit-trigger sweep (one state per ADR) and the two sums *(deterministic)*
- [ ] `OPERATIONAL_READINESS.md` critical path has `ticket:` + `proof:` on every step and no TBD *(deterministic)*
- [ ] *(live-read)* The artifact this row writes cites the live state it describes: the CI read of every open PR in the stack (`ci-boundary.sh --stack --no-wait` output with its `read_at` — BM-CI-01); where the build has a production surface, a probe-run record (id, `date -u`, result, sha256) no older than 24 h at the commit. A statement about production state with no such citation is removed, not written.
- [ ] verification green; every new behaviour has a test that fails if it is removed; requirement ids stamped in the PR; anything not automatically verifiable is a `DEFERRALS.md` row with its compensating control; ADRs written for every deviation and owned decision; `BUILD_INDEX.md` row and `LEDGER.md` advanced; operating clauses met — dates from the clock, PR checks read and recorded, AC layers stated, no living-record pins, protected records only appended, gate words verbatim, harness in the run-ledger header. *(agentic — the universal phase-gate AC)*

## Requirement IDs to satisfy and stamp in the PR
The backlog/readiness ids of `{{spec_path}}` (matching `{{req_id_pattern}}`).

## Cross-cutting invariants
- Cited from `docs/tickets/00_MANIFEST.md § Cross-cutting invariants`.

## Operating clauses
- Cited from `docs/tickets/00_MANIFEST.md § Operating rules`; the gap table has one row per clause.

## Notes
- This ticket owns `BACKLOG.csv`'s column set. Each source appears in exactly one item.
