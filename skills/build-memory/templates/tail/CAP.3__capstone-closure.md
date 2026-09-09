<!--
  Template: tail ticket CAP.3 (capstone closure). Filled by: decompose-spec at seed/extend.
  Placeholders filled on instantiation. An ordinary implement-spec contract.
-->
# CAP.3 — capstone closure

- **Sequence:** capstone 3 · **Phase:** capstone · **Kind:** capstone
- **Tag:** capstone
- **base_branch:** current checkout
- **Depends on:** CAP.2
- **Run:** `implement-spec spec=docs/tickets/<file>.md`
- **Gate status:** none
- **Live stage:** offline-only

## Goal
Close the real gaps CAP.1/CAP.2 routed to closure, consciously accept the sound deviations,
and produce the accepted-deviations list the operator signs at `GATE-ACCEPT`.

## Load (read these — do not re-read others)
- `docs/build/CAPSTONE_GAP_ANALYSIS.md`, `docs/build/COVERAGE_MATRIX.csv`,
  `docs/build/COMPOSED_E2E_REPORT.md` (the routed gaps and deviations).
- `docs/tickets/DEFERRALS.md` (rows to close or add).
- `{{spec_path}}` for the sections the closures touch.

## In scope — deliverables
1. Close each routed gap on the branch `<user>/{{build_name}}-capstone` (forked from the chain
   tip) — CODE gaps fixed + tested; VERIFICATION gaps run — each a small scoped change.
2. Consciously accept each sound deviation with its reasoning, and write an ADR for every
   MET-DIFFERENTLY verdict and every SHOULD-level deviation.
3. `docs/build/CAPSTONE_CLOSURE.md` — what was closed, what was accepted, and the
   **ACCEPTED-deviations list proposed for the operator's signature** (each row: id, what
   deviates, why it is sound, the compensating control). Update the matrix verdicts as rows close.

## Out of scope
- The gap analysis (CAP.1) and composed run (CAP.2). Reconciliation backlog/spec/integration
  (REC.1–REC.3). Signing the deviations (the operator does that at `GATE-ACCEPT`).

## Acceptance criteria
- [ ] every gap CAP.1/CAP.2 routed to closure is closed or moved to an ACCEPTED/DEFERRALS row with reason *(deterministic)*
- [ ] `CAPSTONE_CLOSURE.md` carries the ACCEPTED-deviations list for signature *(deterministic)*
- [ ] an ADR exists for every MET-DIFFERENTLY verdict and every SHOULD-level deviation *(deterministic)*
- [ ] verification green; every new behaviour has a test that fails if it is removed; requirement ids stamped in the PR; anything not automatically verifiable is a `DEFERRALS.md` row with its compensating control; ADRs written for every deviation and owned decision; `BUILD_INDEX.md` row and `LEDGER.md` advanced. *(agentic — the universal phase-gate AC)*

## Requirement IDs to satisfy and stamp in the PR
The closure ids of `{{spec_path}}` and any ids whose verdict this ticket moves to MET (matching `{{req_id_pattern}}`).

## Cross-cutting invariants
- Cited from `docs/tickets/00_MANIFEST.md § Cross-cutting invariants`.

## Notes
- This ticket owns `CAPSTONE_CLOSURE.md` and the ACCEPTED-deviations list. `GATE-ACCEPT` is
  the next chain row; do not mark the build DONE here.
