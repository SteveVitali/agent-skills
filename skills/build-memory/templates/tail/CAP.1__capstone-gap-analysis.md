<!--
  Template: tail ticket CAP.1 (capstone gap analysis). Filled by: decompose-spec, at seed
  (appended as a tail row when the chain has more than one implement-spec ticket) or at
  extend. Placeholders {{build_name}} {{spec_path}} {{req_id_pattern}} {{ticket_count}}
  {{last_ticket}} are filled on instantiation. An ordinary implement-spec contract; it CITES
  the spec, never copies it.
-->
# CAP.1 — capstone gap analysis

- **Sequence:** capstone 1 · **Phase:** capstone · **Kind:** capstone
- **Tag:** capstone
- **base_branch:** current checkout
- **Depends on:** {{last_ticket}} (the last implement-spec ticket landed)
- **Run:** `implement-spec spec=docs/tickets/<file>.md gap_analysis=true live_verification=false`
- **Gate status:** none
- **Live stage:** none

> **Independence is the point.** This is the one place the build is judged as a *whole*. Do
> the verdicts in a fresh context, from the composed final tree and the spec — **before**
> reading any per-ticket run ledger — so a per-ticket lens cannot hide a cross-cutting gap.

## Goal
Prove, or disprove with evidence, that the composed build of {{ticket_count}} tickets
satisfies `{{spec_path}}` as a whole: one verdict per requirement, a coverage matrix, and a
seam hunt that a per-ticket gap analysis structurally cannot see.

## Load (read these — do not re-read others)
- `{{spec_path}}` in full (every §, every cross-cutting invariant, the out-of-scope list).
- `docs/tickets/00_MANIFEST.md` (the chain, the requirement-ID → ticket index, the invariants).
- The composed final tree: `git diff <pinnedBaseSha>...<chainTip>` and the real final files.
- `docs/tickets/DEFERRALS.md` (what was consciously owed). **Do not** read `docs/build/runs/*`
  until every verdict is recorded — that is the anti-bias rule.

## In scope — deliverables
1. `docs/build/COVERAGE_MATRIX.csv` — one row per requirement id, columns EXACTLY:
   `id, level, spec_section, class, verdict, evidence, owning_tickets, tests, adrs, routing, note,
   required_domain, achieved_domain, owed_legs, accepted_scope` (the last four appended, never
   renamed). `verdict` ∈ BM-VERDICT-01: MET / MET-DIFFERENTLY(ADR-nnn|RISK-id) /
   MET-ENGINEERED(D-id;…) / PARTIAL / MISSING / AT-RISK-INTEGRATION / WAIVED(ADR-nnn) /
   N/A-RATIONALE, parameters `;`-separated; domains are BM-STATUS-01 layer words; `evidence` is
   never blank for MET or MET-DIFFERENTLY (a `path:line`, a test node id, or an ADR id).
2. `docs/build/CAPSTONE_GAP_ANALYSIS.md` — method + commands; a roll-up by verdict and by
   requirement family; the **seam hunt** (inter-ticket seams, dual-owned fields, cross-cutting
   requirements "subsumed by" something else, any composed path never run green end-to-end);
   the top gaps with the routing decision for each (fix in CAP.3 / accept as deviation /
   defer with a `DEFERRALS.md` row). Satisfies the capstone requirements of `{{spec_path}}`.

## Out of scope
- Closing the gaps (CAP.3 owns closure) and composed execution (CAP.2 owns it). Reconciliation
  backlog/spec/integration (REC.1–REC.3 own those).

## Acceptance criteria
- [ ] every requirement id matching `{{req_id_pattern}}` has exactly one matrix row with a verdict *(deterministic)*
- [ ] every MET / MET-DIFFERENTLY row cites concrete evidence (path:line / test / ADR) *(deterministic)*
- [ ] every MET-DIFFERENTLY row names an existing ADR or RISK row that names the id *(deterministic)*
- [ ] every MET-ENGINEERED row has non-empty `owed_legs`, each an OPEN/PARTIAL D-row that names the id *(deterministic)*
- [ ] no MET row cites an OPEN/PARTIAL D-row, and `achieved_domain ≥ required_domain` for every MET row *(deterministic)*
- [ ] every WAIVED row names an accepted ADR that quotes the operator verbatim and has a `## Revisit trigger` *(deterministic)*
- [ ] the verdicts were recorded before any `docs/build/runs/*` was read (stated in the report) *(agentic)*
- [ ] *(live-read)* The artifact this row writes cites the live state it describes: the CI read of every open PR in the stack (`ci-boundary.sh` output once it ships — BM-CI-01; until then `gh pr checks <n>` with its `date -u`); where the build has a production surface, a probe-run record (id, `date -u`, result, sha256) no older than 24 h at the commit. A statement about production state with no such citation is removed, not written.
- [ ] verification green; every new behaviour has a test that fails if it is removed; requirement ids stamped in the PR; anything not automatically verifiable is a `DEFERRALS.md` row with its compensating control; ADRs written for every deviation and owned decision; `BUILD_INDEX.md` row and `LEDGER.md` advanced; operating clauses met — dates from the clock, PR checks read and recorded, AC layers stated, no living-record pins, protected records only appended, gate words verbatim, harness in the run-ledger header. *(agentic — the universal phase-gate AC)*

## Requirement IDs to satisfy and stamp in the PR
The capstone/gap-analysis ids of `{{spec_path}}` (matching `{{req_id_pattern}}`).

## Cross-cutting invariants
- Cited from `docs/tickets/00_MANIFEST.md § Cross-cutting invariants` — the matrix re-checks each.

## Operating clauses
- Cited from `docs/tickets/00_MANIFEST.md § Operating rules`; the gap table has one row per clause.

## Notes
- This ticket owns `COVERAGE_MATRIX.csv`'s column set and applies the BM-VERDICT-01 vocabulary;
  downstream tickets consume them by name and never rename columns. A scoped operator
  acceptance never raises a verdict (`accepted_scope` set ⇒ verdict ≤ MET-ENGINEERED).
