# Build memory — the layout contract

This is the single source of truth for where build memory lives, what each file is, how
it may change, and who writes it. **Every other skill cites this file and does not restate
the tree.** (`decompose-spec`, `orchestrate-build`, `implement-spec`, `synthesize-spec`,
`reconcile-build`, `agent-docs`, `refresh-repo-docs`.)

Build memory is **committed** — the record of a multi-session build is audit-valuable, and
git is already the artifact store. Only regenerable bulk (`logs/`) is gitignored. A repo
opts in with one marker; a repo without it runs in **legacy scratch mode**, byte-for-byte
the pre-0.2.0 behaviour (see §Compatibility). A rule marked *guarded* warns unless the repo
also carries the guards marker (BM-COMPAT-06). *(forward: SK-nn)* names a change proposal not
yet applied in this skill version; until it lands, that part binds by prose (and any repo guard).

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
│       ├── README.md                 # contains `<!-- build-memory: v2 -->` (+ optional guards marker)
│       ├── LEDGER.md                 # the machine-state file (§ LEDGER)
│       ├── BUILD_INDEX.md            # one row per landed ticket (§ Build index)
│       ├── runs/<ID>.md              # implement-spec run ledgers
│       ├── pr/<ID>.md                # PR bodies as submitted
│       ├── readouts/                 # GATE-G<k>.md · GATE-ACCEPT.md · HUMAN-H<k>.md (append-only; templates/READOUT.md)
│       ├── planning/                 # re-planning rounds: <date -u +%F>_planning-ledger.md, <date -u +%F>_decision-memo.md
│       ├── reports/                  # project-specific reports a ticket produces; ledger-archive/ (BM-LEDGER-08)
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
| **living** | Edited in place until frozen (`research-ledger.md` until ratified). |
| **living-archived** | A value may be updated in place; any other removed or rewritten text is archived byte-for-byte under `docs/build/reports/ledger-archive/` in the same commit, with a sha256 pointer comment left behind (`LEDGER.md` head, BM-LEDGER-08). |

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

### Clock rule (BM-CLOCK-01)

Every date or time recorded in build memory is `date -u` at the moment of writing (ISO-8601
`Z`; date-only fields use the UTC date), or the git/GitHub time of the event it records, with
the source named. Never a remembered, inferred or "chain" date.

- A recorded event date is never later than the commit that records it.
- An act (a gate answer, a landing, a status flip) is not back-dated more than 48 h without
  `retro: <evidence>`.
- A future value needs `future-ok: <scheduled|real-world|synthetic|illustrative>: <reason>`,
  or a repo allow-list entry that expires.
- Tools that record a date default to the clock and refuse values later than clock + 5 min.
- Templates write `<date -u +%FT%TZ, at writing>` (timestamps) or `<date -u +%F>` (date-only
  fields); no template carries a bare date placeholder.
- The validator will warn on the tree and fail on violating *added* lines *(forward: SK-15
  item 7, SK-16)*.

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

Sections, in order (BM-LEDGER-01): the title (+ an archive pointer comment, if any), an
`OPERATING MODE` blockquote (the verbatim resume prompt for a fresh session, with one-line
orient / clock / CI rules), `## CURRENT STATE`, `## OPEN FINDINGS`, `## GATE DECISIONS`,
`## RETURN PASS`, and the PHASE LOG **last** — `## PHASE LOG — Round <n>` headings (a legacy
plain `## PHASE LOG` is accepted). **No plan sections** — the manifest is the plan
(`manifest:` key points at it).

`CURRENT STATE` (BM-LEDGER-02) is a fenced `key: value` block with exactly these keys
(`harness` optional, and only in its slot), in this order (trailing `# comments` allowed; the
reader strips them):

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
harness          # OPTIONAL: <harness>/<model-id>/<tier> (BM-HARNESS-01)
updatedAt        # date -u +%FT%TZ at writing (BM-CLOCK-01)
```

- `blockedOn` is reserved for **real** blocks (red verification, missing dependency, missing
  infrastructure the operator refused). A pending human gate is never a block; it is a
  `RETURN PASS` row (BM-LEDGER-03).
- `GATE DECISIONS` is an append-only table, rows appended at the end of the section, newest
  last: `| date | ticket | gate | item | answer (verbatim) | consequence | kind |` — `date` is
  the `date -u` of receipt; `answer` the operator's exact words in quotes (+ channel);
  `consequence` the recorder's labelled reading; `kind` ∈ decision | pre-authorization |
  confirmation | waiver | correction (a `pre-authorization` lists exact item ids, `expires:`
  and `voided-by:`; the gate-record rules are BM-GATE-05…09). A legacy 6-column table is kept
  as is; a new round may open `### Round <n>` in the 7-column form. Secrets never;
  `provided: yes/no` only (BM-LEDGER-04).
- `RETURN PASS` is a table `| ticket | gates | what the operator must do | re-run line |`;
  `returnPass:` lists the same ticket ids (BM-LEDGER-05).
- `PHASE LOG` entries are append-only, newest last, one per event, and go **only at the end
  of the file**, under the last `## PHASE LOG — Round <n>` heading (a new round opens a new
  heading). Fixed shape, no markup before the kind, each entry ≤ 2 KiB (BM-LEDGER-06):
  `- <date -u +%F> — <ID> <kind> — branch · PR · base · one-line summary · **Verify:** … · **Deferrals:** opened/closed ids · **Deviations:** … · chainTip → … · next → …`
  plus optional `· ci: … · layer: … · harness: …` fields; `kind` ∈ done | blocked | inserted
  | split | gate | pause | round | correction | restored | repair | harness-switch | retroactive.
- `drive-build.sh` parses `projectStatus`, `nextTicket`, `pauseRequested`, `blockedOn`,
  `buildWorktree`, `returnPass`, `manifest` with the never-fail reader; unknown keys are
  ignored; a legacy ledger without the new keys still drives (BM-LEDGER-07).
- **Budget (BM-LEDGER-08, guarded).** The orient region (line 1 → before `## OPEN FINDINGS`)
  is ≤ 12 KiB (warn above 8 KiB). CURRENT STATE holds **values only**: one line per key,
  ≤ 256 B each, no `| PRIOR` history — the PHASE LOG's `chainTip → … · next → …` fields and
  git carry the history of values. `returnPass` is a comma-separated id list (or `(none)`).
  No other line in the file begins with a CURRENT STATE key name. The last `## ` heading is a
  PHASE LOG heading, and its entries obey the 2 KiB cap (older regions only warn). The title,
  provenance, OPERATING MODE and CURRENT STATE are **living-archived** (§ Modes); every other
  region only appends. There is no round-archive key (the archive is the path convention +
  pointer comment); rotating the whole file waits until it exceeds 1 MiB.

---

## Manifest, ticket, markers, skeletons (§5)

**Manifest (`docs/tickets/00_MANIFEST.md`, BM-MANIFEST-01)** — sections in order: title +
three banners (committed contract record; cite-don't-copy with the spec amendment protocol;
deferrals companion); `## How to build` (the stacked-chain recipe and the four rules: table
order; stay on the previous branch; stop at GATE rows; never let a code ticket block on a
HUMAN row; the run-line pattern; how `orchestrate-build` drives it); `## Human prerequisites`
(H-rows, scheduled: owner + date or trigger); `## The chain` (table
`| # | file | phase | kind | scope | gate |`, `kind` ∈ ticket | human | gate | skeleton |
capstone | reconcile | docs, marker rows interleaved; every row sits under a numbered round
banner `### Round <n> — <date -u +%F> · <purpose>`, and `mode=extend` opens the next one);
`## Milestone gates` (thresholds quoted verbatim); `## Phase gates & ownership notes`;
`## Cross-cutting invariants`; `## Operating rules (binding on every ticket)` (short forms of
BM-CLOCK-01, BM-CI-01, BM-STATUS-01, BM-GATE-05…09, BM-PROD-01, BM-TEST-01, BM-HARNESS-01,
plus the project's own OPERATING MODE rules); `## Out of scope`;
`## Requirement-ID → ticket index`; `## Spec amendments applied` (append-only: `date -u +%F`,
section, before/after or pointer, approver, ADR); `## Decomposition decisions` (incl. the
Phase-4 adversarial review record); `## Plan extensions` (append-only: inserts, splits, rounds).

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
`Live stage:` (none | offline-only | operator-gated: <budget>) · `Production mutations:`
(none | list: what · scripted path · pre-state capture · rollback — BM-PROD-01; absent means
none) · `Size budget:` (N changed lines excl. generated/fixtures; over budget → split via
`decompose-spec` first). Body sections: `## Goal` ·
`## Load (read these — do not re-read others)` · `## In scope — deliverables` (numbered;
each names the requirement ids it satisfies) · `## Out of scope` (names the owning ticket) ·
`## Acceptance criteria` (each tagged *(deterministic · layer: <word>)* or *(agentic · layer:
<word>)* with the BM-STATUS-01 layer it must reach — an untagged layer reads `engineered`; the
last is the universal phase-gate AC) · `## Requirement IDs to satisfy and stamp in the PR` ·
`## Cross-cutting invariants` (cited from the manifest) · `## Operating clauses` (cited from
the manifest's `## Operating rules`; the gap table has one row per clause) · `## Notes`.

- The universal phase-gate AC reads (BM-TICKET-02): "verification green; every new behaviour
  has a test that fails if it is removed; requirement ids stamped in the PR; anything not
  automatically verifiable is a `DEFERRALS.md` row with its compensating control; ADRs
  written for every deviation and owned decision; `BUILD_INDEX.md` row and `LEDGER.md`
  advanced; operating clauses met — dates from the clock, PR checks read and recorded, AC
  layers stated, no living-record pins, protected records only appended, gate words
  verbatim, harness in the run-ledger header."
- A skeleton ticket carries `Kind: skeleton`, a `> Skeleton only` banner naming the gate
  after which the body is written, and only the header, `## Scope (one line)`, `## Spec §§`
  and `## REQ coverage`. The validator refuses a run line for a skeleton; `implement-spec`
  MUST stop if asked to run one (BM-TICKET-03).
- Executed contracts are never rewritten; a later amendment appends a dated note
  (`> Amended <date -u +%F>: …`) pointing at the manifest amendment line (BM-TICKET-04).

**Markers (BM-TICKET-05)** — `HUMAN-H<k>`: the operator work as a checklist, exit criterion,
which tickets it blocks, `Owner`, `Scheduled` (a `date -u` target or a trigger ticket), the
claims `Withheld until done`, `Deferrals so far`, and the DEFERRALS rule for tickets that run
before it completes. It is scheduled like a ticket and never skipped by default: code tickets
proceed past it only by opening D-rows that cite it and name the claims they withhold, and a
second deferral stops the chain for the operator's explicit words (keep with a new date, amend
the spec, or waive by ADR). Its checkboxes are living state, ticked (with `date -u +%F`) by the
operator or by `orchestrate-build` when the ledger records the operator's words (a
demonstrably-done-but-unticked marker is a validator warning). `GATE-G<k>`: the criterion
verbatim from the spec, the readout path `docs/build/readouts/GATE-G<k>.md`, the rule "never
guessed past", the pre-registered thresholds, and the DEFERRALS rule (no OPEN row scoped to
the phase). Every marker body carries the guard sentence (BM-INDEX-03).

**Tail rows (BM-TAIL-01..04)** — when the chain has more than one implement-spec ticket,
`decompose-spec` appends, from `templates/tail/`: `CAP.1` gap analysis (independent fresh
context; BM-VERDICT-01 verdicts before reading any run ledger; `COVERAGE_MATRIX.csv` with
columns
`id, level, spec_section, class, verdict, evidence, owning_tickets, tests, adrs, routing, note`
plus, appended (never renamed), `required_domain, achieved_domain, owed_legs, accepted_scope`;
seam hunt; `CAPSTONE_GAP_ANALYSIS.md`), `CAP.2` composed verification (whole build as one
unit; unwired seams are `xfail`/skips whose reason starts with a DEFERRALS id;
`COMPOSED_E2E_REPORT.md`), `CAP.3` closure (`CAPSTONE_CLOSURE.md` headlined with the two sums
and the three-part list for signature), `GATE-ACCEPT` marker (operator signs), `REC.1`
backlog + readiness, `REC.2` spec reconciliation, `REC.3` integration plan, `DOC.1` repo-docs
refresh (invokes `refresh-repo-docs`), `DOC.2` agent-docs refresh (invokes `agent-docs`).
`tail=minimal` (default: `CAP.1`, `CAP.3`, `GATE-ACCEPT`, `DOC` — one docs row invoking
`refresh-repo-docs` then `agent-docs`) | `full` (all of the above; the manifest's
`## Decomposition decisions` names which REC rows read live state and why); `tail=none` is
refused when N > 1. Tail templates carry placeholders (`{{build_name}}`, `{{spec_path}}`,
`{{req_id_pattern}}`, `{{ticket_count}}`, `{{last_ticket}}`) that `decompose-spec` fills; the
instantiated files are ordinary chain rows with `kind` capstone | reconcile | docs.
`projectStatus: DONE` requires every chain row landed or consciously skipped (recorded),
`BUILD_INDEX.md` complete, no `OPEN` deferral without a `landing`, and the `GATE-ACCEPT`
readout signed — in every tail, minimal included (BM-TAIL-03). Every tail row carries a
*(live-read)* AC: the artifact it writes cites the live state it describes (the CI read of
every open PR in the stack; where the build has a production surface, a probe-run record —
id, `date -u`, result, sha256 — no older than 24 h at the commit); a statement about
production state with no such citation is removed, not written (BM-TAIL-04).

### Status layers and verdicts (BM-STATUS-01, BM-VERDICT-01)

**Layers (BM-STATUS-01).** `engineered` · `fixture-verified` · `staging-verified` ·
`live-executed` · `public`, plus `human-completed` (orthogonal: a human leg done by a human;
no agent-produced label counts). The order of the two lowest rungs follows the repo's own
ladder where it has one. No status statement collapses them: name the layer reached. MET
holds only at the requirement's own layer.

**Verdicts (BM-VERDICT-01).** Parameters are `;`-separated so a CSV cell stays one cell.

| verdict | means · entry | exit |
|---|---|---|
| `MET` | every clause holds at its required layer; evidence per clause; `achieved_domain ≥ required_domain`; no OPEN/PARTIAL D-row is a leg of it | demote on a contradicting live read, a regressed test, a new owed leg or vanished evidence |
| `MET-DIFFERENTLY(ADR-nnn\|RISK-id)` | intent met by another mechanism; an accepted ADR (or risk row with a compensating control) names the id and the evidenced alternative | re-verdict if the ADR is superseded |
| `MET-ENGINEERED(D-id;…)` | all engineering built and verified; only live/operator/human acts remain, each in an OPEN/PARTIAL D-row that names the id (`owed_legs`); no surface claims the leg happened | up to MET when every D-row is DONE at the required layer; down to PARTIAL if a surface claims it |
| `PARTIAL` · `MISSING` · `AT-RISK-INTEGRATION` | some clauses unbuilt · nothing conforming · built but the operated path does not use it; exactly one live home (ticket, BL row or OPEN D-row) | up as clauses land / the path switches |
| `WAIVED(ADR-nnn)` | the operator decided it will not be met for a stated scope; an accepted ADR quotes the operator verbatim, names the risk and has a revisit trigger (a WONTFIX row or skipped gate alone is not a waiver) | re-verdict when the trigger fires |
| `N/A-RATIONALE` | a rationale statement with no build obligation | — |

A scoped operator acceptance authorizes action; it never raises a verdict (`accepted_scope`
set ⇒ verdict ≤ MET-ENGINEERED). Headlines use two sums: *engineering closed* = MET +
MET-DIFFERENTLY + MET-ENGINEERED; *requirement satisfied* = MET + MET-DIFFERENTLY.
MET-ENGINEERED is never counted as MET.

---

## Deferrals, ADRs, build index, readouts (§6)

**`docs/tickets/DEFERRALS.md` (BM-DEFER-01)** — the header states the rules verbatim:
read first every run; never delete a row; a deferral not in the file did not happen; gates
refuse to pass with an `OPEN` row scoped to the phase; and (rule 5, in files initialised
from 0.3.0 — an existing file adopts it by appending it) **human work is scheduled, not
deferred by default**: a `P` row, or any row whose `unblocked by` names a person, carries
`owner: <who>` and `trigger: <date -u +%F | ticket id>` in `unblocked by` and
`withholds: <claim>` in `why deferred`; the same obligation deferred a second time (an
appended `DEFERRED-AGAIN <date -u +%F>` note) stops the chain for the operator's explicit
choice. Row schema:
`| id | item | why deferred | unblocked by | how to verify | proxy now | status |`; `id` =
`D-<TICKET>-<n>`; `status` ∈ OPEN | PARTIAL | DONE | WONTFIX | ACCEPTED-SKELETON (a flip
appends `date -u +%F` + evidence); an optional `kind` column ∈ V | F | D | H (handoff seam) |
P (human prerequisite) | X. The validator warns on an OPEN/PARTIAL `P` row without `owner:` /
`trigger:` (failing such rows *added* under the guards marker is *forward: SK-16*).
`implement-spec` Phase 0.3 reads it; closing any row
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
`| seq | ticket | kind | branch | PR | base | landed | ADRs | deferrals opened → closed | live verification (run / fixture-only / n-a / gate-pending) | evidence | harness |`,
where `landed` is `date -u +%F`, `evidence` points at `runs/<ID>.md#evidence` or `pr/<ID>.md`,
and the trailing `harness` column (BM-HARNESS-01) exists only in new tables — an existing
table is never re-headed (a new round may open `## Round <n>` with the new header). Written by
the worker at close, never reconstructed later. `docs/build/runs/<ID>.md` is the implement-spec run ledger:
`Spec / Base / Branch / Config`, `## Deferrals read`, `## Requirements`, `## Acceptance
criteria`, `## Plan`, `## Test matrix`, `## Progress`, `## Gap table`, `## Evidence log`,
`## Evidence report` (the text submitted as the PR body) (BM-INDEX-02). `docs/build/pr/<ID>.md`
is the PR body as submitted (`gh pr create --body-file`). Readouts
`docs/build/readouts/{GATE-G<k>,GATE-ACCEPT,HUMAN-H<k>}.md` follow `templates/READOUT.md` and
are append-only except their single `Status:` line (PENDING → SIGNED | PASSED |
SKIPPED-BY-OPERATOR | NOT-PASSABLE). Each carries the **guard sentence** — "An operator or
authorized human record supplies the decision; an agent must not sign or assume silence is
approval." — the criterion verbatim, per-item evidence (source, `date -u` of the read, layer
reached), any agent-written text inside an `agent-drafted` block with its sha256, and, appended
at signing, a Signature block: the operator's words verbatim with `date -u` and channel, the
GATE DECISIONS row, and the operator's confirmation quoting the agent-drafted hash prefix.
Signing never edits or deletes anything above it; the recorder names its harness/model and does
not sign (BM-INDEX-03). Readouts that predate the guards marker are grandfathered; checking the
guard sentence in newer ones is *forward: SK-15 item 8*.

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
- A decomposition **never pre-answers a gate**: it records the gate and its pre-registered
  thresholds, never a `decision` row. An authorization the operator gives at planning time is
  a `pre-authorization` row (explicit item ids, `expires:`, `voided-by:`), never a blanket rule.

### Rule ids cited before their full text lands

The manifest template's `## Operating rules` carries a short form of each; it binds until the
full rule lands here.

| id | short form | full text |
|---|---|---|
| BM-CI-01 | PR checks read at every boundary and recorded; red / pending / unreadable → `blockedOn`; nothing stacks on red | *forward: SK-01* |
| BM-GATE-05…09 | operator words verbatim (+ `date -u`, channel); tentative words get a yes/no confirmation; no proxy signatures; agent-drafted text labelled + hash-confirmed; scoped pre-authorizations | *forward: SK-03* |
| BM-HARNESS-01 | harness/model id in CURRENT STATE `harness`, run-ledger headers, PHASE LOG and BUILD_INDEX; switch only at a boundary, recorded | *forward: SK-04* |
| BM-PROD-01 | no production mutation outside a ticket whose `Production mutations:` header names it | *forward: SK-06* |
| BM-ORIENT-01 | orient from the ledger head, RETURN PASS, the last three PHASE LOG entries and the next row — never whole files | *forward: SK-07* |
| BM-TEST-01 | tests assert invariants, never the current value of a living record | *forward: SK-12* |

---

## Who writes what (§8)

| Artifact | Writer | When |
|---|---|---|
| `docs/build/README.md`, `LEDGER.md` (seed), `BUILD_INDEX.md` (header), `logs/.gitignore`, `docs/README.md` rows, `docs/adr/{README,_TEMPLATE}.md`, `docs/tickets/{00_MANIFEST,_TEMPLATE,DEFERRALS}.md`, tickets, markers, tail rows, `docs/decomposition-prompt.md` | `decompose-spec` via `build-memory init` | seed / extend |
| `runs/<ID>.md`, `pr/<ID>.md`, ADRs, `DEFERRALS.md` rows, `BUILD_INDEX.md` row, `LEDGER.md` close (CURRENT STATE + PHASE LOG), `reports/*`, project registers the spec mandates | `implement-spec` | per ticket, two commits: code+docs, then `docs(build): close <ID>` |
| `LEDGER.md` GATE DECISIONS / RETURN PASS / OPEN FINDINGS / pause / insert / split; `readouts/*.md` (never the Signature: the operator's words only) | `orchestrate-build` | at boundaries, committed on the chain tip |
| `reports/ledger-archive/*` + pointer comment | whoever replaces living `LEDGER.md` text | same commit |
| `COVERAGE_MATRIX.csv`, `CAPSTONE_*.md`, `COMPOSED_E2E_REPORT.md` | `CAP.*` tickets (workers) | tail |
| `BACKLOG.*`, `TICKET_VS_SPEC.md`, `SPEC_RECONCILIATION_PLAN.md`, `INTEGRATION_PLAN.md`, `OPERATIONAL_READINESS.md` | `REC.*` tickets via `reconcile-build` | tail |
| `docs/research-ledger.md`, `research/*`, `design/*`, the spec, `decomposition-prompt.md` | `synthesize-spec` | upstream |
| `planning/<date -u +%F>_*.md` | `reconcile-build` (seed) and `decompose-spec mode=extend` | next round |

---

## The validator (§10, BM-VALID-01..02)

`scripts/check-build-memory.sh [repo]` — bash 3.2, read-only, exit 0 clean / 1 violations /
2 not a build-memory repo; human summary to stdout, JSON to `/tmp/build-memory-check.json`.
It checks everything derived (layout, ticket grammar + unique sequence, manifest ↔ files,
backward `Depends on`, skeletons without run lines, markers referenced, DEFERRALS ids +
statuses, no OPEN row past a PASSED gate, ADR ↔ index, revisit triggers, ledger key order
(optional `harness` in its slot), `nextTicket` validity, PHASE-LOG-done ↔ BUILD_INDEX + runs,
REQ coverage when the spec and `req_id_pattern` resolve, size + secrets). Guarded checks
(BM-COMPAT-06): the BM-LEDGER-08 budget and shape. Warnings only: an owed `P` deferral without
`owner:`/`trigger:`; `projectStatus: DONE` without a signed `GATE-ACCEPT` readout; a seed
ledger whose GATE DECISIONS holds a non-`pre-authorization` row ("pre-answered gate?"). The
rest of the truth checks and history mode are *forward: SK-15, SK-16*. `decompose-spec` runs it after seeding,
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

**Guards marker (BM-COMPAT-06).** A committed repo opts into strict tree checks with a second
marker line in `docs/build/README.md`: `<!-- build-memory-guards: 1 -->` (alone on its line).
Without it every *guarded* rule is a warning, so legacy content (PRIOR chains, oversized
entries, old 6-column tables) never fails; with it they fail. Content the guards cannot
change — PHASE LOG entries in regions before the last — stays warning-level either way.
