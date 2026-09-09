# synthesize-spec · mode: synthesize (BM-SYNTH-03)

Write the spec **from the notes** (not from context): every research/design row is `done` and carries a note
with emitted `REQ-*` ids and outline deltas. Synthesis composes those into one self-contained spec.

## Write `spec_out` (default `docs/<build_name>-spec.md`)
Use `skills/build-memory/templates/spec-front-matter.md` for the head, then the body:

- **Front-matter block** — `Status`/version (start `Draft for operator review`), a one-paragraph **delta** vs the
  prior version (or "initial"), **Synthesized from** (the notes + the brief, by path), **Supersedes** (what this
  overrides on any point of disagreement).
- **§0 How to read** — one self-contained spec; the **contracts adopted by reference** as normative; the section
  map; the diagram/wireframe conventions.
- **§0.2 Requirement-ID convention** — `REQ-<FAMILY>-<n>`, **append-only**, the reserved-id note, and the
  `req_id_pattern` (the ERE `decompose-spec`/the validator will use, e.g. `REQ-[A-Z]+-[0-9]+`). Fold every note's
  emitted `REQ-<STREAM>-<n>` ids into the families here, verbatim.
- **A decision register** — the synthesis rulings that resolved conflicts between notes.
- **Body sections** — organised by the streams (product, UI/UX, systems, …), each requirement carrying its id.
- **Appendices** — **A** requirement index (id → section, with AC hooks); **B** decision register (the `Q-*`
  questions and their rulings); **C** research index (every note by id); **D** glossary + reserved strings;
  **E** review dispositions (seeded empty; `review` fills it).

## With a brief (outline_trace on)
Maintain `docs/OUTLINE_TRACE.md`: each `OL-*` obligation → the spec section that discharges it (or a conscious
de-scope to raise in `ratify`). Add a spec appendix proving the spec is a **superset** of the brief — every `OL-*`
is covered or explicitly dropped with a reason. An uncovered `OL-*` is a synthesis gap, not something to leave silent.

## Close
Update the ledger's `§O` synthesis row to `done` (evidence = the spec path), add a change-log line, set the hub
to route to `review` (unless `adversarial_review=false`, then `ratify`), and return.
