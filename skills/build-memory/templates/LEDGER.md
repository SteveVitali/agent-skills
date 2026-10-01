<!--
  Template: docs/build/LEDGER.md — the machine-state file (BM-LEDGER-01..08).
  Seeded by: decompose-spec via build-memory init. Advanced by: implement-spec at ticket
  close (CURRENT STATE + PHASE LOG). GATE DECISIONS / RETURN PASS / OPEN FINDINGS: orchestrate-build.
  STATE ONLY — the manifest is the plan (no PHASE PLAN / invariants / SETUP / CAPSTONE here).
  Keep the CURRENT STATE keys in EXACTLY this order (`harness` is optional, only in its slot);
  values only: one line per key, <= 256 B, no `| PRIOR` history. The orient region (down to
  ## OPEN FINDINGS) stays <= 12 KiB. The head is living-archived: text removed beyond a value
  update is archived byte-for-byte under docs/build/reports/ledger-archive/ in the same commit,
  with a pointer comment. Every other region only appends. Every date: `date -u` at writing (BM-CLOCK-01).
-->
# Build ledger — the machine-state file
<!-- archive pointer slot (fill only when head text is archived): Archived <what> → docs/build/reports/ledger-archive/<file>, sha256 <64 hex> -->

> **OPERATING MODE.** Fresh session: read this ledger, then `docs/tickets/00_MANIFEST.md`,
> then `docs/tickets/DEFERRALS.md`. Run the row named by `nextTicket` via `implement-spec`;
> a gate is a pause, not a block. Resume line:
> `implement-spec spec=docs/tickets/<nextTicket file> worktree=<buildWorktree> base_branch=<chainTip>`
> - **Orient (BM-ORIENT-01):** read `sed -n '1,/^## OPEN FINDINGS/p'` of this file, the RETURN PASS table, its last three PHASE LOG entries, and the next row's manifest line + contract header — never this file, DEFERRALS or BUILD_INDEX whole.
> - **Clock (BM-CLOCK-01):** every date you write is `date -u` at that moment.
> - **CI (BM-CI-01):** read the PR checks at every ticket boundary (`ci-boundary.sh --ledger <this file> --ticket <lastCompleted> --stack`); red, pending or unreadable → `blockedOn`; never stack on red.

## CURRENT STATE

```
projectStatus:   NOT_STARTED        # NOT_STARTED | IN_PROGRESS | BLOCKED | PAUSED | DONE
nextTicket:      SETUP
lastCompleted:   (none)
blockedOn:       (nothing)          # REAL blocks only; a pending gate is a RETURN PASS row
pauseRequested:  false
returnPass:      (none)             # comma-separated ticket ids only
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
harness:         (set by the driving session)   # optional: <harness>/<model-id>/<tier>
updatedAt:       <date -u +%FT%TZ, at writing>
```

## OPEN FINDINGS

(none — carry cross-ticket findings here; not per-ticket blocks)

## GATE DECISIONS

<!-- Append rows at the END, newest last. date = `date -u +%FT%TZ` at receipt; answer = the operator's
     exact words in quotes + channel; consequence = the recorder's labelled reading; kind ∈ decision |
     pre-authorization | confirmation | waiver | correction. A decomposition never writes a decision row. -->
| date | ticket | gate | item | answer (verbatim) | consequence | kind |
|---|---|---|---|---|---|---|

## RETURN PASS

| ticket | gates | what the operator must do | re-run line |
|---|---|---|---|

## PHASE LOG — Round 1

<!-- The LAST region and the only append target: new entries go at EOF; a new round opens
     `## PHASE LOG — Round <n>`. One entry per event, <= 2 KiB, no markup before the kind:
     `<date -u +%F> — <ID> <kind> — branch · PR · base · summary · **Verify:** … · **Deferrals:** … · **Deviations:** … · chainTip → … · next → …`
     with optional `· ci: … · layer: … · harness: …`. kind ∈ done | blocked | inserted | split | gate |
     pause | round | correction | restored | repair | harness-switch | retroactive. -->

- <date -u +%F> — ROUND1 round — Ledger created by decompose-spec from `<spec>`; <N> tickets; tail=<minimal|full>; plan revisable at run time.
