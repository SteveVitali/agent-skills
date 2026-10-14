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

| id | item | kind | unblocked by | status |
|---|---|---|---|---|
| D-T9-1 | done-led cell whose dated tail says open | P | — | **DONE (2026-01-02):** landed — prior: **OPEN — 2026-01-01.** owed then |
| D-T9-2 | compound-token row (the never-flip shape) | P | — | **DONE-code** — 2026-01-01: confirmed open → leg owed. 2026-01-02: landed; DONE. |
| D-T9-3 | partial-led cell with done tail | P | — | **PARTIAL — 2026-01-03:** head DONE; tail legs owed, stays PARTIAL |
| D-T9-4 | dropped row | P | — | **WONTFIX (2026-01-04):** DROPPED 2026-01-04: mooted by an election |
| D-T9-5 | skeleton-led cell with done tail | P | — | **ACCEPTED-SKELETON (2026-01-05):** thin slice; a DONE leg sits in the tail |
| D-T9-6 | honestly owed, scheduled | P | owner: op · trigger: t | **OPEN — 2026-01-06.** owed and scheduled |
| D-T9-7 | done-led cell citing a passed gate | A | — | **DONE (2026-01-07):** the GATE-G1-scoped leg discharged — prior: **OPEN — 2026-01-01** GATE-G1 tail |
| D-T9-8 | honestly owed, unscheduled | P | — | **OPEN — 2026-01-08.** owed |
| D-T9-9 | honestly partial, unscheduled | P | — | **PARTIAL — 2026-01-09.** owed |
