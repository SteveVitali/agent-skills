---
name: reconcile-build
license: MIT
description: "The closeout procedures the tail REC.* tickets invoke — backlog + operational readiness, spec reconciliation, and the integration plan — for a multi-session build. Use it when a build's tickets have landed and the tail rows (from decompose-spec) call 'invoke reconcile-build mode=…', the way P22.x tickets called refresh-repo-docs. Reads the committed build memory (DEFERRALS, ADRs, OPEN FINDINGS, the coverage matrix, BUILD_INDEX) and writes the backlog / reconciliation / integration artifacts. Not a sequencer and not a merge tool."
inputs:
  - name: mode
    required: true
    description: "'backlog' (BACKLOG.csv/.md + OPERATIONAL_READINESS.md), 'spec' (TICKET_VS_SPEC.md + SPEC_RECONCILIATION_PLAN.md), or 'integration' (INTEGRATION_PLAN.md + release notes + next-round memo)."
  - name: ledger
    required: false
    description: "Path to docs/build/LEDGER.md (default: resolved via build-memory memory-root.sh)."
  - name: manifest
    required: false
    description: "Path to docs/tickets/00_MANIFEST.md (default: the ledger's manifest: key)."
  - name: apply_amendments
    required: false
    description: "[spec mode] Default false = write proposals only. true = apply the ticked amendments through spec_src, add the manifest amendment line + ADR."
---

# Reconcile Build

Hold the **closeout procedures** a multi-session build runs after its tickets land — so they live in one place
with their templates and checkers, and the tail `REC.*` tickets just say *"invoke `reconcile-build mode=…`"*
(the way the docs tickets say "invoke `refresh-repo-docs`"). Folding these into `orchestrate-build` would push
that SKILL past the line ceiling and mix sequencing with content; this skill is the content.

> **Precedent.** `agent-docs` / `refresh-repo-docs` own the docs procedures the `DOC.*` tickets invoke;
> `reconcile-build` owns the reconciliation procedures the `REC.*` tickets invoke. It reads and writes the
> committed build memory defined in `skills/build-memory/layout.md` (it cites that file, does not restate it):
> `DEFERRALS.md`, `docs/adr/`, the ledger's `OPEN FINDINGS`, `COVERAGE_MATRIX.csv`, `BUILD_INDEX.md`, and the
> `BACKLOG.*` / `*_PLAN.md` / `OPERATIONAL_READINESS.md` outputs under `docs/build/`.

## Orient
Resolve the memory root (`build-memory` `memory-root.sh`); confirm `docs/build/` exists and the validator is
green (`check-build-memory.sh .`) before reconciling — reconciliation over an inconsistent layout is noise. Then
follow the mode.

## The modes

| Mode | File | Produces |
|---|---|---|
| `backlog` | [modes/backlog.md](modes/backlog.md) | `docs/build/BACKLOG.csv`, `BACKLOG.md`, `OPERATIONAL_READINESS.md` — every owed thing in exactly one row; readiness with a proof on every critical-path step. |
| `spec` | [modes/spec.md](modes/spec.md) | `docs/build/TICKET_VS_SPEC.md`, `SPEC_RECONCILIATION_PLAN.md` — what the build did vs what the spec said, and the amendments to fold back. |
| `integration` | [modes/integration.md](modes/integration.md) | `docs/build/INTEGRATION_PLAN.md`, a release-notes draft, and a `planning/<date>_decision-memo.md` seeding the next round. |

## The one discipline that matters

**Every owed thing lands in exactly one backlog row.** The failure mode of build closeout is debt that is
"tracked" in five places and therefore nowhere. `backlog` gathers every source — each `OPEN`/`PARTIAL` deferral,
each ADR revisit trigger, each `OPEN FINDINGS` entry, each spec-mandated register's deferred row, each non-`MET`
coverage-matrix row — into a single `sources` cell, and `scripts/check-backlog.sh` fails if any source appears
zero times or more than once. That is the backlog's contract: complete and non-duplicating.

## Scripts (bash 3.2+, read-only)

| Script | Role |
|---|---|
| `scripts/check-backlog.sh` | verify the backlog is complete + non-duplicating; ids unique; statuses valid |
| `scripts/merge-dryrun.sh` | report, per chain PR/branch, whether a clean merge is possible — **never merges** |

## What this skill does NOT do

- **No sequencing** — `orchestrate-build` runs the `REC.*` tickets; this skill is what they invoke.
- **No merging, no CI, no release** — `merge-dryrun.sh` is read-only; the actual merge/release is the operator's,
  from the copy-pasteable procedure `integration` writes.
- **No silent spec edits** — `spec` writes proposals; it applies an amendment only where the plan is ticked and
  `apply_amendments=true`, always through `spec_src` when it exists, with a manifest amendment line + an ADR.
