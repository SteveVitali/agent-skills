# T2 — wire the consumers

- **Sequence:** 2 of 2 · **Phase:** wiring · **Kind:** ticket · **base_branch:** current checkout
- **Depends on:** T1
- **Run:** `implement-spec spec=docs/tickets/02_T2__wire-consumers.md`
- **Gate status:** none · **Live stage:** offline-only

## Goal
Wire the consumers to the schema.

## Load (read these — do not re-read others)
- The spec §2; T1's schema.

## In scope — deliverables
1. The consumers (BM-DEMO-02).

## Out of scope
- The schema shape (owned by T1).

## Acceptance criteria
- [ ] consumers read the schema *(deterministic)*
- [ ] verification green; every new behaviour has a test; requirement ids stamped; deferrals recorded; ADRs written; BUILD_INDEX row and LEDGER advanced *(agentic)*

## Requirement IDs to satisfy and stamp in the PR
BM-DEMO-02.

## Cross-cutting invariants
- Additive / back-compat.

## Notes
Consumes T1's schema.
