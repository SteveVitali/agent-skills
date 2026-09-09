# reconcile-build · mode: backlog (BM-RECON-01)

Gather every owed thing into one backlog and state operational readiness. Invoked by the `REC.1` tail ticket.

## Gather the sources
Read the committed build memory and collect every open obligation:
- every `OPEN` / `PARTIAL` row in `docs/tickets/DEFERRALS.md`;
- every `## Revisit trigger` across `docs/adr/ADR-*.md`;
- every entry in the ledger's `## OPEN FINDINGS`;
- every deferred row in any spec-mandated register the project keeps (risk register, traceability, …);
- every non-`MET` row in `docs/build/COVERAGE_MATRIX.csv` (`PARTIAL` / `MISSING` / `AT-RISK-INTEGRATION`).

## Write `docs/build/BACKLOG.csv`
Columns exactly (from `skills/build-memory/templates/BACKLOG.csv`):
`bl_id, title, type, sources, req_ids, package, blocks, landing, gate, size, status`.
- `bl_id` = `BL-<nn>`, unique.
- **`sources`** — the ids this row absorbs. **Every gathered source id appears in exactly one row's `sources`
  cell** — that is the completeness contract `check-backlog.sh` enforces (zero occurrences = a dropped
  obligation; two = double-tracking).
- `landing` names the ticket / round / gate that will do it (or `accepted`); **no `TBD`**.
- `type` ∈ defect | deferred-feature | operational-prereq | rights/legal | docs-drift | schema-refinement |
  external-dep | process; `size` ∈ S | M | L; `status` ∈ open | closed | accepted.

Then verify:
```bash
bash scripts/check-backlog.sh docs/build/BACKLOG.csv docs/build docs/tickets   # exit 0 = complete + non-duplicating
```

## Write `docs/build/BACKLOG.md`
The same rows grouped by `landing` (a human reads this to see "what's left before X"), with the themes called out.

## Write `docs/build/OPERATIONAL_READINESS.md`
Capability × {code state, infra needed, human gate, owner} — one section per capability. Then the **critical
path**: an ordered list where **every step names a `ticket:` and a `proof:`** (the artifact that shows it done).
**No `TBD` anywhere** — an unknown is itself a backlog row with a `landing`, not a blank. Close with the cost /
risk posture if the build has one.

## Close
Report the backlog size, the readiness verdict, and any source that could not be placed (that is a finding, not
something to drop). The `REC.1` ticket's `implement-spec` run stamps its requirement ids and closes its ledger.
