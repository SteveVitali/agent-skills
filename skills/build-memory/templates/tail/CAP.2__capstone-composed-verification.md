<!--
  Template: tail ticket CAP.2 (capstone composed verification). Filled by: decompose-spec at
  seed/extend. Placeholders filled on instantiation. An ordinary implement-spec contract.
-->
# CAP.2 — capstone composed verification

- **Sequence:** capstone 2 · **Phase:** capstone · **Kind:** capstone
- **Tag:** capstone
- **base_branch:** current checkout
- **Depends on:** CAP.1
- **Run:** `implement-spec spec=docs/tickets/<file>.md`
- **Gate status:** none
- **Live stage:** operator-gated: <budget>   <!-- set to none/offline-only when the build has no runtime surface -->

> Each additive ticket only ever exercised its own slice; the fully-composed path may never
> have run green. This ticket runs the **whole build as one unit**.

## Goal
Exercise the composed build of {{ticket_count}} tickets end-to-end and record the result, so
"{{build_name}} works as a whole" is proven empirically, not inferred from per-ticket greens.

## Load (read these — do not re-read others)
- `docs/build/CAPSTONE_GAP_ANALYSIS.md` and `docs/build/COVERAGE_MATRIX.csv` (CAP.1's output —
  especially the AT-RISK-INTEGRATION rows and the seam hunt).
- `{{spec_path}}` § acceptance criteria and integration invariants.
- `docs/tickets/DEFERRALS.md` (the consciously-unwired seams).

## In scope — deliverables
1. A composed-final-state verification exercising the fully-wired path the additive tickets
   never covered — unit/integration and, where the build has one, the composed runtime run.
2. `docs/build/COMPOSED_E2E_REPORT.md` — what was driven, what was observed, and why it proves
   the behaviour; every unwired seam is an `xfail`/skip whose reason **starts with a
   `DEFERRALS.md` id**; an environment-blocked composed run is recorded (the exact blocker +
   what would close it) and routed to the operator — **never a fabricated green**.

## Out of scope
- Closing new gaps found here (route them to CAP.3). Reconciliation (REC.*).

## Acceptance criteria
- [ ] the composed path runs green, or every non-green is an xfail/skip whose reason starts with a `D-*` id *(deterministic)*
- [ ] `COMPOSED_E2E_REPORT.md` records commands + observed signals for each composed scenario *(agentic)*
- [ ] any environment block is recorded with what would close it and routed to the operator *(agentic)*
- [ ] verification green; every new behaviour has a test that fails if it is removed; requirement ids stamped in the PR; anything not automatically verifiable is a `DEFERRALS.md` row with its compensating control; ADRs written for every deviation and owned decision; `BUILD_INDEX.md` row and `LEDGER.md` advanced. *(agentic — the universal phase-gate AC)*

## Requirement IDs to satisfy and stamp in the PR
The composed-verification / integration ids of `{{spec_path}}` (matching `{{req_id_pattern}}`).

## Cross-cutting invariants
- Cited from `docs/tickets/00_MANIFEST.md § Cross-cutting invariants`.

## Notes
- This ticket owns `COMPOSED_E2E_REPORT.md`. Never mutate canonical/production state; use
  tagged/throwaway fixtures and clean up shared-store records from a written list.
