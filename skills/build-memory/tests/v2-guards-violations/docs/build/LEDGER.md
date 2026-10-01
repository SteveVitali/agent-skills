# Build ledger — the machine-state file

> **OPERATING MODE.** Fresh session: read this ledger, then `docs/tickets/00_MANIFEST.md`,
> then `docs/tickets/DEFERRALS.md`. Run the next chain row via `implement-spec`; a gate is a
> pause, not a block. Resume line:
> `implement-spec spec=docs/tickets/<nextTicket file> worktree=. base_branch=<chainTip>`
> - Legacy ledger lived at `.agents/scratch/demo-build-ledger.md` (gitignored).
> - Standing narrative line 000 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 001 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 002 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 003 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 004 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 005 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 006 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 007 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 008 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 009 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 010 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 011 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 012 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 013 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 014 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 015 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 016 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 017 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 018 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 019 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 020 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 021 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 022 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 023 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 024 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 025 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 026 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 027 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 028 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 029 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 030 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 031 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 032 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 033 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 034 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 035 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 036 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 037 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 038 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 039 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 040 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 041 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 042 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 043 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 044 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 045 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 046 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 047 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 048 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 049 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 050 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 051 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 052 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 053 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 054 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 055 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 056 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 057 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 058 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 059 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 060 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 061 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 062 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 063 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 064 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 065 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 066 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 067 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 068 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 069 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 070 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 071 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 072 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 073 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 074 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 075 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 076 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 077 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 078 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 079 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 080 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 081 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 082 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 083 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 084 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 085 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 086 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 087 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 088 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 089 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 090 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 091 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 092 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 093 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 094 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 095 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 096 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 097 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 098 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 099 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 100 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 101 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 102 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 103 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 104 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 105 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 106 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 107 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 108 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 109 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 110 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 111 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 112 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 113 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 114 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 115 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 116 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 117 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 118 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 119 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 120 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 121 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 122 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 123 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 124 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 125 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 126 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 127 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 128 that belongs in an archive, not in the orient region of the ledger head.
> - Standing narrative line 129 that belongs in an archive, not in the orient region of the ledger head.

## CURRENT STATE

```
projectStatus:   IN_PROGRESS
nextTicket:      T2
lastCompleted:   T1 # T1 landed | PRIOR: (none)
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
chainTip:        demo/t1-seed-schema # narrative narrative narrative narrative narrative narrative narrative narrative narrative narrative narrative narrative narrative narrative narrative narrative narrative narrative narrative narrative narrative narrative narrative narrative narrative narrative narrative narrative narrative narrative narrative narrative narrative narrative narrative narrative narrative narrative narrative narrative narrative narrative narrative narrative narrative narrative narrative narrative narrative narrative narrative narrative narrative narrative narrative narrative narrative narrative 
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

### Round 2

| date | ticket | gate | item | answer (verbatim) | consequence | kind |
|---|---|---|---|---|---|---|
| 2026-09-10T01:00:00Z | T2 | G1 | budget | "go ahead" (chat) | recorder: budget released | decided |
| 2026-09-10T01:05:00Z | T2 | G1 | all | "pre-approve everything for T2" (chat) | recorder: blanket rule | pre-authorization |

## PHASE LOG

- 2026-09-09 · Ledger created by decompose-spec from `docs/spec.md`; 2 tickets, tail omitted in fixture.
- 2026-09-09 — T1 done — demo/t1-seed-schema · PR #1 · demo/build · seed the schema · **Verify:** tests green · **Deferrals:** none · **Deviations:** none · chainTip → demo/t1-seed-schema · next → T2

## RETURN PASS

| ticket | gates | what the operator must do | re-run line |
|---|---|---|---|
