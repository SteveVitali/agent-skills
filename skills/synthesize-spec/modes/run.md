# synthesize-spec · mode: run (BM-SYNTH-02)

Execute **exactly one** open ledger row in this (fresh) context, write its note, and stop — the loop advances to
the next row. This is the upstream analogue of `orchestrate-build`'s "one ticket per fresh context."

## The unit
1. Read `docs/research-ledger.md`; take the row named by `nextUnit`. Mark it `in-progress`.
2. **Do the work.** Read-only research/design **fan-out is allowed inside a row** (a row may itself spawn
   read-only subagents over sources/subsystems and synthesise their returns) — but a row writes exactly one note
   and only *writes* stay single-threaded.
   - A `⚑` operator constraint on the row is fixed — research *within* it, do not relitigate it.
   - If the row cannot proceed without an operator decision, set its status `blocked-on-operator`, add/So update
     the `§Q` row, set `blockedOn` accordingly, and stop (this is a decision surface, not a failure).
3. **Write the note** under `docs/research/` (research) or `docs/design/` (design) as `NN_<slug>.md`, per
   `docs/research/CONVENTIONS.md` (from `skills/build-memory/templates/research-CONVENTIONS.md`). Every material
   claim uses the finding format:
   - **Claim** — one sentence.
   - **Status** — `VERIFIED | PARTIALLY VERIFIED | UNVERIFIED | CONTRADICTED | INACCESSIBLE`.
   - **Evidence** — the URL(s) actually fetched and what they said (nothing cited that was not read).
   - **Retrieved** — the date.
   - **Implication for the spec** — what the design must do about it.
   - **Outline delta** — `CONFIRMS | CORRECTS | EXTENDS | CONTRADICTS §x` of the outline.
   The note ends with `## Open questions` and `## Spec requirements emitted` — numbered `REQ-<STREAM>-<n>` ids the
   synthesis will fold into the spec's requirement index.

## Close the row
Flip the row to `done` with its evidence (the note path), append any new `§Q` questions and any `⚑` the operator
must resolve, add a change-log line, advance `nextUnit` to the next open row (or, if none remain, to the first
`§O` synthesis unit and set the hub to route to `synthesize`), bump `updatedAt`, and return to the hub. **Never
mark a row done without a note that carries its evidence.**
