---
name: decompose-spec
license: MIT
description: "Turn one large spec into an optimally-partitioned, dependency-ordered ticket plan — the fewest self-contained tickets that each fit one fresh-context implementation run — and seed a durable build ledger plus per-ticket contract files and a manifest runbook (relocatable into the repo tree via tickets_dir). The planning half of a multi-session build; pairs with orchestrate-build."
inputs:
  - name: spec
    required: true
    description: "The authoritative spec to decompose — a file path (preferred) or inline instructions. Large/multi-concern is the expected case."
  - name: build_name
    required: false
    description: "Short kebab slug for this build (e.g. 'billing-rework'). Drives the ledger filename and, later, the branch prefix. Derived from the spec title if omitted."
  - name: dispatch_target
    required: false
    description: "How each ticket will later be executed, which sets the ticket-size CEILING: 'subagent' = a single, non-compacting context window (HARD ceiling — size conservatively); 'headless' = a fresh top-level session that can auto-compact (soft ceiling); 'manual' = a human-driven fresh session (soft). Default 'subagent' — the conservative sizing that is safe on every path."
  - name: granularity
    required: false
    description: "A nudge on the factor/over-factor tradeoff: 'coarse' (fewer, larger tickets), 'balanced' (default), 'fine' (smaller tickets). Only shifts where inside the safe band the partition lands; it never overrides the hard ceiling or the shared-decision rule."
  - name: mode
    required: false
    description: "'seed' (default): plan a fresh build and seed the layout. 'extend': add a re-planning round to an existing build — read the current ledger, DEFERRALS.md, research-ledger §Q and BACKLOG.csv, then append inserts/splits/rounds and (for a legacy ledger at CAPSTONE) the standard tail rows, without renaming history."
  - name: tail
    required: false
    description: "The closeout tail appended when the chain has >1 implement-spec ticket: 'full' (default — CAP.1/CAP.2/CAP.3, GATE-ACCEPT, REC.1/REC.2/REC.3, DOC.1/DOC.2) or 'minimal' (CAP.1, CAP.3, DOC.1, DOC.2). 'none' is refused when N>1."
  - name: sequence_prefix
    required: false
    description: "Default true. Name ticket files with the NN[a-z]?_<ID>__<slug>.md global-sequence prefix so lexical order is chain order. Historical/legacy filenames a manifest chain table already lists are never renamed."
  - name: ledger
    required: false
    description: "Default true. Seed the build ledger. In COMMITTED mode (a docs/build/README.md marker, or tickets_dir under docs/) it is docs/build/LEDGER.md, committed. Otherwise it is the gitignored scratch ledger. When false, output the plan without persisting (planning-only / dry run)."
  - name: tickets_dir
    required: false
    description: "Where the per-ticket contracts + 00_MANIFEST.md go. In COMMITTED mode the default is docs/tickets (committed contract record, browsable beside the spec; build-memory init sets up docs/build, docs/adr too). In a repo that has NOT opted into committed build memory, the default stays the gitignored scratch dir ($SCRATCH/<build_name>-tickets/) — byte-for-byte the 0.1.x behaviour. Ignored when ledger=false."
---

# Decompose Spec

Turn **one large spec** into the **fewest self-contained tickets** that can each be implemented in a single
fresh context — then seed the durable **build ledger** that `orchestrate-build` drives to completion.

This is the **planning half** of a multi-session build. It does not implement anything, create branches, or run
code. Its entire job is to answer *"what are the units of work, in what order, and where do we cut?"* — well,
because **the decomposition is the ceiling on the whole build**: a bad split produces tickets with hidden
cross-dependencies that no downstream rigor can recover from (the multi-session analogue of "the build is only
as good as its spec"). Treat this as the highest-leverage, highest-rigor step, not a formality.

> **When to use:** a spec too large for one focused implementation run, that you intend to ship as a chain of
> reviewable PRs across multiple sessions. For a spec that fits one sitting, skip this and run `implement-spec`
> directly. The per-ticket worker in both cases is `implement-spec`.

## The objective (what "optimal" means here)

**Minimize the number of tickets `N`, subject to — for every ticket:**

1. **It fits one fresh-context `implement-spec` run with rigor headroom.** The ticket's working set (its spec
   slice + the code it must read + the tests + the self-review/gap/verify passes `implement-spec` runs *inside*
   it) stays **well under half** the worker's context window. On the `subagent` dispatch target this is a **hard
   failure boundary** — a subagent cannot compact, so a ticket that overflows *fails*. On `headless`/`manual` it
   is softer (the worker compacts, trading gap-analysis fidelity for survival). Size to the ceiling of the
   declared `dispatch_target`.
2. **It is one coherent, independently landable concern** — a single logical thing that stands alone as one
   CI-green PR, traceable to spec section(s). Soft proxies (not laws): ~one focused change, on the order of a few
   files and a few hundred lines. A large mechanical rename can be far bigger and still trivial; LOC is a proxy
   for *cognitive* size, not the target.
3. **It respects the dependency order** — a ticket never forks from work that hasn't landed yet.
4. **Its boundaries fall on the weakest-coupling seams** — cut where two units share the *least* (few
   cross-references, no shared implicit decisions), so each cut creates the fewest integration seams the capstone
   must later reconcile. High cohesion within a ticket; low coupling across.

**The two bounds you are balancing:**

- **Under-factoring (tickets too big)** → context rot: model accuracy degrades *well below* the window limit and
  accumulated irrelevant context hurts independently of raw length. This is the failure the fresh-context design
  exists to prevent; rule 1 is its guard.
- **Over-factoring (tickets too small)** → two costs. **(a) Fragmented decisions:** splitting one concern across
  tickets disperses *implicit* decisions (naming, a shared helper, a pattern) that then collide — the dominant
  failure mode of naive multi-agent coding. **(b) Multiplied fixed cost:** every ticket re-pays context
  bootstrapping (re-reading conventions, anchors, shared models) and every cut adds an integration seam and a PR
  to review.

So the balance is precise: **make each ticket as large as rule 1 safely allows, then stop splitting the moment a
cut would sever a shared implicit decision.** `granularity` only nudges where inside that safe band you land.

---

## Phase 0: Read the spec and the ground truth

1. **Read the spec in full** (and any companion docs it references). Extract four structured lists — you will
   partition against these and hand them to the ledger:
   - **Requirements** — every "shall / add / wire / implement" item, by section.
   - **Acceptance criteria** — the spec's explicit ACs plus any implied "must hold" invariants.
   - **Cross-cutting invariants** — the "every ticket must preserve" rules (back-compat/additive, wire-name
     stability, security invariants, "do not touch X"). These are the ACs most easily missed and belong at the
     top of the plan so every ticket re-checks them.
   - **Out-of-scope** — what no ticket does (the scope-creep guard the capstone and each gap-analysis rely on).
2. **Read the repo's ground truth** so tickets cut along real boundaries, not imagined ones: the AGENTS.md /
   CLAUDE.md hierarchy (root → subproject) for conventions and "ask-first" boundaries, and the spec's
   **integration anchors** (file:line) — open each so the partition respects the code's actual module structure.
   Anchors drift; record "re-confirm at build time" against each.

For a large spec, this reading is itself broad: you MAY fan out **read-only** subagents over subsystems (reading
is safe to parallelize; only *writes* must stay single-threaded). Each returns a compact map of its area's
seams and dependencies.

**In `mode=extend`** (a re-planning round on an existing build), also read the current build state before
cutting: `docs/build/LEDGER.md` (what has landed, `chainTip`, `round`), `docs/tickets/DEFERRALS.md` (owed work
that a new round may close), `docs/research-ledger.md` §Q (operator decisions), and `docs/build/BACKLOG.csv`
(carried debt). The new round's tickets fork from the current `chainTip`; you append to the manifest's chain
table and `## Plan extensions`, and never rename an existing ticket file (BM-COMPAT-05).

---

## Phase 1: Build the dependency + coupling map

Before cutting, understand the structure you are cutting:

- **Dependency DAG** — which requirements must land before which (data model before its consumers, an interface
  before its callers, a config key before the code that reads it). This fixes ordering and reveals the
  stacked-PR chain.
- **Coupling seams** — where the work naturally separates (module/package/layer boundaries, distinct files,
  distinct data flows) and, conversely, where units are tightly bound (they touch the same function, share a new
  helper, or encode the same design decision). The tight bindings are where you must NOT cut.
- **Repo boundaries** — units that live in a *different repository* are **out-of-chain**: they cannot stack on
  this repo's branch and must be tracked separately (they depend on the chain *informationally*, e.g. "needs the
  image name P2 publishes," not by git history).

---

## Phase 2: Partition into the ticket plan

Apply the objective. Produce, as a table, one row per ticket:

| Ticket | Scope (spec §§) | Files/anchors | forks-from / PR-base | Acceptance (deterministic / agentic) | Tests |

Rules for filling it:

- **Order by the DAG.** Number `T1..Tn` so every `forks-from` points at a ticket that lands earlier (no forward
  references). Chained tickets fork from the previous ticket's branch (the `chainTip` at run time); the PR
  `--base` is that same branch so each PR diff is exactly one ticket.
- **Mark out-of-chain rows** (different repo / deliberately independent): they do not advance `chainTip` and
  record their dependency as informational.
- **Include non-code rows where the build has them, marked as such.** Two kinds, each written as a **marker
  file** in the same global sequence (BM-TICKET-05, from `build-memory`'s `templates/HUMAN.md` / `templates/GATE.md`):
  **human prerequisites** (`NN[a-z]_HUMAN-H<k>__<slug>.md` — account registrations, outreach, procurement, work
  only the operator can do; listed so the chain never silently blocks on them) and **milestone gates**
  (`NN[a-z]_GATE-G<k>__<slug>.md` — a hard synchronization barrier or a pre-registered go/no-go, its thresholds
  quoted verbatim from the spec and recorded *before* the gated work begins). Neither is an `implement-spec`
  input: they do not advance `chainTip`. **A gate is a pause, not a block** — it is dispositioned by the operator
  (recorded in the ledger's GATE DECISIONS + a `readouts/GATE-G<k>.md`) and never guessed past; a pending gate is
  a `RETURN PASS` row, not a `blockedOn`.
- **Emit skeleton tickets after a gate where the body cannot be written yet** (BM-TICKET-03): `Kind: skeleton`,
  a `> Skeleton only` banner naming the gate, and only the header + `## Scope (one line)` + `## Spec §§` +
  `## REQ coverage`. A skeleton carries **no run line** — the validator refuses to run one and `implement-spec`
  stops if asked to.
- **Classify acceptance per ticket.** Is "done" **deterministic** (a unit/integration test, a byte-identity or
  behavioral check) or **empirical/agentic** (a repeat-scored metric on a benchmark set)? Agentic tickets need a
  benchmark fixture defined at SETUP — note it.
- **Respect the ceiling** from `dispatch_target` for every row (Phase-4 review re-checks this explicitly).
- **Keep shared decisions inside one ticket.** If two candidate tickets would both introduce or depend on the
  same new symbol/helper/convention, either merge them or make the *first* ticket own the decision and later
  tickets reference it — and note that dependency in the row.

---

## Phase 3: Author per-ticket contracts *(only where the spec lacks execute-grade ones)*

`implement-spec` diffs its work against a **contract**. If the spec already states a precise per-ticket contract,
reuse it. Where it only gives loose scope, author the missing contract for each such ticket — concrete enough
that a fresh context can implement against it without re-deriving the design:

- **Files/anchors touched** (file:line, "re-confirm at build time").
- **New symbols / models** — types, endpoints, config keys; for anything persisted, its stable wire name and the
  additive/back-compat rule ("optional, default = today's behavior").
- **Exact scope + what it must NOT do** (the per-ticket scope-creep guard).
- **Acceptance criteria** — numbered, each independently checkable (a test, a diff, a measured shift); marked
  deterministic or agentic.
- **Tests to write** — unit (pure logic), integration (seams), and (agentic) the benchmark-harness run.

Keep the cross-cutting invariants and out-of-scope list from Phase 0 at the top of the contract set — every
ticket's gap-analysis re-checks them. If the spec is so underspecified that contracts cannot be derived
(no decomposition *and* no derivable design), that is design work, not decomposition: **stop and tell the
operator the spec needs a design pass first** — do not invent a design.

**Each contract is its own file**, from `build-memory`'s `templates/ticket.md` (BM-TICKET-01) — written to the
tickets directory (committed mode: `docs/tickets`; otherwise the gitignored scratch dir) as
`NN[a-z]?_<ID>__<slug>.md` when `sequence_prefix` is true (the global sequence, zero-padded so lexical order is
chain order), else the legacy `T<nn>__<slug>.md` / `P<phase>.<k>__<slug>.md`. It carries the template's full
header (sequence, phase, kind, `base_branch: current checkout`, depends-on, the literal `Run:` line, `Gate
status`, `Live stage`) and body sections, ending with the universal phase-gate AC (BM-TICKET-02), so a fresh
worker loads **one small file** and nothing else. Two disciplines make the layout safe:

- **Cite, don't copy.** A ticket file *cites* the spec's sections and requirement IDs; it never restates the
  design — a restated design forks the spec, and the drift arrives with the first amendment. To change a
  requirement: amend the spec first, then the affected ticket's Load/AC lines.
- **Stamp requirement IDs.** Where the spec carries stable requirement IDs, each ticket lists the IDs it
  satisfies — to be stamped in its PR — and the Phase-4 coverage check runs on IDs: every in-scope ID maps to
  exactly one ticket, or to an explicit deferred table naming its target phase.

---

## Phase 4: Adversarial review of the split *(the quality gate)*

The partition is the ceiling on the build, and the context that just authored it is a biased reviewer of it.
Run a **fresh-context critique** — a subagent given only the spec, the plan, and the invariants where the
harness supports subagents; otherwise the explicit discipline of re-reading the spec and plan from disk and
arguing each judgment from what is there, not from memory of authoring it. Hunt specifically for:

- **Fragmented decisions** — any two tickets that secretly share an implicit decision (a name, a helper, a
  pattern). → merge them, or record the shared decision and assign ownership to the earlier ticket.
- **Overflow risk** — any ticket whose working set won't fit one fresh-context run at the declared ceiling.
  → split it at its next-weakest seam.
- **Orphan seams** — any integration point that no ticket owns because a cut created it. → assign it to a ticket
  or explicitly to the CAPSTONE.
- **Coverage + scope** — every spec requirement maps to exactly one ticket (nothing dropped, nothing
  double-owned); nothing in the out-of-scope list is scheduled.
- **Ordering** — no cycles, no forward `forks-from` references.
- **Over-factoring** — trivially small adjacent tickets that share context → merge to reclaim the fixed cost.

Revise the plan until the critique is clean or the remaining tradeoffs are consciously recorded. **The plan is a
starting point, not a contract in stone:** `orchestrate-build` may split an overflowing ticket or merge trivial
ones at run time and write the change back to the ledger. Note that explicitly so a later session knows the plan
is revisable.

---

## Phase 5: Seed the build memory

`build-memory` owns the layout; `decompose-spec` fills it. Everything below cites
`skills/build-memory/layout.md` and does not restate the tree. If `ledger=false`, skip every write and present
the plan + all sections to the operator instead.

**1. Initialise the layout.** Invoke the `build-memory` skill in `init` mode (idempotent — never overwrites an
existing file). In **committed** mode this creates `docs/build/{README.md (with the marker), LEDGER.md,
BUILD_INDEX.md, logs/.gitignore}`, `docs/adr/{README.md, _TEMPLATE.md}`, `docs/tickets/{_TEMPLATE.md,
DEFERRALS.md}`, the `AGENTS.md` build-memory section and the `docs/README.md` rows. A repo that has **not** opted
in stays in scratch mode — byte-for-byte the 0.1.x behaviour (a gitignored `${build_name}-build-ledger.md` and a
scratch tickets dir); everything below still applies, minus the commit.

**2. Write the state-only ledger** (`docs/build/LEDGER.md`, from the template, BM-LEDGER-01/02). It holds
**state only — the manifest is the plan.** The `CURRENT STATE` fenced block carries exactly the keyset in layout
order (`projectStatus … round … updatedAt`); seed `projectStatus: NOT_STARTED`, `nextTicket: SETUP`,
`manifest: docs/tickets/00_MANIFEST.md`, `canonicalSpec`, `memoryRoot`, `round: 1`. Below it: empty
`OPEN FINDINGS`, `GATE DECISIONS`, `RETURN PASS` tables, and a `PHASE LOG` with one seed entry (spec, ticket
count, "the plan is revisable at run time"). **No PHASE PLAN / SETUP / CAPSTONE sections** — those moved to the
manifest (the plan) and to tail tickets.

**3. Write the per-ticket contracts** (Phase 3) and the manifest.

**4. Write `docs/tickets/00_MANIFEST.md`** from the template (BM-MANIFEST-01), the human-facing runbook that
makes the chain self-driving **without** the ledger: the three banners (committed contract record; cite-don't-copy
with the spec amendment protocol; deferrals companion), a `companions:` line and an optional `req_id_pattern:`
line, `## How to build` (the four rules + the run-line pattern), `## Human prerequisites`, `## The chain`
(`| # | file | phase | kind | scope | gate |`, HUMAN/GATE marker and skeleton rows interleaved in order),
`## Milestone gates`, `## Phase gates & ownership notes`, `## Cross-cutting invariants`, `## Out of scope`,
`## Requirement-ID → ticket index`, `## Spec amendments applied`, `## Decomposition decisions` (incl. the Phase-4
adversarial review record), `## Plan extensions`.

**5. Append the tail** (BM-TAIL-01) when the chain has **more than one** implement-spec ticket: instantiate
`build-memory`'s `templates/tail/` — `tail=full` (CAP.1, CAP.2, CAP.3, GATE-ACCEPT, REC.1, REC.2, REC.3, DOC.1,
DOC.2) or `tail=minimal` (CAP.1, CAP.3, DOC.1, DOC.2) — filling the placeholders (`{{build_name}}`, `{{spec_path}}`,
`{{req_id_pattern}}`, `{{ticket_count}}`, `{{last_ticket}}`). Each becomes an ordinary chain row (`kind` capstone
| reconcile | docs). `tail=none` is refused when N > 1. The capstone is tickets — there is no CAPSTONE ledger
section.

**6. Persist the hand-off** when this run was invoked from a `docs/decomposition-prompt.md` — keep that file as
the frozen record of the exact invocation and binding constraints.

**7. Validate.** Run `bash skills/build-memory/scripts/check-build-memory.sh .` — it must exit 0 (layout, ticket
grammar + unique sequence, manifest ↔ files, backward deps, skeletons w/o run lines, DEFERRALS, ADR index, ledger
keys, REQ coverage). A failure is a real block: fix the seed, don't hand off a red layout. In committed mode,
this is the state `orchestrate-build` commits at SETUP.

### The spec amendment protocol
Ticket files **cite** the spec; they never copy the design (a restated design forks the spec, and the drift
arrives with the first amendment). To change a requirement: **amend the source spec first**; bump its
version/delta; requirement ids are **append-only**; add a `## Spec amendments applied` manifest line (date,
section, before/after or pointer, approver); write an **ADR** when a design decision changes; then update the
affected tickets' Load/AC lines (executed contracts get an appended `> Amended <date>:` note, never a rewrite).

---

## Hand off

Print a concise summary: the ticket count and the one-line scope of each, the chain shape (with out-of-chain rows
called out), any conscious tradeoffs from Phase 4, the ledger path, and the exact next step:

```
▶ To build: run orchestrate-build with ledger=<path>  (it will SETUP, then drive each ticket via implement-spec).
```

Also print the manual floor — it needs no orchestrator at all:

```
▶ Or by hand: in a fresh session, run  implement-spec spec=docs/tickets/<first ticket file>
  then, per docs/tickets/00_MANIFEST.md, chain the next file from the branch each ticket leaves checked out.
  Each worker closes its own ticket in docs/build/LEDGER.md (committed mode), so the chain advances with no orchestrator.
```

Report the validator result (`check-build-memory.sh` exit 0) as part of the hand-off. Do not create worktrees,
branches, or run anything — that is `orchestrate-build`'s job.

## What this does NOT do

- **No implementation, no branches, no worktrees, no execution** — pure planning + build-memory seeding
  (the manifest, the state-only ledger, the tickets, the tail; it writes docs, never code or branches).
- **No design authoring.** It decomposes an authoritative spec; it does not invent a missing design (that's a
  hard stop in Phase 3).
- **No runtime parameters** (worktree path, pinned base, autonomy) — those are resolved by `orchestrate-build` at
  SETUP; the ledger leaves placeholders.
