<!--
  Template: tail ticket CAP.3 (capstone closure). Filled by: decompose-spec at seed/extend.
  Placeholders filled on instantiation. An ordinary implement-spec contract.
-->
# CAP.3 — capstone closure

- **Sequence:** capstone 3 · **Phase:** capstone · **Kind:** capstone
- **Tag:** capstone
- **base_branch:** current checkout
- **Depends on:** CAP.2 (minimal tail: CAP.1)
- **Run:** `implement-spec spec=docs/tickets/<file>.md`
- **Gate status:** none
- **Live stage:** offline-only

## Goal
Close the real gaps CAP.1/CAP.2 routed to closure, consciously accept the sound deviations,
and produce the list the operator signs at `GATE-ACCEPT`, headlined with two honest sums.

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
3. `docs/build/CAPSTONE_CLOSURE.md`, headlined with two sums recomputed from the matrix:
   - *engineering closed* = MET + MET-DIFFERENTLY + MET-ENGINEERED;
   - *requirement satisfied* = MET + MET-DIFFERENTLY.
   MET-ENGINEERED is never counted as MET. The list for the operator's signature has three parts:
   (a) accepted deviations (MET-DIFFERENTLY + ADR; each row: id, what deviates, why it is sound,
   the compensating control); (b) scoped-out owed legs (MET-ENGINEERED + D-rows with owner and
   trigger); (c) waivers requested (each needs an ADR quoting the operator). The headline also
   states the highest layer (BM-STATUS-01) the build reached. Update the matrix verdicts as rows close.

## Out of scope
- The gap analysis (CAP.1) and composed run (CAP.2). Reconciliation backlog/spec/integration
  (REC.1–REC.3). Signing the deviations (the operator does that at `GATE-ACCEPT`).

## Acceptance criteria
- [ ] every gap CAP.1/CAP.2 routed to closure is closed or moved to an ACCEPTED/DEFERRALS row with reason *(deterministic)*
- [ ] `CAPSTONE_CLOSURE.md` carries the three-part list for signature, and its two sums and highest layer recompute from the matrix *(deterministic)*
- [ ] no MET-ENGINEERED row is counted as MET anywhere in the headline *(deterministic)*
- [ ] an ADR exists for every MET-DIFFERENTLY verdict and every SHOULD-level deviation *(deterministic)*
- [ ] *(live-read)* The artifact this row writes cites the live state it describes: the CI read of every open PR in the stack (`ci-boundary.sh --stack --no-wait` output with its `read_at` — BM-CI-01); where the build has a production surface, a probe-run record (id, `date -u`, result, sha256) no older than 24 h at the commit. A statement about production state with no such citation is removed, not written.
- [ ] verification green; every new behaviour has a test that fails if it is removed; requirement ids stamped in the PR; anything not automatically verifiable is a `DEFERRALS.md` row with its compensating control; ADRs written for every deviation and owned decision; `BUILD_INDEX.md` row and `LEDGER.md` advanced; operating clauses met — dates from the clock, PR checks read and recorded, AC layers stated, no living-record pins, protected records only appended, gate words verbatim, harness in the run-ledger header. *(agentic — the universal phase-gate AC)*

## Requirement IDs to satisfy and stamp in the PR
The closure ids of `{{spec_path}}` and any ids whose verdict this ticket moves to MET (matching `{{req_id_pattern}}`).

## Cross-cutting invariants
- Cited from `docs/tickets/00_MANIFEST.md § Cross-cutting invariants`.

## Operating clauses
- Cited from `docs/tickets/00_MANIFEST.md § Operating rules`; the gap table has one row per clause.

## Notes
- This ticket owns `CAPSTONE_CLOSURE.md` and the list for signature. `GATE-ACCEPT` is the next
  chain row (every tail); do not mark the build DONE here.
