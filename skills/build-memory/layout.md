# Build memory — the layout contract

This is the single source of truth for where build memory lives, what each file is, how
it may change, and who writes it. **Every other skill cites this file and does not restate
the tree.** (`decompose-spec`, `orchestrate-build`, `implement-spec`, `synthesize-spec`,
`reconcile-build`, `agent-docs`, `refresh-repo-docs`.)

Build memory is **committed** — the record of a multi-session build is audit-valuable, and
git is already the artifact store. Only regenerable bulk (`logs/`) is gitignored. A repo
opts in with one marker; a repo without it runs in **legacy scratch mode**, byte-for-byte
the pre-0.2.0 behaviour (see §Compatibility). A rule marked *guarded* warns unless the repo
also carries the guards marker (BM-COMPAT-06). Every rule id the build skills cite has its full
text in this file (0.5.0 applied the last of the SK-01…SK-25 proposals); the history mode
(BM-HIST-01) enforces the modes below on every change.

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
│       ├── reports/                  # project reports; ledger-archive/ (BM-LEDGER-08); digests/ (BM-DIGEST-01)
│       ├── tools/                    # validators + generators; repo hooks ci_boundary.*, memory_guard.*; record_policy/
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
| **append-only** | Rows/entries added, never removed or rewritten (`DEFERRALS.md`, `GATE DECISIONS`, `PHASE LOG`, readouts, ADR set, `reports/digests/`); enforced per change by history mode (BM-HIST-01). |
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
- The validator warns on record dates later than the clock in the tree, and history mode
  (BM-HIST-01, R1–R6) fails a change whose *added* record dates break these rules.

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

- `blockedOn` is reserved for **real** blocks (red verification incl. a CI read that is not
  green — BM-CI-01, missing dependency, missing infrastructure the operator refused). A pending
  human gate is never a block; it is a `RETURN PASS` row (BM-LEDGER-03).
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
  A `repair` names its gap after the kind: `repair — close: <what was missing> (<worker harness>,
  why)` for an orchestrator repair of a worker close, `repair — ci: #<n> read pass` for a CI block
  cleared. A second `repair — close:` in one round sets `blockedOn: worker close protocol broken
  (<ids>)` — fix the worker, never back-fill a `done` entry for unverified work. A
  `harness-switch` entry reads `<old> → <new> · reason · operator: "<words>" (<date -u>, <channel>)`
  (BM-HARNESS-01); a `retroactive` entry records work that landed outside the loop (an interactive
  session, an off-stack PR) with its chain row and run ledger, before anything else proceeds.
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
banner `### Round <n> — <date -u +%F> · <purpose>`, and `mode=extend` opens the next one — the
validator warns on legacy rows outside a banner and history mode fails a new one, V13);
`## Milestone gates` (thresholds quoted verbatim); `## Phase gates & ownership notes`;
`## Cross-cutting invariants`; `## Operating rules (binding on every ticket)` (short forms of
BM-CLOCK-01, BM-CI-01, BM-STATUS-01, BM-GATE-05…09, BM-PROD-01, BM-TEST-01, BM-HARNESS-01,
plus the project's own OPERATING MODE rules); `## Out of scope`;
`## Requirement-ID → ticket index`; `## Spec amendments applied` (append-only: `date -u +%F`,
section, before/after or pointer, approver, ADR); `## Decomposition decisions` (incl. the
Phase-4 adversarial review record); `## Plan extensions` (append-only: inserts, splits, rounds).

- The manifest is complete on its own: a human with a terminal can drive the chain from it
  without the ledger (BM-MANIFEST-02).
- Inserting at run time is a scoped `decompose-spec mode=extend` (Phase 3 contract + Phase 4
  fresh-context review of the insert — never a contract drafted ad hoc at a boundary), with a
  filename suffix letter (`16a_…`) and a `## Plan extensions` line; an id never re-binds to
  another slug; splitting produces `<ID>a`, `<ID>b` files and marks the original
  `superseded-by-split` in its gate cell (the original file is kept). A row leaves the
  `nextTicket` order only by a token in its **gate cell** (the row's last cell):
  `superseded-by(<ids>)`, `superseded-by-split`, `deferred(<D-id>)` or `unused`; HUMAN rows are
  skipped too. A skip word anywhere else in the row (title, slug, scope) never takes it out of
  the order (V2). A legacy bare word in the gate cell (`superseded`, `deferred`, `skipped`,
  `withdrawn`, `dropped`) still skips, with a warning naming the token to write. A file in
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
choice. A status flip puts the new status first in the last cell, followed by its `date -u +%F`
and the evidence, and keeps the earlier text (`DONE 2026-10-01 (PR #12, rerun green) — was: OPEN
…`): a row only grows. Row schema:
`| id | item | why deferred | unblocked by | how to verify | proxy now | status |`; `id` =
`D-<TICKET>-<n>`; `status` ∈ OPEN | PARTIAL | DONE | WONTFIX | ACCEPTED-SKELETON (a flip
appends `date -u +%F` + evidence); an optional `kind` column ∈ V | F | D | H (handoff seam) |
P (human prerequisite) | X. The validator warns on an OPEN/PARTIAL `P` row without `owner:` /
`trigger:`; history mode fails such a row *added* under the guards marker.
`implement-spec` Phase 0.3 reads it; closing any row
this ticket or its landed prerequisites unblock is in scope; a live check that cannot run
because a `Live stage` is operator-gated or infrastructure is absent records an OPEN row
(proxy, unblocked-by, how-to-verify) and reports "gate pending" — never a failure, never a
fabricated pass (BM-DEFER-02).

**ADRs (BM-ADR-01..02)** — `docs/adr/ADR-NNN-<slug>.md`: H1 `# ADR-NNN: <title>`; header
bullets `Status` (Proposed | Accepted | Superseded by ADR-MMM), `Date`, `Ticket`,
`Requirement ids`, `Spec`; sections `## Context`, `## Decision`, `## Consequences`,
`## Alternatives considered`, `## Revisit trigger`. Decisions are immutable; a change is a new
ADR, and the superseded one gains only an appended `Status: Superseded by ADR-MMM (<date -u +%F>)`
line; a retro-fitted record says so in its title. `docs/adr/README.md` is generated by
`scripts/adr-index.sh` (numeric order; columns ADR · Title · Ticket · Status) and carries
`<!-- generated by build-memory adr-index; do not edit -->`; the generator reads the header
forms in use (`# ADR-NNN:` or `# ADR-NNN —`; `Ticket`, else `Phase`, else `Phase / ticket`;
bold or plain bullets; an appended `Superseded by` line), and the validator regenerates and
diffs (an index the pre-0.5.0 generator wrote only warns) and warns on every cell that reads
`—` (fails for an ADR added after the guards marker) (BM-ADR-02). `implement-spec` writes an ADR for every MET-DIFFERENTLY verdict, every SHOULD-level
deviation, and every decision its ticket's `## Notes` says it owns; the ADR lands in the same
PR (BM-ADR-03). When the spec carries an ADR appendix/index, the validator checks the two sets
are equal (BM-ADR-04).

**`docs/build/BUILD_INDEX.md` (BM-INDEX-01)** — one row per landed chain row:
`| seq | ticket | kind | branch | PR | base | landed | ADRs | deferrals opened → closed | live verification (live-executed / staging / fixture-only / engineered / n-a / gate-pending) | evidence | harness |`,
where `landed` is `date -u +%F`, `live verification` names the BM-STATUS-01 layer the ticket's
own verification reached (legacy `run` is accepted; anything else warns), `evidence` points at
`runs/<ID>.md#evidence` or `pr/<ID>.md`,
and the trailing `harness` column (BM-HARNESS-01) exists only in new tables — an existing
table is never re-headed (a new round may open `## Round <n>` with the new header). Written by
the worker at close, never reconstructed later. `docs/build/runs/<ID>.md` is the implement-spec run ledger:
`Spec / Base / Branch / Config`, `## Deferrals read`, `## Requirements`, `## Acceptance
criteria`, `## Plan`, `## Test matrix`, `## Progress`, `## Gap table`, `## Evidence log`,
`## Evidence report` (the text submitted as the PR body); its header also carries
`Harness: <harness>/<model-id>/<tier>` (BM-HARNESS-01), `Skills:` (the skills version loaded),
`Started:` and `Closed:` (`date -u +%FT%TZ`) and, at close, the `ci:` field (BM-CI-01)
(BM-INDEX-02). `docs/build/pr/<ID>.md` is the PR body as submitted (`gh pr create
--body-file`). Readouts
`docs/build/readouts/{GATE-G<k>,GATE-ACCEPT,HUMAN-H<k>}.md` follow `templates/READOUT.md` and
are append-only except their single `Status:` line (PENDING → SIGNED | PASSED |
SKIPPED-BY-OPERATOR | NOT-PASSABLE). Each carries the **guard sentence** — "An operator or
authorized human record supplies the decision; an agent must not sign or assume silence is
approval." — the criterion verbatim, per-item evidence (source, `date -u` of the read, layer
reached), any agent-written text inside an `agent-drafted` block with its sha256, and, appended
at signing, a Signature block: the operator's words verbatim with `date -u` and channel, the
GATE DECISIONS row, and the operator's confirmation quoting the agent-drafted hash prefix.
Signing never edits or deletes anything above it; the recorder names its harness/model and does
not sign (BM-INDEX-03). The validator fails a readout created after the guards marker that lacks
the guard sentence; older readouts only warn.

---

## Gate protocol (§7, BM-GATE-01..04)

- Before dispatching a ticket whose `Gate status` block has unticked items,
  `orchestrate-build` pauses in every autonomy mode (in `auto`, an item proceeds without a pause
  only when a live `pre-authorization` row names its id, acting on that row's words; human,
  rights, counsel, publication and acceptance items always pause), presents the block, records
  each answer in `GATE DECISIONS` under BM-GATE-05…09, commits `LEDGER.md` on the chain tip,
  and dispatches with the prompt line "Gate answers are in
  `docs/build/LEDGER.md` GATE DECISIONS — copy them into the ticket's Gate status block in
  your first commit and act on them" (BM-GATE-01).
- An answer of "skip" runs the ticket ungated: everything up to the gate, the gated remainder
  as `DEFERRALS.md` rows, its PR opened, and a `RETURN PASS` row with the re-run line.
  Re-running after ticking is idempotent (BM-GATE-02).
- A `GATE-G<k>` marker row is executed by `orchestrate-build`: read the readout (or draft it,
  labelled per BM-GATE-08), present it, record the operator's disposition verbatim (PASSED /
  SKIPPED-BY-OPERATOR / NOT PASSABLE + what would pass it), commit, continue or stop. Never
  guessed past (BM-GATE-03).
- `drive-build.sh` exits 0 with "gate pending — answer in LEDGER.md GATE DECISIONS and re-run"
  when the only obstacle is a gate under `checkpoint`/`manual`; exit 2 remains for real blocks
  (BM-GATE-04).
- A decomposition **never pre-answers a gate**: it records the gate and its pre-registered
  thresholds, never a `decision` row. An authorization the operator gives at planning time is
  a `pre-authorization` row (explicit item ids, `expires:`, `voided-by:`), never a blanket rule.

**Gate-record rules (BM-GATE-05…09).** They bind every `GATE DECISIONS` row and readout.

- **Verbatim (BM-GATE-05).** `answer` holds the operator's exact words in quotes, stamped with
  the `date -u` of receipt and the channel; `consequence` is the recorder's reading, labelled as
  such; `kind` ∈ decision | pre-authorization | confirmation | waiver | correction. A `decision`
  is dated at or after the gate's pause.
- **Tentative ≠ decision (BM-GATE-06).** Interrogative, conditional or hedged words (`?`, "I
  wonder", "perhaps", "maybe", "should just", "I think … but") are not a decision: restate the
  concrete decision and its consequences, ask yes/no, record only the answer as a
  `confirmation` row, and act only after it.
- **No proxy signatures (BM-GATE-07).** No agent enters a signature, tick or attestation for
  the operator, even when asked ("sign for me", "on my behalf"); it prepares the text and asks
  the operator to confirm it. Operator-reported counsel is recorded `operator-reported`; it
  never closes a counsel obligation or fills a reviewer field.
- **Agent-drafted text is labelled and confirmed (BM-GATE-08).** Readout text an agent writes
  sits in an `agent-drafted` block with its sha256 (`templates/READOUT.md`); the operator's
  confirmation quotes the hash prefix. Signing appends a Signature block and changes only the
  `Status:` line; it never deletes pending text or the guard sentence.
- **Scoped pre-authorization (BM-GATE-09).** A pre-authorization (or any blanket rule) lists
  exact item ids, `expires:` (a ticket or a `date -u +%F` date) and `voided-by:`; it is *live*
  until it expires or is voided. A new item, or a material new fact, needs a new answer.
  Planners never pre-answer.

The validator checks, in a 7-column table (its header has a `kind` column), that each row's `kind` is in
the vocabulary and that a `pre-authorization` row carries `expires:` and `voided-by:`
(guarded). Whether the words are really the operator's cannot be proven by any in-repo check;
the rules make a deviation visible, not impossible.

---

## CI and production at the boundary (BM-CI-01, BM-PROD-01)

**CI truth (BM-CI-01).** A ticket's PR checks are read on its pushed head by the worker before
its closeout (`implement-spec` §6.5 step 0), and again — with every still-open ancestor PR in
the stack — before the next unit is dispatched (`orchestrate-build` §2.1/§2.3; `drive-build.sh`
does it mechanically, `--print-prompt` for the `manual` tier).

- The reader is `orchestrate-build/scripts/ci-boundary.sh`, or a repo hook
  `docs/build/tools/ci_boundary.*` run with `--pr <n> --json <path>` (plus the caller's
  `--ledger`, `--interval`, `--max-wait` / `--no-wait` when given and the hook's file names that
  flag — a hook that names none gets exactly the two) that keeps the shared exit
  codes: 0 pass / none-declared / not applicable · 3 fail, cancelled, or a required check
  missing or skipped · 4 pending after the bounded wait (default 45 min) · 5 unknown (never
  green). The required set is `docs/build/tools/record_policy/ci_required.txt` when present,
  else every check reported on the head.
- It is recorded as the `ci:` field of the PHASE LOG `done` entry and the run ledger:
  `ci: pass #<n>@<sha7> (<check> <run-id>; …)`, `ci: none-declared (locally-green)` when the repo
  declares no CI, or the pending/unknown line as read. A local-only result is `locally-green`,
  never "green".
- Not green → `blockedOn: CI <fail|pending|unknown> on #<n> (<check>): <first failing line>`;
  `nextTicket` stays and nothing stacks on red. It clears only when a read passes, recorded as a
  PHASE LOG `repair` entry naming the fixing PR.
- A red inherited from an ancestor PR blocks too, unless GATE DECISIONS holds the operator's
  verbatim `waiver` row naming that PR and check. A waiver covers the PR it names: the same red
  reappearing on a descendant needs that PR named too.
- Fixing a red is a ticket (an insert or a return pass), never a silent edit inside the next
  ticket, never a relaxed test.
- At each boundary the orchestrator also records the external state — `origin/<default>`'s
  head, whether the chain still descends from it, PRs merged since the last boundary (who,
  when), open PRs that are not chain rows. An off-stack merge into the chain, or a chain PR
  rebased or retargeted by someone else, is a `blockedOn` for the operator.

**No out-of-ticket production changes (BM-PROD-01).** A production mutation — a deploy, a job
execution, a scheduler / database / bucket / IAM / instance change, a publish — runs only inside
a ticket whose `Production mutations:` header names it (what · scripted path · pre-state capture
· rollback · verification); no header means none.

- The worker runs it only through that scripted path, after recording the pre-state and the
  rollback command in the run ledger, and never triggers a paid or expensive operation the
  header does not name.
- The orchestrator never runs one, not even on an in-chat "yes": a "yes" authorizes inserting
  such a ticket.
- Hosted tickets and every round tail re-read the production state they depend on (backups,
  publish surface, scheduler).
- A legacy ticket re-run for a live return pass gets a `> Amended <date -u +%F>:` note naming its
  mutations (BM-TICKET-04).

## Harness, orient, tests, digest (BM-HARNESS-01, BM-ORIENT-01, BM-TEST-01, BM-DIGEST-01)

**Harness identity (BM-HARNESS-01).** Every session that writes build memory records itself as
`<harness>/<model-id>/<tier>` (e.g. `devin-desktop/swe-2-high/manual`,
`claude-code/claude-opus-5-5/headless`): in CURRENT STATE `harness:`, in every run-ledger header
(`Harness:`), in the `harness:` field of the PHASE LOG entries and the `harness` cell of the
BUILD_INDEX rows it writes. Commits carry the harness's co-author trailer naming harness and
model. The value is self-reported — a record, not proof.

- A session whose harness or model differs from CURRENT STATE `harness:` is a **harness switch**.
  It happens only at a ticket boundary, on the operator's words: a PHASE LOG `harness-switch`
  entry (old → new, reason, the operator's words verbatim with `date -u` and channel), then the
  first ticket after it re-runs orient, the validator and the CI read before dispatch. A switch
  the operator did not ask for → pause and ask; `harness:` is never overwritten silently at a close.
- The validator fails a run ledger created after the guards marker that has no `Harness:` line
  (older ones warn) and accepts the `harness` key only between `round` and `updatedAt`.

**Orient within a byte budget (BM-ORIENT-01).** A fresh session never reads `LEDGER.md`,
`DEFERRALS.md` or `BUILD_INDEX.md` whole. It reads: (O1) the ledger head,
`sed -n '1,/^## OPEN FINDINGS/p' docs/build/LEDGER.md` (≤ 12 KiB); (O2, inside it) CURRENT
STATE (≤ 3 KiB); (O3) the current RETURN PASS table (a `### RETURN PASS — current` sub-table
when the repo keeps one); (O4) any repo projection the OPERATING MODE names; (O5) the last
three PHASE LOG entries; (O6) the next row's manifest line and contract header — ≤ 48 KiB in
all. The ledger's OPERATING MODE may give its own recipe; follow it. Workers still load their
contract and the DEFERRALS rows it scopes. A head over budget, a path in it that does not
exist (relative to the repo or to `docs/build/`), or a stale token (`.agents/scratch`,
`gitignored`, `Do not resume until`, plus one per line in
`docs/build/tools/record_policy/stale_tokens.txt`, where `!token` retires a default) is a
finding to surface before dispatch (validator: guarded; the recipe's total over 48 KiB warns).
A superseding note names what it retires without quoting a stale token.

**Tests assert invariants, not living records (BM-TEST-01).**
- A test may assert what holds at every commit: schema, vocabulary membership, uniqueness,
  generated == source, references resolve, append-only.
- It never asserts the *current value* of a living record: `nextTicket`, a project, readout or
  obligation status, or the counts, row ranges and dates of living registers (LEDGER,
  BUILD_INDEX, DEFERRALS, the coverage matrix, README/CHANGELOG wording). A validator derives
  expected counts from their source; it does not pin them.
- When such a pin fails, convert it to an invariant or delete it, in its own commit — never relax
  it in place. Assertions over frozen artifacts (a dated report, a closed round's plan) are fine
  when the test says why. The validator's `living-pin?` heuristic warns on a tracked test file
  that names a living record file and one of its living keys.

**Layered progress and the operator digest (BM-DIGEST-01).**
- After each boundary the orchestrator emits one line naming the layer reached, never just
  "complete": `T# · PR #n · CI: pass|RED|pending|locally-green · layer: <BM-STATUS-01 word> ·
  prod touched: none|<what> · deferrals +k/−j · <date -u> · next: T#+1`.
- At every pause, at session end, at every usage-limit event, and at the cadence the ledger's
  OPERATING MODE names (e.g. once per wave), it appends an **operator digest** to
  `docs/build/reports/digests/<date -u +%F>.md` (append-only; one `## <date -u +%FT%TZ> —
  operator digest (<trigger>)` section each) and shows it. `orchestrate-build/scripts/digest.sh`
  reads the mechanical part: the harness in use, the ledger state, the validator result, every
  open chain PR's CI, merges by anyone since the previous digest (read from GitHub), the default
  branch and whether the chain descends from it, owed human and rights work (owner, trigger). The
  session adds the production anomalies it read, the infrastructure spend and the agent usage —
  runs, usage per run (median, maximum), cumulative, the projection, usage-limit events — as the
  harness exposes them ("not measured" is valid; a figure is never invented).
- No secret values. If one appeared in a transcript the digest records `exposed: yes` and the
  session stops for rotation; `digest.sh` refuses to write a digest that holds a token-shaped
  string (the validator's secret scan covers `reports/`).
- **Stop and ask** (set `blockedOn` or pause; never proceed) when: a required check is red;
  production contradicts a record; a date is not from the clock; operator words are tentative
  or delegate a signature; a pre-authorized step meets a new fact; a ticket would touch
  production outside its contract or rewrite a protected record; human work would be deferred a
  second time; the harness or model would change; a usage limit is hit. Silence is never consent.

---

## History mode (BM-HIST-01)

Tree mode can only warn about legacy content it cannot change. History mode judges **only the
lines a change adds or removes**, so legacy records never fail for what they already contain:
`check-build-memory.sh --range BASE..HEAD | --staged | --first-parent SHA` (it runs
`scripts/check-history.sh`; bash 3.2 + git).

| region | mode |
|---|---|
| LEDGER `## GATE DECISIONS`, every `## PHASE LOG…`, `## OPEN FINDINGS…`, `## RETURN PASS…` | append-only + append position: an addition is one block after the region's last non-blank line |
| other LEDGER regions below the head | append-only |
| LEDGER head (title, provenance, OPERATING MODE, CURRENT STATE) | living-archived: a CURRENT STATE value may change; other removed text is archived byte-for-byte under `reports/ledger-archive/` in the same change, with a pointer comment naming the file |
| `DEFERRALS.md` rows | row-annotate: every old cell's text survives; a new leading status carries a date the row did not have |
| `readouts/*` | append-only except the single `Status:` line (no in-place ticks, no deleted guard text) |
| `runs/<ID>.md` once its header carries a dated `Closed:` stamp (before its first `##` heading; `- **Closed:** none.` in a body section is not a close) | append-only (one honest closeout; a later fact is an appended dated note) |
| `BUILD_INDEX.md` | append-only; an added row has the header's column count, a seq not used before and a real PR |
| manifest `## Spec amendments applied`, `## Plan extensions`; chain table | append-only; a new chain row sits under a numbered `### Round <n>` banner (V13) and never re-binds an id to another slug |
| executed contracts (the ticket has a BUILD_INDEX row at the base) | frozen; only an appended `> Amended <date -u +%F>:` note |
| landed ADRs | frozen; only an appended `Superseded by ADR-NNN (<date -u +%F>)` line, ADR-NNN existing |
| `docs/build/**/*.jsonl` | byte prefix |
| `reports/digests/*.md` | append-only |

**Record dates** on added lines (PHASE LOG lead dates, GATE DECISIONS dates, `updatedAt`,
BUILD_INDEX `landed`, DEFERRALS status dates, run-ledger and readout stamps, plan-extension
dates, an added ADR's `Date:`, `recorded_at` in `*.jsonl`, digest headings, planning change-log
stamps): **R1** not later than the commit that adds them (+ 5 min; a date-only value ≤ the
commit's UTC or committer-local date) nor the clock; **R2** an act is not back-dated more than
48 h unless the line says `≤`, `retro: <evidence>` or `as-of <sha|#PR>`; **R3** a correction line
may quote a wrong date when it also carries the true one; **R5** `future-ok: <class>: <reason>`
or an unexpired allow entry exempts R1; **R6** no commit is later than the clock (+ 5 min). Each
added line takes the committer time of the commit in the range that added it.

- **Repo policy** — `docs/build/tools/record_policy/history.policy`, one rule per line:
  `append-only <glob>` (e.g. `db/sqitch.plan`), `date <glob> <ERE>` (an extra record position),
  `allow <glob> <expires ISO> <text>` (a future date allowed until it expires),
  `exempt <path> <heading>` (a generated `##`/`###` region, e.g. `exempt docs/build/LEDGER.md
  ### RETURN PASS — current`), `archive <dir>` (another living-archived destination). A comment
  is a line whose first non-blank character is `#`, or a lone `#` after whitespace (followed by
  whitespace or the line end) and the rest of the line; a `#` inside a token is kept (`###`,
  `#123`, `^#+`).
- **Repo hook** — if `docs/build/tools/memory_guard.{py,sh}` (or an executable `memory_guard`)
  exists, history mode runs it as `<hook> all --range … | --staged | --first-parent …
  [--json PATH] [--now ISO]` and passes its exit code through; the repo's own guard is
  authoritative for the repo.
- **Where it runs** — `implement-spec` §6.5 (`--staged` before the closeout commit);
  `orchestrate-build` at every boundary (`--range <chainTip before>..<chainTip after>`); CI
  (`base..head` on pull requests, `--first-parent` on pushes to the default branch); optionally
  a pre-commit hook.
- **Exits** — 0 clean · 1 violations · 2 not applicable (scratch mode) · 5 unknown (a shallow
  clone — "set fetch-depth: 0" —, an unresolvable range, bad arguments or a report that cannot
  be written; never green).

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
| `reports/digests/<date -u +%F>.md` (append-only) | `orchestrate-build` via `scripts/digest.sh` | every pause, session end, usage-limit event, OPERATING MODE cadence |

---

## The validator (§10, BM-VALID-01..02)

`scripts/check-build-memory.sh [repo] [--json PATH]` — bash 3.2, read-only. **Tree mode**
(default) checks everything derived: layout, ticket grammar + unique ids, manifest ↔ files,
backward `Depends on`, skeletons without run lines, markers referenced, DEFERRALS ids +
statuses, no OPEN row past a PASSED gate, ADR ↔ index (BM-ADR-02), revisit triggers, ledger key
order (optional `harness` in its slot), `nextTicket` validity, PHASE-LOG-done ↔ BUILD_INDEX +
runs (the parser strips markup and reports `candidates`/`evaluated`), REQ coverage when the spec
and `req_id_pattern` resolve, size + secrets.

- **Guarded** (BM-COMPAT-06): the CURRENT STATE vocabularies (`projectStatus`, `pauseRequested`,
  `mergePolicy`, `autonomy`, integer `round`, ISO `updatedAt`); the BM-LEDGER-08 budget and shape
  (head ≤ 12 KiB, CURRENT STATE ≤ 3 KiB and ≤ 256 B a line, no `| PRIOR`, the last region a
  PHASE LOG, its entries ≤ 2 KiB); stale orient paths and tokens (BM-ORIENT-01); the `kind` of
  7-column GATE DECISIONS rows and scoped pre-authorizations (BM-GATE-05, -09); a done entry that
  parses only after stripping markup, in the current region. Files created after the marker
  must also carry: the readout guard sentence (BM-INDEX-03), a run ledger's `Harness:` line
  (BM-HARNESS-01), parseable ADR index cells (BM-ADR-02).
- **Warnings only:** BUILD_INDEX row shape, unique seq, `PR pending` once Closed:, the
  live-verification vocabulary (BM-INDEX-01); record dates later than the clock (BM-CLOCK-01);
  `nextTicket` not the lowest chain row still to land (gate-cell tokens and HUMAN rows skipped;
  a legacy bare gate-cell word warns); two `repair — close:` entries in a round
  with `blockedOn` empty; the orient recipe over 48 KiB; chain rows outside a numbered round
  banner; `living-pin?` test files (BM-TEST-01); an owed `P` deferral without `owner:`/`trigger:`;
  `projectStatus: DONE` without a signed `GATE-ACCEPT` readout; a seed ledger whose GATE
  DECISIONS holds a non-`pre-authorization` row ("pre-answered gate?").
- **History mode** — `--range` / `--staged` / `--first-parent` (BM-HIST-01).
- **Planning mode** — `--planning <ledger>` checks a research or planning ledger (V14,
  BM-SYNTH-02): `updatedAt` not older than the newest change-log stamp, `lastCompleted` the
  newest done row the change log names, `nextUnit` not a done row. It needs no marker.
- **Report** — human summary to stdout; JSON `build-memory-check/2` to `--json PATH` or a unique
  `mktemp` file (the last stdout line names it): `input {repo, commit, dirty, input_digest}`,
  `summary {violations, warnings, exit}`, `counts {<check>: {candidates, evaluated}}`,
  diagnostics `{check, severity, file, obligation, evidence, message}` — every field under its
  own key, empty or not. A report that cannot be written exits 2.
- **Exit codes** (the shared build-script contract): 0 clean · 1 violations · 2 not a
  build-memory repo · 3 vacuous (done entries exist but fewer than half parse — never green).

`decompose-spec` runs it after seeding, `implement-spec` before its close commit (tree, then
`--staged`), `orchestrate-build` at every boundary (tree, then `--range`); any non-zero exit is a
real block. The CI read at a boundary is a separate script with the same exit codes (BM-CI-01).

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
entries, old 6-column tables, off-enum values) never fails; with it they fail. Content the guards
cannot change — PHASE LOG entries in regions before the last, files created before the marker
— stays warning-level either way. History mode judges only what a change adds or removes, so it
needs no marker (its one guarded rule: an owed `P` row added without `owner:`/`trigger:`).
