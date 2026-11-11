# Deferred obligations ledger

> **Maintained companion — NOT a generated ticket.** Committed and hand-maintained; preserved
> across any ticket regeneration; never overwritten or deleted. No `NN_` prefix so it is not
> mistaken for a chain ticket.

The rules:
1. **Every run, first:** read this file. Closing any `OPEN` row this ticket or its landed
   prerequisites unblock is part of the run: verify, then flip to `DONE` with date + evidence.
2. **Never delete a row.** Flip `OPEN` → `DONE` / `WONTFIX` (with reason). History stays.
3. **When you defer something new,** append a row in the same run. A deferral not in this file did not happen.
4. **Gates refuse to pass** while any `OPEN` row scoped to that phase remains.

Status values: `OPEN` · `PARTIAL` · `DONE` · `WONTFIX` · `ACCEPTED-SKELETON`.

| id | item | why deferred | unblocked by | how to verify | proxy now | status |
|---|---|---|---|---|---|---|
| D-T1-1 | live schema round-trip | no live stage in fixture | operator stands up stage | run the round-trip | unit test | DONE |
| D-T2-1 | consumer perf budget | needs prod-shaped data | REC.1 | measure p95 | none | OPEN |
