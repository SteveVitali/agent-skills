<!--
  Template: docs/tickets/NN[a-z]_HUMAN-H<k>__<slug>.md — a HUMAN marker (BM-TICKET-05).
  Written by: decompose-spec. A marker, NOT an implement-spec input: no run line. Scheduled like a
  ticket (owner + date or trigger). Its checkboxes are living state — ticked (with `date -u +%F`) by
  the operator, or by orchestrate-build when the ledger records the operator's words that the item is
  done. A done-but-unticked marker is a validator warning.
-->
# HUMAN-H<k> — <short title>

- **Kind:** human · **Phase:** <phase>
- **Blocks:** <the ticket ids that cannot complete until this is done>
- **Owner:** <named person or role>   **Scheduled:** <date -u +%F target, or the trigger ticket>
- **Withheld until done:** <the public or recorded claims that must not be made while this is open>
- **Deferrals so far:** 0   <!-- a second deferral stops the chain for an explicit operator choice -->
- **Readout:** `docs/build/readouts/HUMAN-H<k>.md` (from `templates/READOUT.md`)

> **Operator work — NOT an `implement-spec` input.** These are actions only the operator can
> take (account registration, procurement, outreach, a credential). An operator or authorized
> human record supplies the decision; an agent must not sign or assume silence is approval.
> Code tickets may proceed past this row only by opening D-rows that cite it and name the claims
> they withhold. The row itself is never skipped by default. Deferring it again needs the
> operator's explicit words: keep with a new date, amend the spec, or waive by ADR.

## Checklist
- [ ] <operator action> <!-- tick with `date -u +%F` + evidence pointer when done -->

## Exit criterion
<what makes this HUMAN row complete>

## DEFERRALS rule for tickets that run before this completes
A ticket that depends on this row but runs before it is ticked opens a `D-<TICKET>-<n>` row
(kind `P`) in `DEFERRALS.md` — why deferred = "H<k> pending · withholds: <claim>", unblocked by =
"H<k> · owner: <who> · trigger: <date -u +%F | ticket id>", how to verify — and reports "gate
pending": never a failure, never a fabricated pass, never a claim this row withholds (DEFERRALS
rule 5).
