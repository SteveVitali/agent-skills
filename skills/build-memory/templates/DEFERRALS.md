<!--
  Template: docs/tickets/DEFERRALS.md (BM-DEFER-01). Seeded by build-memory init; rows
  appended by implement-spec (and closed by later runs). Append-only companion — NOT a
  chain ticket, never overwritten or deleted. The four rules below are stated verbatim.
-->
# Deferred obligations ledger

> **Maintained companion — NOT a generated ticket.** Committed and hand-maintained; preserved
> across any ticket regeneration; never overwritten or deleted. It has no `NN_` sequence prefix
> so it is not mistaken for a chain ticket.

The rules:
1. **Every run, first:** read this file. If the ticket you are about to implement — or a
   prerequisite it depends on — unblocks any `OPEN` row, **closing that row is part of your
   run**: verify it for real, then flip it to `DONE` with the date and evidence.
2. **Never delete a row.** Flip `OPEN` → `DONE` (verified) or `WONTFIX` (with a reason).
   History stays.
3. **When you defer something new,** append a row here in the same run that defers it. A
   deferral that is not in this file did not happen.
4. **Gates refuse to pass** while any `OPEN` row scoped to that phase remains. Treat an open
   row as gate-blocking.

Status values: `OPEN` (owed) · `PARTIAL` · `DONE` (verified — add date + evidence) ·
`WONTFIX` (add reason) · `ACCEPTED-SKELETON` (intentionally minimal for now; revisit at the
named ticket). Optional `kind`: V (verification) | F (functionality) | D (deviation) |
H (handoff seam) | P (human prerequisite) | X (other).

Pre-existing normalized debt is tracked in `docs/build/BACKLOG.csv`; a row here cites its
`BL-` id where one exists (no duplication).

| id | item | why deferred | unblocked by | how to verify | proxy now | status |
|---|---|---|---|---|---|---|
