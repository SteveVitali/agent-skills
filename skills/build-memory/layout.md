# Build memory — the layout contract

This is the single source of truth for where build memory lives, what each file is, how
it may change, and who writes it. **Every other skill cites this file and does not restate
the tree.** (`decompose-spec`, `orchestrate-build`, `implement-spec`, `synthesize-spec`,
`reconcile-build`, `agent-docs`, `refresh-repo-docs`.)

Build memory is **committed** — the record of a multi-session build is audit-valuable, and
git is already the artifact store. Only regenerable bulk (`logs/`) is gitignored. A repo
opts in with one marker; a repo without it runs in **legacy scratch mode**, byte-for-byte
the pre-0.2.0 behaviour (see §Compatibility).

---

## The tree (BM-LAYOUT-01)

```
<repo>/
├── AGENTS.md                         # + a "Build memory" section (BM-DOCS-01)
├── docs/
│   ├── README.md                     # docs map with a mode column (BM-DOCS-02)
│   ├── brief.md                      # S0 (optional; frozen)
│   ├── research-ledger.md            # S1–S3 work list + Q register (living until ratified, then frozen)
│   ├── research/  design/            # numbered notes; research/CONVENTIONS.md
│   ├── <spec>.md  [spec_src/ + BUILD.sh]   # canonical spec (generated if spec_src exists)
│   ├── decomposition-prompt.md       # the committed hand-off (frozen)
│   ├── adr/                          # README.md (generated) · _TEMPLATE.md · ADR-NNN-<slug>.md
│   ├── tickets/                      # contracts: the record of what was owed
│   │   ├── 00_MANIFEST.md · _TEMPLATE.md · DEFERRALS.md
│   │   ├── NN[a-z]?_<ID>__<slug>.md              # implement-spec contracts
│   │   └── NN[a-z]_HUMAN-H<k>__<slug>.md · NN[a-z]_GATE-G<k>__<slug>.md   # marker docs
│   └── build/                        # the memory root: the record of what happened
│       ├── README.md                 # contains `<!-- build-memory: v2 -->`
│       ├── LEDGER.md                 # the machine-state file (§ LEDGER)
│       ├── BUILD_INDEX.md            # one row per landed ticket (§ Build index)
│       ├── runs/<ID>.md              # implement-spec run ledgers
│       ├── pr/<ID>.md                # PR bodies as submitted
│       ├── readouts/GATE-G<k>.md     # gate readouts (append-only)
│       ├── planning/                 # re-planning rounds: <date>_planning-ledger.md, <date>_decision-memo.md
│       ├── reports/                  # project-specific reports a ticket produces
│       ├── tools/                    # validators + one-off generators (committed)
│       ├── fixtures/                 # small scratch fixtures (size-capped)
│       ├── logs/                     # gitignored: `*` + `!.gitignore`; drive-build/ under it
│       ├── COVERAGE_MATRIX.csv · CAPSTONE_GAP_ANALYSIS.md · COMPOSED_E2E_REPORT.md · CAPSTONE_CLOSURE.md
│       └── BACKLOG.csv · BACKLOG.md · TICKET_VS_SPEC.md · SPEC_RECONCILIATION_PLAN.md · INTEGRATION_PLAN.md · OPERATIONAL_READINESS.md
```

The named entries above are the **only** allowed entries at the root of `docs/build/`; the
validator flags anything else (BM-LAYOUT-01). `docs/build/logs/` is the one gitignored
subtree, by a checked-in `docs/build/logs/.gitignore` containing `*` and `!.gitignore`
(BM-LAYOUT-03). Fixtures over 1 MB and any single file over 5 MB under `docs/build/` are
flagged; logs are never committed (BM-LAYOUT-04). No file under `docs/build/` or
`docs/tickets/` contains a secret — the validator greps for common token shapes and fails
on a hit; ledgers record `provided: yes/no` for credentials, never values (BM-LAYOUT-05).

### Modes (how a file may change)

| Mode | Meaning |
|---|---|
| **generated** | Derived from other files by a script; never hand-edited (`adr/README.md`). |
| **frozen** | Written once, then immutable (`brief.md`, `decomposition-prompt.md`, executed contracts). |
| **append-only** | Rows/entries added, never removed or rewritten (`DEFERRALS.md`, `GATE DECISIONS`, `PHASE LOG`, readouts, ADR set). |
| **historical** | A record of what happened; corrected by a new entry, not an edit (`docs/build/`, `docs/tickets/`). |
| **living** | Edited in place until frozen (`research-ledger.md` until ratified; `LEDGER.md` state). |

### Ids and filenames (BM-LAYOUT-02)

- **Ticket ids** match `^(HUMAN-H|GATE-G)?[A-Z]+[0-9]*(\.[0-9]+[a-z]?)?$`. Canonically that is:
  a marker id `HUMAN-H<k>` / `GATE-G<k>` (prefix + digits), **or** an ordinary id
  `<LETTERS><digits?>` with an optional dotted sub-part and an optional trailing letter.
  Examples: `T1`, `T12a`, `P0.15b`, `PRB.04`, `CAP.1`, `REC.2`, `DOC.1`, `MAINT.1`,
  `HUMAN-H0`, `GATE-G1`. `GATE-ACCEPT` is the one named gate marker (the operator's
  accepted-deviations signature, BM-TAIL-01) and is also accepted.
- **Filenames** match `^[0-9]{2,3}[a-z]?_<ID>__[a-z0-9-]+\.md$`. Lexical order is chain order;
  a run-time insert uses a suffix letter (`16a_…`, `16b_…`).
- **Legacy filenames** (e.g. `P00.1__slug.md`) are accepted when the manifest chain table
  lists them: historical contracts are never renamed (BM-COMPAT-05).

---

## The memory root (BM-ROOT-01, BM-ROOT-02)

`scripts/memory-root.sh [worktree]` prints two lines — `mode=<committed|scratch>` and
`root=<absolute path>` — resolved as:

1. `$BUILD_MEMORY_ROOT` if set → `committed`, that path.
2. `<worktree toplevel>/docs/build` if its `README.md` contains `<!-- build-memory: v2 -->`
   → `committed`.
3. otherwise `scratch`, `root=${AGENT_SCRATCH_DIR:-<parent of git-common-dir>/.agents/scratch}`
   (today's rule, unchanged).

Every build skill obtains the root from this script. Resolution always uses the **current
worktree**, so a sibling build worktree reads the ledger on its own chain tip, never the
main worktree's copy (BM-ROOT-02 — the sibling-worktree defect ADR-058 records).

---

## `LEDGER.md` — the machine-state contract (§4)

Sections, in order (BM-LEDGER-01): an `OPERATING MODE` blockquote (the verbatim resume
prompt for a fresh session), `## CURRENT STATE`, `## OPEN FINDINGS`, `## GATE DECISIONS`,
`## RETURN PASS`, `## PHASE LOG`. **No plan sections** — the manifest is the plan
(`manifest:` key points at it).

`CURRENT STATE` (BM-LEDGER-02) is a fenced `key: value` block with exactly these keys, in
this order (trailing `# comments` allowed; the reader strips them):

```
projectStatus    # NOT_STARTED | IN_PROGRESS | BLOCKED | PAUSED | DONE
nextTicket
lastCompleted
blockedOn
pauseRequested
returnPass
manifest
canonicalSpec
memoryRoot
dispatchTarget
buildWorktree
buildBranchBase
pinnedBaseSha
chainTip
benchmarkSet
autonomy
mergePolicy      # NONE | OPERATOR | AUTO-BOTTOM-UP
round            # integer, starts 1
updatedAt
```

- `blockedOn` is reserved for **real** blocks (red verification, missing dependency, missing
  infrastructure the operator refused). A pending human gate is never a block; it is a
  `RETURN PASS` row (BM-LEDGER-03).
- `GATE DECISIONS` is an append-only table `| date | ticket | gate | item | answer | consequence |`.
  Secrets never; `provided: yes/no` only (BM-LEDGER-04).
- `RETURN PASS` is a table `| ticket | gates | what the operator must do | re-run line |`;
  `returnPass:` lists the same ticket ids (BM-LEDGER-05).
- `PHASE LOG` entries are append-only, newest last, one per event, of the fixed shape
  (BM-LEDGER-06):
  `- <date> — <TICKET> <done|blocked|inserted|split|gate|pause|round> — branch · PR · base · one-line summary · **Verify:** … · **Deferrals:** opened/closed ids · **Deviations:** … · chainTip → … · next → …`
- `drive-build.sh` parses `projectStatus`, `nextTicket`, `pauseRequested`, `blockedOn`,
  `buildWorktree`, `returnPass`, `manifest` with the never-fail reader; unknown keys are
  ignored; a legacy ledger without the new keys still drives (BM-LEDGER-07).

---

## Manifest, ticket, markers, skeletons (§5)

**Manifest (`docs/tickets/00_MANIFEST.md`, BM-MANIFEST-01)** — sections in order: title +
three banners (committed contract record; cite-don't-copy with the spec amendment protocol;
deferrals companion); `## How to build` (the stacked-chain recipe and the four rules: table
order; stay on the previous branch; stop at GATE rows; never let a code ticket block on a
HUMAN row; the run-line pattern; how `orchestrate-build` drives it); `## Human prerequisites`
(H-rows); `## The chain` (table `| # | file | phase | kind | scope | gate |`, `kind` ∈
ticket | human | gate | skeleton | capstone | reconcile | docs, marker rows interleaved);
`## Milestone gates` (thresholds quoted verbatim); `## Phase gates & ownership notes`;
`## Cross-cutting invariants`; `## Out of scope`; `## Requirement-ID → ticket index`;
`## Spec amendments applied` (append-only: date, section, before/after or pointer, approver,
ADR); `## Decomposition decisions` (incl. the Phase-4 adversarial review record);
`## Plan extensions` (append-only: inserts, splits, rounds).

- The manifest is complete on its own: a human with a terminal can drive the chain from it
  without the ledger (BM-MANIFEST-02).
- Inserting at run time uses filename suffix letters (`16a_…`) and a `## Plan extensions`
  line; splitting produces `<ID>a`, `<ID>b` files and marks the original
  `superseded-by-split` in the chain table (the original file is kept). A file in
  `docs/tickets/` that is neither a chain row nor a listed companion is a validator error
  (BM-MANIFEST-03).
- A `companions:` line under the banners lists non-chain files kept in `docs/tickets/`
  (default `DEFERRALS.md`, `_TEMPLATE.md`; a project may add audit/readout companions). The
  validator accepts exactly those (BM-MANIFEST-04).
- An optional `req_id_pattern:` line gives the spec's requirement-id ERE, driving the REQ
  coverage check.

**Ticket (`docs/tickets/_TEMPLATE.md`, BM-TICKET-01)** — header bullets: `Sequence: <n> of <N>`
(an inserted ticket uses its filename prefix, e.g. `16e of 50`) · `Phase` · `Kind` · `Tag`
(optional) · `base_branch: current checkout` · `Depends on` · `Run:` (the exact
`implement-spec` line incl. per-ticket flags) · `Gate status:` (operator ticks, or `none`) ·
`Live stage:` (none | offline-only | operator-gated: <budget>). Body sections: `## Goal` ·
`## Load (read these — do not re-read others)` · `## In scope — deliverables` (numbered;
each names the requirement ids it satisfies) · `## Out of scope` (names the owning ticket) ·
`## Acceptance criteria` (each tagged *(deterministic)* or *(agentic)*; the last is the
universal phase-gate AC) · `## Requirement IDs to satisfy and stamp in the PR` ·
`## Cross-cutting invariants` (cited from the manifest) · `## Notes`.

- The universal phase-gate AC reads (BM-TICKET-02): "verification green; every new behaviour
  has a test that fails if it is removed; requirement ids stamped in the PR; anything not
  automatically verifiable is a `DEFERRALS.md` row with its compensating control; ADRs
  written for every deviation and owned decision; `BUILD_INDEX.md` row and `LEDGER.md`
  advanced."
- A skeleton ticket carries `Kind: skeleton`, a `> Skeleton only` banner naming the gate
  after which the body is written, and only the header, `## Scope (one line)`, `## Spec §§`
  and `## REQ coverage`. The validator refuses a run line for a skeleton; `implement-spec`
  MUST stop if asked to run one (BM-TICKET-03).
- Executed contracts are never rewritten; a later amendment appends a dated note
  (`> Amended <date>: …`) pointing at the manifest amendment line (BM-TICKET-04).

**Markers (BM-TICKET-05)** — `HUMAN-H<k>`: the operator work as a checklist, exit criterion,
which tickets it blocks, and the DEFERRALS rule for tickets that run before it completes; its
checkboxes are living state, ticked (with a date) by the operator or by `orchestrate-build`
when the ledger records the item done (a demonstrably-done-but-unticked marker is a validator
warning). `GATE-G<k>`: the criterion verbatim from the spec, the readout path
`docs/build/readouts/GATE-G<k>.md`, the rule "never guessed past", the pre-registered
thresholds, and the DEFERRALS rule (no OPEN row scoped to the phase).

**Tail rows (BM-TAIL-01..03)** — when the chain has more than one implement-spec ticket,
`decompose-spec` appends, from `templates/tail/`: `CAP.1` gap analysis (independent fresh
context; verdicts MET / MET-DIFFERENTLY / PARTIAL / MISSING / AT-RISK-INTEGRATION before
reading any run ledger; `COVERAGE_MATRIX.csv` with columns
`id, level, spec_section, class, verdict, evidence, owning_tickets, tests, adrs, routing, note`;
seam hunt; `CAPSTONE_GAP_ANALYSIS.md`), `CAP.2` composed verification (whole build as one
unit; unwired seams are `xfail`/skips whose reason starts with a DEFERRALS id;
`COMPOSED_E2E_REPORT.md`), `CAP.3` closure (`CAPSTONE_CLOSURE.md` with the ACCEPTED-deviations
list), `GATE-ACCEPT` marker (operator signs), `REC.1` backlog + readiness, `REC.2` spec
reconciliation, `REC.3` integration plan, `DOC.1` repo-docs refresh (invokes
`refresh-repo-docs`), `DOC.2` agent-docs refresh (invokes `agent-docs`). `tail=full` (default)
| `minimal` (`CAP.1`, `CAP.3`, `DOC.1`, `DOC.2`); `tail=none` is refused when N > 1. Tail
templates carry placeholders (`{{build_name}}`, `{{spec_path}}`, `{{req_id_pattern}}`,
`{{ticket_count}}`, `{{last_ticket}}`) that `decompose-spec` fills; the instantiated files are
ordinary chain rows with `kind` capstone | reconcile | docs. `projectStatus: DONE` requires
every chain row landed or consciously skipped (recorded), `BUILD_INDEX.md` complete, no `OPEN`
deferral without a `landing`, and the `GATE-ACCEPT` readout signed.

---

## Deferrals, ADRs, build index, readouts (§6)

**`docs/tickets/DEFERRALS.md` (BM-DEFER-01)** — the header states the four rules verbatim:
read first every run; never delete a row; a deferral not in the file did not happen; gates
refuse to pass with an `OPEN` row scoped to the phase. Row schema:
`| id | item | why deferred | unblocked by | how to verify | proxy now | status |`; `id` =
`D-<TICKET>-<n>`; `status` ∈ OPEN | PARTIAL | DONE | WONTFIX | ACCEPTED-SKELETON; an optional
`kind` column ∈ V | F | D | H | P | X. `implement-spec` Phase 0.3 reads it; closing any row
this ticket or its landed prerequisites unblock is in scope; a live check that cannot run
because a `Live stage` is operator-gated or infrastructure is absent records an OPEN row
(proxy, unblocked-by, how-to-verify) and reports "gate pending" — never a failure, never a
fabricated pass (BM-DEFER-02).

**ADRs (BM-ADR-01..02)** — `docs/adr/ADR-NNN-<slug>.md`: H1 `# ADR-NNN: <title>`; header
bullets `Status` (Proposed | Accepted | Superseded by ADR-MMM), `Date`, `Ticket`,
`Requirement ids`, `Spec`; sections `## Context`, `## Decision`, `## Consequences`,
`## Alternatives considered`, `## Revisit trigger`. Decisions are immutable; a change is a new
ADR; a retro-fitted record says so in its title. `docs/adr/README.md` is generated by
`scripts/adr-index.sh` (numeric order; columns ADR · Title · Ticket · Status) and carries
`<!-- generated by build-memory adr-index; do not edit -->`; the validator regenerates and
diffs. `implement-spec` writes an ADR for every MET-DIFFERENTLY verdict, every SHOULD-level
deviation, and every decision its ticket's `## Notes` says it owns; the ADR lands in the same
PR (BM-ADR-03). When the spec carries an ADR appendix/index, the validator checks the two sets
are equal (BM-ADR-04).

**`docs/build/BUILD_INDEX.md` (BM-INDEX-01)** — one row per landed chain row:
`| seq | ticket | kind | branch | PR | base | landed | ADRs | deferrals opened → closed | live verification (run / fixture-only / n-a / gate-pending) | evidence |`,
where `evidence` points at `runs/<ID>.md#evidence` or `pr/<ID>.md`. Written by the worker at
close, never reconstructed later. `docs/build/runs/<ID>.md` is the implement-spec run ledger:
`Spec / Base / Branch / Config`, `## Deferrals read`, `## Requirements`, `## Acceptance
criteria`, `## Plan`, `## Test matrix`, `## Progress`, `## Gap table`, `## Evidence log`,
`## Evidence report` (the text submitted as the PR body) (BM-INDEX-02). `docs/build/pr/<ID>.md`
is the PR body as submitted (`gh pr create --body-file`). Gate readouts
`docs/build/readouts/GATE-G<k>.md` are append-only: criterion, per-item evidence, verdict
(PASSED | NOT PASSABLE | SKIPPED-BY-OPERATOR), date, operator disposition (BM-INDEX-03).

---

## Gate protocol (§7, BM-GATE-01..04)

- Before dispatching a ticket whose `Gate status` block has unticked items,
  `orchestrate-build` pauses (in `checkpoint`/`manual`; in `auto` it treats all items as
  "skip"), presents the block, records each answer in `GATE DECISIONS`, commits `LEDGER.md`
  on the chain tip, and dispatches with the prompt line "Gate answers are in
  `docs/build/LEDGER.md` GATE DECISIONS — copy them into the ticket's Gate status block in
  your first commit and act on them" (BM-GATE-01).
- An answer of "skip" runs the ticket ungated: everything up to the gate, the gated remainder
  as `DEFERRALS.md` rows, its PR opened, and a `RETURN PASS` row with the re-run line.
  Re-running after ticking is idempotent (BM-GATE-02).
- A `GATE-G<k>` marker row is executed by `orchestrate-build`: read (or produce) the readout,
  present it, record the disposition (PASSED / SKIPPED-BY-OPERATOR / NOT PASSABLE + what would
  pass it), commit, continue or stop. Never guessed past (BM-GATE-03).
- `drive-build.sh` exits 0 with "gate pending — answer in LEDGER.md GATE DECISIONS and re-run"
  when the only obstacle is a gate under `checkpoint`/`manual`; exit 2 remains for real blocks
  (BM-GATE-04).

---

## Who writes what (§8)

| Artifact | Writer | When |
|---|---|---|
| `docs/build/README.md`, `LEDGER.md` (seed), `BUILD_INDEX.md` (header), `logs/.gitignore`, `docs/README.md` rows, `docs/adr/{README,_TEMPLATE}.md`, `docs/tickets/{00_MANIFEST,_TEMPLATE,DEFERRALS}.md`, tickets, markers, tail rows, `docs/decomposition-prompt.md` | `decompose-spec` via `build-memory init` | seed / extend |
| `runs/<ID>.md`, `pr/<ID>.md`, ADRs, `DEFERRALS.md` rows, `BUILD_INDEX.md` row, `LEDGER.md` close (CURRENT STATE + PHASE LOG), `reports/*`, project registers the spec mandates | `implement-spec` | per ticket, two commits: code+docs, then `docs(build): close <ID>` |
| `LEDGER.md` GATE DECISIONS / RETURN PASS / OPEN FINDINGS / pause / insert / split; `readouts/GATE-G<k>.md` | `orchestrate-build` | at boundaries, committed on the chain tip |
| `COVERAGE_MATRIX.csv`, `CAPSTONE_*.md`, `COMPOSED_E2E_REPORT.md` | `CAP.*` tickets (workers) | tail |
| `BACKLOG.*`, `TICKET_VS_SPEC.md`, `SPEC_RECONCILIATION_PLAN.md`, `INTEGRATION_PLAN.md`, `OPERATIONAL_READINESS.md` | `REC.*` tickets via `reconcile-build` | tail |
| `docs/research-ledger.md`, `research/*`, `design/*`, the spec, `decomposition-prompt.md` | `synthesize-spec` | upstream |
| `planning/<date>_*.md` | `reconcile-build` (seed) and `decompose-spec mode=extend` | next round |

---

## The validator (§10, BM-VALID-01..02)

`scripts/check-build-memory.sh [repo]` — bash 3.2, read-only, exit 0 clean / 1 violations /
2 not a build-memory repo; human summary to stdout, JSON to `/tmp/build-memory-check.json`.
It checks everything derived (layout, ticket grammar + unique sequence, manifest ↔ files,
backward `Depends on`, skeletons without run lines, markers referenced, DEFERRALS ids +
statuses, no OPEN row past a PASSED gate, ADR ↔ index, revisit triggers, ledger key order,
`nextTicket` validity, PHASE-LOG-done ↔ BUILD_INDEX + runs, REQ coverage when the spec and
`req_id_pattern` resolve, size + secrets). `decompose-spec` runs it after seeding,
`implement-spec` before its close commit, `orchestrate-build` at every boundary; a failure
is a real block.

---

## Compatibility (§9)

A repo without `docs/build/README.md` (with the marker) behaves exactly as 0.1.0: scratch
mode, gitignored ledgers, `tickets_dir` default in scratch, `.agents/` excluded from staging
(BM-COMPAT-01). All existing inputs keep their names and defaults, except `tickets_dir`
defaults to `docs/tickets` **in committed mode only** (BM-COMPAT-02). A legacy ledger (PHASE
PLAN present, `manifest:` absent) is driven from its own PHASE PLAN; on `nextTicket: CAPSTONE`
the fresh context runs `decompose-spec mode=extend tail=full` and continues; the one-context
capstone procedure is retained in `skills/orchestrate-build/modes/legacy-capstone.md` for
`legacy_capstone=true` (BM-COMPAT-03). `build-memory migrate` moves a legacy scratch dir into
`docs/build/` (move/rename only; contents byte-identical; dry-run by default) (BM-COMPAT-04).
Historical ticket filenames are not renamed; the manifest chain table carries the sequence
(BM-COMPAT-05).
