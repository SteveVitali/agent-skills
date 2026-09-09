<!--
  Template: tail ticket DOC.2 (agent-docs refresh). Filled by: decompose-spec at seed/extend.
  Placeholders filled on instantiation. An ordinary implement-spec contract that invokes
  agent-docs (the AGENTS.md hierarchy).
-->
# DOC.2 — agent docs refresh

- **Sequence:** docs 2 · **Phase:** docs · **Kind:** docs
- **Tag:** docs
- **base_branch:** current checkout
- **Depends on:** DOC.1
- **Run:** `implement-spec spec=docs/tickets/<file>.md live_verification=false`
- **Gate status:** none
- **Live stage:** none

## Goal
Converge {{build_name}}'s agent-facing docs (the AGENTS.md hierarchy) onto the composed build,
including the "Build memory" section, so a fresh agent can start productive work cold.

## Load (read these — do not re-read others)
- **Invoke `agent-docs`** (refresh mode) and follow it completely.
- The composed final tree; `docs/build/README.md` (the build-memory marker) so the
  "Build memory" section is generated where the marker is present.

## In scope — deliverables
1. The AGENTS.md hierarchy refreshed against the composed build, including a "Build memory"
   section (where `docs/tickets`, `00_MANIFEST.md`, `DEFERRALS.md`, `BUILD_INDEX.md` and ADRs
   live; "read `DEFERRALS.md` first every run" as a Critical Gotcha; the append-only and
   stacked-PR rules).

## Out of scope
- Human-facing docs (DOC.1 owns those). Architectural decisions (agent-docs documents what IS).

## Acceptance criteria
- [ ] `agent-docs`' freshness detector reports 0 critical issues after the run *(deterministic)*
- [ ] the AGENTS.md "Build memory" section is present in a repo carrying the marker *(deterministic)*
- [ ] verification green; every new behaviour has a test that fails if it is removed; requirement ids stamped in the PR; anything not automatically verifiable is a `DEFERRALS.md` row with its compensating control; ADRs written for every deviation and owned decision; `BUILD_INDEX.md` row and `LEDGER.md` advanced. *(agentic — the universal phase-gate AC)*

## Requirement IDs to satisfy and stamp in the PR
The agent-docs ids of `{{spec_path}}`, if any (matching `{{req_id_pattern}}`).

## Cross-cutting invariants
- Cited from `docs/tickets/00_MANIFEST.md § Cross-cutting invariants`.

## Notes
- The last tail row. After it lands and every gate is signed, `projectStatus: DONE` per BM-TAIL-03.
