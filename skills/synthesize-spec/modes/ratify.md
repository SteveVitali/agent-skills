# synthesize-spec · mode: ratify (BM-SYNTH-05)

The one place the operator's decisions are **required** — no spec goes `canonical` on the model's say-so. This is
the hand-off to `decompose-spec`.

## 1. Present the open questions
Gather every unanswered `§Q` row and every `⚑` constraint the research surfaced as still-open, plus any `review`
finding dispositioned `defer` that the operator should rule on. Present them as a numbered decision list. **Stop
and wait for the operator's answers** (this is a decision surface; `drive-build.sh` treats it as gate-pending —
exit 0, re-run after answers). If `operator_questions=false` the operator has pre-waived this; record that.

## 2. Record the answers
Write each answer into the `§Q` register (`decision` + `unblocks / new rows`), verbatim. An answer that opens new
work adds ledger rows (a second round) rather than being silently absorbed. Secrets are never recorded — a
credential is `provided: yes/no`.

## 3. Flip and freeze
- Flip the spec's `Status` to **canonical** (with the date and "ratified by the operator" + the Q ids resolved).
- Freeze the research ledger: a final `## Change log` line ("ledger frozen at ratification, round N"); set
  `projectStatus: DONE`. The ledger is now historical.

## 4. Write the hand-off `docs/decomposition-prompt.md`
The committed, frozen record of exactly how to decompose this spec:
- the exact `decompose-spec` invocation (`decompose-spec spec=<spec_out> build_name=<build_name>
  tickets_dir=docs/tickets tail=full …`);
- the project binding constraints (the `⚑` constraints, the reserved strings, the `req_id_pattern`, the
  cross-cutting invariants the decomposition must carry into every ticket);
- a pointer to the research index (Appendix C) and the outline trace.

## 5. Hand off
Print the run line for `decompose-spec` and stop. Do not decompose here — that is `decompose-spec`'s job, and it
begins the committed build memory (`build-memory init`, the manifest, the state-only ledger).
