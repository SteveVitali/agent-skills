<!--
  Template: tail ticket REC.3 (integration plan). Filled by: decompose-spec at seed/extend.
  Placeholders filled on instantiation. An ordinary implement-spec contract that invokes
  reconcile-build.
-->
# REC.3 — integration plan

- **Sequence:** reconcile 3 · **Phase:** reconcile · **Kind:** reconcile
- **Tag:** reconcile
- **base_branch:** current checkout
- **Depends on:** REC.2
- **Run:** `implement-spec spec=docs/tickets/<file>.md live_verification=false`
- **Gate status:** none
- **Live stage:** none

## Goal
Give the operator a copy-pasteable plan to land the stacked chain: the PR graph, a read-only
merge dry-run, strategies, rollback, post-merge verification, and the seed of the next round.

## Load (read these — do not re-read others)
- **Invoke `reconcile-build mode=integration`** and follow it completely.
- `docs/build/BUILD_INDEX.md` (the PR graph and bases), `docs/build/LEDGER.md` (`mergePolicy`,
  `chainTip`, `pinnedBaseSha`), `docs/build/BACKLOG.csv` (what lands later).

## In scope — deliverables
1. `docs/build/INTEGRATION_PLAN.md` — the PR graph; a **read-only** merge dry-run (never
   merges); merge strategies; a copy-pasteable operator procedure; rollback; post-merge
   verification.
2. A release-notes draft derived from `BUILD_INDEX.md`.
3. `docs/build/planning/<date -u +%F>_decision-memo.md` (skeleton) seeding the next
   `decompose-spec mode=extend` round.

## Out of scope
- Actually merging (the operator does that) and fixing CI (reading it is in scope — the
  *(live-read)* AC). The backlog (REC.1) and spec reconciliation (REC.2).

## Acceptance criteria
- [ ] `INTEGRATION_PLAN.md` shows the PR graph and a read-only merge dry-run that performs no merge *(deterministic)*
- [ ] a release-notes draft and a `planning/<date -u +%F>_decision-memo.md` seed exist *(deterministic)*
- [ ] *(live-read)* The artifact this row writes cites the live state it describes: the CI read of every open PR in the stack (`ci-boundary.sh --stack --no-wait` output with its `read_at` — BM-CI-01); where the build has a production surface, a probe-run record (id, `date -u`, result, sha256) no older than 24 h at the commit. A statement about production state with no such citation is removed, not written.
- [ ] verification green; every new behaviour has a test that fails if it is removed; requirement ids stamped in the PR; anything not automatically verifiable is a `DEFERRALS.md` row with its compensating control; ADRs written for every deviation and owned decision; `BUILD_INDEX.md` row and `LEDGER.md` advanced; operating clauses met — dates from the clock, PR checks read and recorded, AC layers stated, no living-record pins, protected records only appended, gate words verbatim, harness in the run-ledger header. *(agentic — the universal phase-gate AC)*

## Requirement IDs to satisfy and stamp in the PR
The integration ids of `{{spec_path}}` (matching `{{req_id_pattern}}`).

## Cross-cutting invariants
- Cited from `docs/tickets/00_MANIFEST.md § Cross-cutting invariants`. The dry-run is read-only;
  it never merges.

## Operating clauses
- Cited from `docs/tickets/00_MANIFEST.md § Operating rules`; the gap table has one row per clause.

## Notes
- This ticket owns `INTEGRATION_PLAN.md` and seeds the next round's `planning/` memo.
