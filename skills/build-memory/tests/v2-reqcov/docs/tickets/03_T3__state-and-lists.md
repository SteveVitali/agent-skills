# T3 — state versions and lists

- **Sequence:** 3 of 4 · **Phase:** wiring · **Kind:** ticket · **base_branch:** current checkout
- **Depends on:** T2
- **Run:** `implement-spec spec=docs/tickets/03_T3__state-and-lists.md`
- **Gate status:** none · **Live stage:** offline-only

## Goal
state versions and lists.

## Load (read these — do not re-read others)
- The spec §2; T1's schema.

## In scope — deliverables
1. state versions and lists (BM-STATE-3, BM-LIST-2).

## Out of scope
- The schema shape (owned by T1).

## Acceptance criteria
- [ ] consumers read the schema *(deterministic)*
- [ ] verification green; every new behaviour has a test; requirement ids stamped; deferrals recorded; ADRs written; BUILD_INDEX row and LEDGER advanced *(agentic)*

## Requirement IDs to satisfy and stamp in the PR
BM-STATE-3, BM-LIST-2.

## Cross-cutting invariants
- Additive / back-compat.

## Notes
Consumes T1's schema.
