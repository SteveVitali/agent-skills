<!--
  Template: ticket contract (docs/tickets/NN[a-z]?_<ID>__<slug>.md).
  Filled by: decompose-spec (one file per ticket) — also the _TEMPLATE.md init writes.
  When: seed / extend. Executed contracts are frozen (BM-TICKET-04): amend by appending
  a `> Amended <date -u +%F>:` note pointing at the manifest amendment line, never by rewriting.
  These docs CITE the spec's §§ and requirement ids; they never copy the design.
-->
# <ID> — <short title>

- **Sequence:** <n> of <N> · **Phase:** <phase> · **Kind:** ticket   <!-- ticket | human | gate | skeleton | capstone | reconcile | docs -->
- **Tag:** <optional, e.g. beta / post-beta>
- **base_branch:** current checkout
- **Depends on:** <prior ids, or "nothing"> <!-- must point backward in the chain -->
- **Run:** `implement-spec spec=docs/tickets/<file>.md <per-ticket flags>`
- **Gate status:** none   <!-- or a block of operator ticks -->
- **Live stage:** offline-only   <!-- none | offline-only | operator-gated: <budget> -->
- **Production mutations:** none  <!-- none | list: what · scripted path · pre-state capture · rollback (BM-PROD-01) -->
- **Size budget:** <N> changed lines excl. generated/fixtures  <!-- over budget → split via decompose-spec first -->

## Goal
<one paragraph: what this ticket makes true>

## Load (read these — do not re-read others)
- <the spec §§ and reference files this ticket needs, and nothing more>

## In scope — deliverables
1. <deliverable> (<REQ ids it satisfies>)

## Out of scope
- <what a sibling ticket owns — name the owning ticket>

## Acceptance criteria
<!-- layer: the BM-STATUS-01 word the AC must reach (engineered | fixture-verified | staging-verified | live-executed | public | human-completed) -->
- [ ] <criterion> *(deterministic · layer: engineered)*
- [ ] <criterion> *(agentic · layer: engineered)*
- [ ] verification green; every new behaviour has a test that fails if it is removed; requirement ids stamped in the PR; anything not automatically verifiable is a `DEFERRALS.md` row with its compensating control; ADRs written for every deviation and owned decision; `BUILD_INDEX.md` row and `LEDGER.md` advanced; operating clauses met — dates from the clock, PR checks read and recorded, AC layers stated, no living-record pins, protected records only appended, gate words verbatim, harness in the run-ledger header. *(agentic — the universal phase-gate AC)*

## Requirement IDs to satisfy and stamp in the PR
<REQ ids>

## Cross-cutting invariants
- <cited from docs/tickets/00_MANIFEST.md § Cross-cutting invariants>

## Operating clauses
- Cited from `docs/tickets/00_MANIFEST.md § Operating rules`; the gap table has one row per clause.

## Notes
- <decisions this ticket owns; anchors to re-confirm at build time>
