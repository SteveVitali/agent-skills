<!--
  Template: tail marker GATE-ACCEPT. Filled by: decompose-spec at seed/extend. This is a GATE
  marker, NOT an implement-spec input — orchestrate-build executes it, never guessed past.
  Placeholders filled on instantiation.
-->
# GATE-ACCEPT — operator signs the accepted-deviations list

> **Milestone gate — NOT an `implement-spec` input.** The chain STOPS here after CAP.3 until
> the operator dispositions the accepted-deviations list. Never guessed past.

- **Kind:** gate · **Phase:** capstone
- **Blocks:** `projectStatus: DONE` (BM-TAIL-03) and REC.1–REC.3 that assume signed deviations.

## Criterion (verbatim)
The operator has reviewed the ACCEPTED-deviations list in `docs/build/CAPSTONE_CLOSURE.md`
(from CAP.3) and signed each row as accepted, or sent a row back to closure. A build of
{{ticket_count}} tickets against `{{spec_path}}` is not DONE while any proposed deviation is
unsigned.

## Readout
`docs/build/readouts/GATE-ACCEPT.md` — append-only: the list presented, the operator's
per-row disposition (ACCEPTED / SEND-BACK + what would accept it), verdict
(PASSED | NOT PASSABLE | SKIPPED-BY-OPERATOR), date, and the operator's disposition line.
`orchestrate-build` records the answers in `LEDGER.md § GATE DECISIONS` and commits on the
chain tip.

## Pre-registered thresholds
Every row in the CAP.3 ACCEPTED-deviations list is signed (accepted) or returned to closure;
no proposed deviation is left unsigned.

## Deferrals rule
This gate refuses to pass while any `OPEN` row in `docs/tickets/DEFERRALS.md` scoped to the
capstone phase remains (`DEFERRALS.md` rule 4).

## Disposition
- [ ] Operator disposition recorded in `docs/build/LEDGER.md` § GATE DECISIONS and `docs/build/readouts/GATE-ACCEPT.md`.
