<!--
  Template: docs/tickets/NN[a-z]_HUMAN-H<k>__<slug>.md — a HUMAN marker (BM-TICKET-05).
  Written by: decompose-spec. A marker, NOT an implement-spec input: no run line. Its
  checkboxes are living state — ticked (with a date) by the operator or by orchestrate-build
  when the ledger records the item done. A done-but-unticked marker is a validator warning.
-->
# HUMAN-H<k> — <short title>

- **Kind:** human · **Phase:** <phase>
- **Blocks:** <the ticket ids that cannot complete until this is done>

> **Operator work — NOT an `implement-spec` input.** These are actions only the operator can
> take (account registration, procurement, outreach, a credential). The chain never silently
> blocks on this: a code ticket that reaches it before it is done records the gated remainder
> as `DEFERRALS.md` rows and continues (see the DEFERRALS rule below).

## Checklist
- [ ] <operator action> <!-- tick with a date + evidence pointer when done -->

## Exit criterion
<what makes this HUMAN row complete>

## DEFERRALS rule for tickets that run before this completes
A ticket that depends on this row but runs before it is ticked opens a `D-<TICKET>-<n>` row
in `DEFERRALS.md` (why deferred = "H<k> pending", unblocked-by = "H<k>", how-to-verify) and
reports "gate pending" — never a failure, never a fabricated pass.
