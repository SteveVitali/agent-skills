<!--
  Template: docs/tickets/00_MANIFEST.md (BM-MANIFEST-01..04). Written by decompose-spec via
  build-memory init; extended by decompose-spec mode=extend and orchestrate-build (inserts/
  splits append to ## Plan extensions). The manifest is COMPLETE ON ITS OWN — a human with a
  terminal can drive the chain from it without the ledger. Sections MUST appear in this order.
-->
# <build> manifest — the ticket chain

> **Committed contract record.** These ticket docs are a derived build artifact; they *cite*
> the spec and its requirement ids, they do not copy the design. This chain table is
> authoritative if it and a filename ever disagree.
> **Cite, don't copy — the spec amendment protocol.** To change a requirement: amend the
> source spec; bump its version / delta; ids are append-only; add a `## Spec amendments
> applied` line with before/after (or a pointer) and the approver; write an ADR when a design
> decision changes; then update the affected tickets' Load/AC lines.
> **Deferrals companion.** Acceptance criteria/deliverables a ticket cannot finish at
> implementation time are tracked in `DEFERRALS.md` in this directory — read it first every run.

companions: DEFERRALS.md, _TEMPLATE.md
req_id_pattern: <the spec's requirement-id ERE, e.g. REQ-[A-Z]+-[0-9]+>

## How to build
Stacked-PR chain. Rules: (1) go in table order; (2) between tickets, stay on the previous
ticket's branch so PRs stack; (3) STOP at every GATE row until the operator reads it out —
never guessed past; (4) HUMAN rows are operator work — start them when the table reaches them
and never let a code ticket silently block on one. Run line, per row:
`implement-spec spec=docs/tickets/<file> <per-ticket flags>`. `orchestrate-build` drives this
from `docs/build/LEDGER.md`; a human can drive it by hand from this table alone.

## Human prerequisites
<the HUMAN-H<k> rows — operator work, not code tickets>

## The chain

| # | file | phase | kind | scope | gate |
|---|---|---|---|---|---|
| 1 | `01_<ID>__<slug>.md` | <phase> | ticket | <one line> | — |

<!-- kind ∈ ticket | human | gate | skeleton | capstone | reconcile | docs; marker rows interleaved in order -->

## Milestone gates
<the gate thresholds, quoted verbatim from the spec; pre-registered, never guessed past>

## Phase gates & ownership notes
<barriers; external-dependency rows that must never block the chain; logic several tickets consume>

## Cross-cutting invariants
<the "every ticket re-checks" rules; the capstone re-checks all>

## Out of scope
<what no ticket does; the capstone verifies none crept in>

## Requirement-ID → ticket index
<REQ id → owning ticket; authoritative for coverage>

## Spec amendments applied
<append-only: date · section · before/after or pointer · approver · ADR>

## Decomposition decisions
<the split rationale, incl. the Phase-4 adversarial review record>

## Plan extensions
<append-only: inserts (16a_…), splits (<ID>a/<ID>b, original marked superseded-by-split), rounds>
