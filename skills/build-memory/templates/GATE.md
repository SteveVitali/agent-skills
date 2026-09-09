<!--
  Template: docs/tickets/NN[a-z]_GATE-G<k>__<slug>.md — a GATE marker (BM-TICKET-05, BM-GATE-03).
  Written by: decompose-spec. A marker, NOT an implement-spec input: no run line. Executed by
  orchestrate-build (read/produce the readout, present it, record the disposition, commit,
  continue or stop). Never guessed past.
-->
# GATE-G<k> — <short title>

- **Kind:** gate · **Phase:** <phase>
- **Readout:** `docs/build/readouts/GATE-G<k>.md`

> **Milestone gate — NOT an `implement-spec` input.** The chain STOPS here until the operator
> dispositions the readout. Never guessed past.

## Criterion (verbatim from the spec)
<the go/no-go criterion, quoted verbatim from the spec §; thresholds pre-registered below>

## Pre-registered thresholds
<the numeric/boolean thresholds, fixed BEFORE the gated work — never moved to fit a result>

## DEFERRALS rule
This gate does not pass while any `OPEN` row in `DEFERRALS.md` scoped to this phase remains
(DEFERRALS rule 4).

## Disposition
- [ ] Operator disposition recorded in `docs/build/LEDGER.md` GATE DECISIONS and in the
      readout as PASSED | SKIPPED-BY-OPERATOR | NOT PASSABLE (+ what would pass it).
