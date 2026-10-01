<!--
  Template: docs/tickets/NN[a-z]_GATE-G<k>__<slug>.md — a GATE marker (BM-TICKET-05, BM-GATE-03).
  Written by: decompose-spec. A marker, NOT an implement-spec input: no run line. Executed by
  orchestrate-build (read/produce the readout, present it, record the operator's words, commit,
  continue or stop). Never guessed past. A decomposition never pre-answers it.
-->
# GATE-G<k> — <short title>

- **Kind:** gate · **Phase:** <phase>
- **Readout:** `docs/build/readouts/GATE-G<k>.md` (from `templates/READOUT.md`)

> **Milestone gate — NOT an `implement-spec` input.** The chain STOPS here until the operator
> dispositions the readout. Never guessed past. An operator or authorized human record supplies
> the decision; an agent must not sign or assume silence is approval.

## Criterion (verbatim from the spec)
<the go/no-go criterion, quoted verbatim from the spec §; thresholds pre-registered below>

## Pre-registered thresholds
<the numeric/boolean thresholds, fixed BEFORE the gated work — never moved to fit a result>

## DEFERRALS rule
This gate does not pass while any `OPEN` row in `DEFERRALS.md` scoped to this phase remains
(DEFERRALS rule 4).

## Disposition
Recorded only from the operator's own words, never ticked or signed by an agent: the readout
(READOUT shape) appends a Signature block with the decision verbatim and flips its `Status:` line to
PASSED | SKIPPED-BY-OPERATOR | NOT-PASSABLE (+ what would pass it); the same words, verbatim, go in
`docs/build/LEDGER.md` GATE DECISIONS (`kind: decision`).
