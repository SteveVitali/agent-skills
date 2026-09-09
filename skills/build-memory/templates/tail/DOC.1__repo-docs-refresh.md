<!--
  Template: tail ticket DOC.1 (repo-docs refresh). Filled by: decompose-spec at seed/extend.
  Placeholders filled on instantiation. An ordinary implement-spec contract that invokes
  refresh-repo-docs (the human-facing docs).
-->
# DOC.1 — repo docs refresh

- **Sequence:** docs 1 · **Phase:** docs · **Kind:** docs
- **Tag:** docs
- **base_branch:** current checkout
- **Depends on:** REC.3
- **Run:** `implement-spec spec=docs/tickets/<file>.md live_verification=false`
- **Gate status:** none
- **Live stage:** none

## Goal
Converge {{build_name}}'s human-facing docs onto what the composed build actually does, so a
reader following the README/guides/examples gets a correct result.

## Load (read these — do not re-read others)
- **Invoke `refresh-repo-docs`** and follow it completely, honoring `docs/README.md`'s mode
  table (`generated` → fix source/regenerate; `frozen`/`historical`/`append-only` →
  report-only; `docs/tickets/` and `docs/build/` default to historical).
- `docs/build/BUILD_INDEX.md` and `docs/build/COVERAGE_MATRIX.csv` for what shipped.

## In scope — deliverables
1. README(s), `docs/` (living), CHANGELOG, guides, examples corrected against the composed
   build — stale fixed, cruft removed, gaps filled, every claim verified against the code.

## Out of scope
- Agent-facing docs (`AGENTS.md` / `CLAUDE.md`) — DOC.2 owns those. Historical/frozen build
  memory is report-only, never rewritten.

## Acceptance criteria
- [ ] `refresh-repo-docs`' detector reports no broken references after the run *(deterministic)*
- [ ] every changed claim is verified against the current code (no fabricated content) *(agentic)*
- [ ] verification green; every new behaviour has a test that fails if it is removed; requirement ids stamped in the PR; anything not automatically verifiable is a `DEFERRALS.md` row with its compensating control; ADRs written for every deviation and owned decision; `BUILD_INDEX.md` row and `LEDGER.md` advanced. *(agentic — the universal phase-gate AC)*

## Requirement IDs to satisfy and stamp in the PR
The docs ids of `{{spec_path}}`, if any (matching `{{req_id_pattern}}`).

## Cross-cutting invariants
- Cited from `docs/tickets/00_MANIFEST.md § Cross-cutting invariants`. Never hand-edit a
  generated doc; fix its source and regenerate.

## Notes
- Runs after reconciliation so the docs describe the reconciled build, not a mid-flight state.
