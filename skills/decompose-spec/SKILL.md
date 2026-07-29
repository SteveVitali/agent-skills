---
name: decompose-spec
license: MIT
description: "Turn one large spec into an optimally-partitioned, dependency-ordered ticket plan — the fewest self-contained tickets that each fit one fresh-context implementation run — and seed a durable build ledger. The planning half of a multi-session build; pairs with orchestrate-build."
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
  - name: ledger
    required: false
    description: "Default true. Write the seeded build ledger to the gitignored scratch dir. When false, output the plan to the operator without persisting (planning-only / dry run)."
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

## Phase 5: Seed the build ledger

Write the durable ledger — the single source of truth that every later fresh context (worker or orchestrator)
reads to get its bearings. Put it in the repo's canonical, **gitignored** scratch location:

```bash
SCRATCH="${AGENT_SCRATCH_DIR:-$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.agents/scratch}"
mkdir -p "$SCRATCH"    # must be gitignored; never commit the ledger
LEDGER="$SCRATCH/${build_name}-build-ledger.md"
```

Write these sections (this is the exact structure `orchestrate-build` and `drive-build.sh` parse):

### `CURRENT STATE` — a grep-friendly `key: value` block, parsed first
Keep it plain `key: value` lines (machine-readable by a shell loop, and models are less likely to rewrite a
structured status block than prose):
```
projectStatus:   NOT_STARTED        # NOT_STARTED | IN_PROGRESS | BLOCKED | CAPSTONE | DONE
nextTicket:      SETUP              # SETUP, then T1..Tn per the ordering, then CAPSTONE, then DONE
lastCompleted:   (none)
blockedOn:       (nothing)
pauseRequested:  false              # the human sets true to halt the loop at the next ticket boundary
canonicalSpec:   <path to the spec>
dispatchTarget:  <subagent|headless|manual>
buildWorktree:   (set at SETUP)
buildBranchBase: (set at SETUP)
pinnedBaseSha:   (set at SETUP)
chainTip:        (set at SETUP; advances per completed chained ticket)
benchmarkSet:    (id | PENDING_CREATE | N/A)
autonomy:        (set by orchestrate-build)
updatedAt:       <date>
```

### `PHASE PLAN` — the canonical ticket table from Phase 2 (do not reorder), with a legend defining `forks-from / PR-base` and marking out-of-chain rows, plus the per-ticket contracts (or a pointer to where they live).

### `CROSS-CUTTING INVARIANTS` and `OUT OF SCOPE` — from Phase 0, verbatim; every ticket and the capstone re-check these.

### `SETUP checklist` — the one-time bootstrap `orchestrate-build` runs: create the dedicated worktree off the pinned base, baseline-green check, stand up the benchmark fixture if any ticket is agentic (with its safe-creation recipe and pollution hazard called out), then set `chainTip`, `nextTicket=T1`, `projectStatus=IN_PROGRESS`.

### `CAPSTONE checklist` — the one-time whole-chain closeout after the last ticket: a fresh whole-chain gap analysis vs the *entire* spec → close real gaps / consciously accept sound deviations → a composed end-to-end verification exercising the whole build as one unit. (Templated here; `orchestrate-build` runs it.)

### `PHASE LOG` — append-only, newest last. Seed one "ledger created" entry noting the spec, the ticket count, and that the plan is revisable at run time.

If `ledger=false`, skip the write and present the plan + all sections to the operator instead.

---

## Hand off

Print a concise summary: the ticket count and the one-line scope of each, the chain shape (with out-of-chain rows
called out), any conscious tradeoffs from Phase 4, the ledger path, and the exact next step:

```
▶ To build: run orchestrate-build with ledger=<path>  (it will SETUP, then drive each ticket via implement-spec).
```

Do not create worktrees, branches, or run anything — that is `orchestrate-build`'s job.

## What this does NOT do

- **No implementation, no branches, no worktrees, no execution** — pure planning + ledger seeding.
- **No design authoring.** It decomposes an authoritative spec; it does not invent a missing design (that's a
  hard stop in Phase 3).
- **No runtime parameters** (worktree path, pinned base, autonomy) — those are resolved by `orchestrate-build` at
  SETUP; the ledger leaves placeholders.
