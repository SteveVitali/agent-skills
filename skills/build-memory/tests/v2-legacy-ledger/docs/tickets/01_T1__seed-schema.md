# T1 — seed the schema

- **Sequence:** 1 of 2 · **Phase:** schema · **Kind:** ticket · **base_branch:** current checkout
- **Depends on:** nothing
- **Run:** `implement-spec spec=docs/tickets/01_T1__seed-schema.md`
- **Gate status:** none · **Live stage:** offline-only

## Goal
Seed the schema.

## Load (read these — do not re-read others)
- The spec §1.

## In scope — deliverables
1. The schema file (BM-DEMO-01).

## Out of scope
- Wiring the consumers (owned by T2).

## Acceptance criteria
- [ ] schema parses *(deterministic)*
- [ ] verification green; every new behaviour has a test; requirement ids stamped; deferrals recorded; ADRs written; BUILD_INDEX row and LEDGER advanced *(agentic)*

## Requirement IDs to satisfy and stamp in the PR
BM-DEMO-01.

## Cross-cutting invariants
- Additive / back-compat.

## Notes
Owns the schema shape.
