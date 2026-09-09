# reconcile-build · mode: spec (BM-RECON-02)

Reconcile what the build **did** with what the spec **said**, and fold the differences back into the source spec.
Invoked by the `REC.2` tail ticket. Proposals-only unless `apply_amendments=true`.

## Write `docs/build/TICKET_VS_SPEC.md`
For each landed chain row (from `BUILD_INDEX.md`), tag each deliverable it shipped:
- **in-spec** — the spec required it (cite the requirement id);
- **spec-implied** — a reasonable reading of the spec, not stated;
- **ticket-added** — the ticket introduced it beyond the spec.
Give each a disposition: `fold-back as a new id` / `note in an appendix` / `leave as an implementation detail`.
This is the evidence the reconciliation plan draws on.

## Write `docs/build/SPEC_RECONCILIATION_PLAN.md`
The amendments to apply to the **source** spec, each a row with: target file (the `spec_src/` fragment when the
spec is generated, else the spec file), anchor, before/after, and a tick box (`[ ]` → `[x]` when approved).
- Requirement ids are **append-only** — a fold-back gets a new id in its family, never a renumber.
- Record the ADR set vs the spec's ADR appendix: they must end equal (the validator checks this when the spec
  carries an appendix).

## Applying (only where ticked, only with `apply_amendments=true`)
For each **ticked** amendment: edit **through `spec_src/`** when the spec is generated (then run its `BUILD.sh`),
else the spec file directly; append a `## Spec amendments applied` line to the manifest (date · section ·
before/after · approver); and write an **ADR** for any design decision the amendment changes. Never edit an
executed ticket contract — a later note (`> Amended <date>:`) points at the manifest line. With
`apply_amendments=false` (default), write the plan and stop — the operator ticks and re-runs.

## Close
Report the counts (in-spec / spec-implied / ticket-added), the amendments proposed vs applied, and the ADR-set
delta. The `REC.2` ticket stamps its requirement ids and closes its ledger.
