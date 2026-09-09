<!--
  Template: docs/build/LEDGER.md — the machine-state file (BM-LEDGER-01..07).
  Seeded by: decompose-spec via build-memory init. Advanced by: implement-spec at ticket
  close (CURRENT STATE + PHASE LOG). GATE DECISIONS / RETURN PASS / OPEN FINDINGS: orchestrate-build.
  STATE ONLY — the manifest is the plan (no PHASE PLAN / invariants / SETUP / CAPSTONE here).
  Keep the CURRENT STATE keys in EXACTLY this order; the reader strips trailing # comments.
-->
# Build ledger — the machine-state file

> **OPERATING MODE.** Fresh session: read this ledger, then `docs/tickets/00_MANIFEST.md`,
> then `docs/tickets/DEFERRALS.md`. Run the row named by `nextTicket` via `implement-spec`;
> a gate is a pause, not a block. Resume line:
> `implement-spec spec=docs/tickets/<nextTicket file> worktree=<buildWorktree> base_branch=<chainTip>`

## CURRENT STATE

```
projectStatus:   NOT_STARTED        # NOT_STARTED | IN_PROGRESS | BLOCKED | PAUSED | DONE
nextTicket:      SETUP
lastCompleted:   (none)
blockedOn:       (nothing)          # REAL blocks only; a pending gate is a RETURN PASS row
pauseRequested:  false
returnPass:      (none)
manifest:        docs/tickets/00_MANIFEST.md
canonicalSpec:   <path to the spec>
memoryRoot:      docs/build
dispatchTarget:  <subagent|headless|manual>
buildWorktree:   (set at SETUP)
buildBranchBase: (set at SETUP)
pinnedBaseSha:   (set at SETUP)
chainTip:        (set at SETUP; advances per completed chained ticket)
benchmarkSet:    (id | PENDING_CREATE | N/A)
autonomy:        (set by orchestrate-build)
mergePolicy:     OPERATOR           # NONE | OPERATOR | AUTO-BOTTOM-UP
round:           1
updatedAt:       <date>
```

## OPEN FINDINGS

(none — carry cross-ticket findings here; not per-ticket blocks)

## GATE DECISIONS

| date | ticket | gate | item | answer | consequence |
|---|---|---|---|---|---|

## RETURN PASS

| ticket | gates | what the operator must do | re-run line |
|---|---|---|---|

## PHASE LOG

- <date> · Ledger created by decompose-spec from `<spec>`; <N> tickets; plan revisable at run time.
