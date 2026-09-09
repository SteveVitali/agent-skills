<!--
  Template: tail ticket REC.2 (spec reconciliation). Filled by: decompose-spec at seed/extend.
  Placeholders filled on instantiation. An ordinary implement-spec contract that invokes
  reconcile-build.
-->
# REC.2 — spec reconciliation

- **Sequence:** reconcile 2 · **Phase:** reconcile · **Kind:** reconcile
- **Tag:** reconcile
- **base_branch:** current checkout
- **Depends on:** REC.1
- **Run:** `implement-spec spec=docs/tickets/<file>.md live_verification=false`
- **Gate status:** none
- **Live stage:** none

## Goal
Reconcile what the build actually shipped with `{{spec_path}}`: tag every landed deliverable,
propose the amendments that fold reality back into the spec, and apply only the ticked ones.

## Load (read these — do not re-read others)
- **Invoke `reconcile-build mode=spec`** and follow it completely.
- `{{spec_path}}` (and its `spec_src/` + `BUILD.sh` if it is generated), `docs/build/BUILD_INDEX.md`,
  each landed ticket's deliverables, `docs/adr/` (the ADR set), the manifest amendment log.

## In scope — deliverables
1. `docs/build/TICKET_VS_SPEC.md` — each landed ticket's deliverables tagged
   in-spec / spec-implied / ticket-added, each with a disposition (fold-back as a new id /
   note in an appendix / leave as implementation detail).
2. `docs/build/SPEC_RECONCILIATION_PLAN.md` — proposed amendments with target file, anchor,
   before/after, and a tick state; fold-back ids appended to their families; the ADR set vs
   the spec's ADR appendix. Amendments are applied **only where ticked**, always through
   `spec_src/` when it exists, each with a manifest `## Spec amendments applied` line and an ADR.

## Out of scope
- The backlog (REC.1) and integration plan (REC.3). Applying unticked amendments.

## Acceptance criteria
- [ ] every landed ticket's deliverables are tagged and dispositioned in `TICKET_VS_SPEC.md` *(deterministic)*
- [ ] applied amendments are exactly the ticked ones, each with a manifest amendment line + ADR, through `spec_src/` when present *(deterministic)*
- [ ] the ADR set equals the spec's ADR appendix (or the difference is a dispositioned row) *(deterministic)*
- [ ] verification green; every new behaviour has a test that fails if it is removed; requirement ids stamped in the PR; anything not automatically verifiable is a `DEFERRALS.md` row with its compensating control; ADRs written for every deviation and owned decision; `BUILD_INDEX.md` row and `LEDGER.md` advanced. *(agentic — the universal phase-gate AC)*

## Requirement IDs to satisfy and stamp in the PR
The spec-reconciliation ids of `{{spec_path}}` (matching `{{req_id_pattern}}`).

## Cross-cutting invariants
- Cited from `docs/tickets/00_MANIFEST.md § Cross-cutting invariants`. Amend the source, never
  a generated spec artifact directly.

## Notes
- This ticket owns `TICKET_VS_SPEC.md` and `SPEC_RECONCILIATION_PLAN.md`.
