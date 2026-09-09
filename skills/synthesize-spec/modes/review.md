# synthesize-spec · mode: review (BM-SYNTH-04)

A **fresh-context adversarial pass** over the spec — the anti-bias mechanism, the same reason `implement-spec`
Pass 2 and `decompose-spec` Phase 4 run fresh. A context that just wrote the spec favours its own generations
(LLM self-preference bias); this pass is given the spec + the ledger, **not** the authoring history.

## Run it in a fresh context
Where the harness supports subagents, dispatch this as a fresh-context subagent (spec + ledger + brief only).
Where it doesn't, enforce the discipline manually: re-read the spec from disk in full and argue each finding from
what is on the page, not from memory of writing it.

## Hunt for
- **Internal consistency** — sections that contradict each other; a requirement whose id family or AC hook is
  wrong; reserved strings used two ways.
- **Coverage of every ledger row** — each `done` research/design row's implication and emitted `REQ-*` ids appear
  in the spec; each `OL-*` outline obligation is discharged (or consciously de-scoped).
- **MVP realism** — is the scope buildable in the intended rounds, or is it a wish-list? Flag scope that no
  ticket chain could land.
- **Self-contradiction of the spec's own claims** — a "must" in one section that a later section makes impossible.
- **Delta-only when a prior version exists** — for round ≥ 2, review only the delta paragraph's changes against
  the prior canonical version, plus anything they touch.

## Disposition every finding
Record each in **Appendix E** with the vocabulary `accept | adapt | rebut | defer` — the same disposition
vocabulary `respond-to-review` uses — with a one-line rationale. `accept`/`adapt` findings are folded into the
spec in this same pass (it is the author revising); `rebut` records why the spec stands; `defer` names when.

## Close
Update the ledger's `§O` review row to `done` (evidence = Appendix E), add a change-log line, route the hub to
`ratify`, and return. A spec with unresolved `accept` findings is not ready to ratify.
