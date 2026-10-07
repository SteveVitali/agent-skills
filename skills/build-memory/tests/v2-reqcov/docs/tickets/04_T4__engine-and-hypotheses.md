# T4 — engine and hypotheses

- **Sequence:** 4 of 4 · **Phase:** wiring · **Kind:** ticket · **base_branch:** current checkout
- **Depends on:** T2
- **Run:** `implement-spec spec=docs/tickets/04_T4__engine-and-hypotheses.md`
- **Gate status:** none · **Live stage:** offline-only

## Goal
engine and hypotheses.

## Load (read these — do not re-read others)
- The spec §2; T1's schema.

## In scope — deliverables
1. engine and hypotheses (BM-HYP-2, BM-ENG-3).

## Out of scope
- The schema shape (owned by T1).

## Acceptance criteria
- [ ] consumers read the schema *(deterministic)*
- [ ] verification green; every new behaviour has a test; requirement ids stamped; deferrals recorded; ADRs written; BUILD_INDEX row and LEDGER advanced *(agentic)*

## Requirement IDs to satisfy and stamp in the PR
BM-HYP-2, BM-ENG-3.

## Cross-cutting invariants
- Additive / back-compat.

## Notes
Consumes T1's schema.
