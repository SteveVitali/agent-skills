# Build ledger — the machine-state file

> **OPERATING MODE.** Fresh session: read this ledger, then `docs/tickets/00_MANIFEST.md`,
> then `docs/tickets/DEFERRALS.md`. Run the next chain row via `implement-spec`; a gate is a
> pause, not a block. Resume line:
> `implement-spec spec=docs/tickets/<nextTicket file> worktree=. base_branch=<chainTip>`

## CURRENT STATE

```
projectStatus:   IN_PROGRESS
nextTicket:      T2
lastCompleted:   T1
blockedOn:       (nothing)
pauseRequested:  false
returnPass:      (none)
manifest:        docs/tickets/00_MANIFEST.md
canonicalSpec:   docs/spec.md
memoryRoot:      docs/build
dispatchTarget:  manual
buildWorktree:   .
buildBranchBase: demo/build
pinnedBaseSha:   0000000000000000000000000000000000000000
chainTip:        demo/t1-seed-schema
benchmarkSet:    N/A
autonomy:        checkpoint
mergePolicy:     OPERATOR
round:           1
updatedAt:       2026-09-09
```

## OPEN FINDINGS

(none)

## GATE DECISIONS

| date | ticket | gate | item | answer | consequence |
|---|---|---|---|---|---|

## RETURN PASS

| ticket | gates | what the operator must do | re-run line |
|---|---|---|---|

## PHASE LOG

- 2026-09-09 · Ledger created by decompose-spec from `docs/spec.md`; 2 tickets, tail omitted in fixture.
- 2026-09-09 — T1 done — demo/t1-seed-schema · PR #1 · demo/build · seed the schema · **Verify:** tests green · **Deferrals:** none · **Deviations:** none · chainTip → demo/t1-seed-schema · next → T2
