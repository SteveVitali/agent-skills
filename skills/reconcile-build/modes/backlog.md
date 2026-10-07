# reconcile-build · mode: backlog (BM-RECON-01)

Gather every owed thing into one backlog and state operational readiness. Invoked by the `REC.1` tail ticket.

## Gather the sources
Read the committed build memory and collect every open obligation:
- every `OPEN` / `PARTIAL` row in `docs/tickets/DEFERRALS.md`;
- every `## Revisit trigger` across `docs/adr/ADR-*.md`;
- every entry in the ledger's `## OPEN FINDINGS`;
- every deferred row in any spec-mandated register the project keeps (risk register, traceability, …);
- the owed rows of `docs/build/COVERAGE_MATRIX.csv`, by verdict (BM-VERDICT-01; the matrix is CSV with quoted
  cells, verdict parameters `;`-separated):
  - `PARTIAL`, `MISSING`, `AT-RISK-INTEGRATION` — gathered by their id;
  - `MET-ENGINEERED(D-…)` — covered by its owed-leg D-rows (gathered above); each must still be OPEN/PARTIAL,
    otherwise the row is a `stale MET-ENGINEERED` to re-verdict;
  - `WAIVED(ADR-nnn)` — covered by that ADR's revisit-trigger row;
  - `MET-DIFFERENTLY` — not gathered (its ADR is); `MET` and `N/A-RATIONALE` — not gathered, and a `MET` row that
    cites an OPEN/PARTIAL D-row is an issue (it is MET-ENGINEERED until the leg is done).

## Write `docs/build/BACKLOG.csv`
Columns exactly (from `skills/build-memory/templates/BACKLOG.csv`):
`bl_id, title, type, sources, req_ids, package, blocks, landing, gate, size, status`.
- `bl_id` = `BL-<nn>`, unique.
- **`sources`** — the ids this row absorbs. **Every gathered source id appears in exactly one row's `sources`
  cell** — that is the completeness contract `check-backlog.sh` enforces (zero occurrences = a dropped
  obligation; two = double-tracking).
- `landing` names the ticket / round / gate that will do it (or `accepted`); **no `TBD`**.
- **Home liveness:** a source's row is `open` (or `accepted`) while the source itself is owed — a trigger or an
  OPEN deferral never sits on a `closed` row.
- `type` ∈ defect | deferred-feature | operational-prereq | rights/legal | docs-drift | schema-refinement |
  external-dep | process; `size` ∈ S | M | L; `status` ∈ open | closed | accepted.

Then verify:
```bash
bash scripts/check-backlog.sh docs/build/BACKLOG.csv docs/build docs/tickets   # exit 0 = complete, non-duplicating, live homes, verdict-consistent, sums = CAP.3
```
Exit 1 = issues (including `inputs`: no `DEFERRALS.md` in the tickets directory, or a build directory other
than the backlog's own); exit 2 = no backlog / a missing directory; **exit 3 = 0 expected ids gathered** — the
script refuses to call an empty gather complete (it is almost always a wrong path). Pass `--allow-empty` only for
a build that truly owes nothing. Never pipe the call (`| tail`) without `set -o pipefail`: a pipe hides the code.

## Write `docs/build/BACKLOG.md`
The same rows grouped by `landing` (a human reads this to see "what's left before X"), with the themes called out.
Then the **REC sweeps**, each dated with `date -u` when you run it:
- **Revisit-trigger sweep** — every ADR's `## Revisit trigger` evaluated this round, one line each:
  `ADR-NNN — quiet | fired-unanswered | fired-answered | superseded | dormant — <evidence read>`; a
  `fired-unanswered` trigger is itself a backlog row.
- **Risk register** — where the project keeps one, append a dated `## Round <n> review` section (never edit the
  rows above it).
- **The two sums** — *engineering closed* = MET + MET-DIFFERENTLY + MET-ENGINEERED and *requirement satisfied* =
  MET + MET-DIFFERENTLY, recomputed from the matrix (`check-backlog.sh` prints them) and compared with CAP.3's
  headline; a difference is a finding, never a quiet correction.

## Write `docs/build/OPERATIONAL_READINESS.md`
Capability × {code state, infra needed, human (owner, date), highest layer reached (BM-STATUS-01), proof} — one
section per capability. Then the **critical path**: an ordered list where **every step names a `ticket:` and a
`proof:`** (the artifact that shows it done). **No `TBD` anywhere** — an unknown is itself a backlog row with a
`landing`, not a blank — and **no production claim without a citation**: a probe-run record (id, `date -u`,
result, sha256) or a `ci-boundary.sh` read no older than 24 h at the commit. A claim you cannot cite is removed,
not written (BM-TAIL-04). Close with the cost / risk posture if the build has one.

## Close
Report the backlog size, the readiness verdict, and any source that could not be placed (that is a finding, not
something to drop). The `REC.1` ticket's `implement-spec` run stamps its requirement ids and closes its ledger.
