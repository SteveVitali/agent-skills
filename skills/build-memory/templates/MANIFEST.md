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
never guessed past; (4) HUMAN rows are scheduled operator work (owner + date or trigger) —
start them when the table reaches them and never let a code ticket silently block on one. Run
line, per row: `implement-spec spec=docs/tickets/<file> <per-ticket flags>`. `orchestrate-build`
drives this from `docs/build/LEDGER.md`; a human can drive it by hand from this table alone.

## Human prerequisites
<the HUMAN-H<k> rows — operator work, not code tickets; each with owner + scheduled date or trigger>

## The chain

### Round 1 — <date -u +%F> · <one-line purpose>
<!-- every row sits under a numbered round banner; mode=extend opens `### Round <n>` and appends under it -->

| # | file | phase | kind | scope | gate |
|---|---|---|---|---|---|
| 1 | `01_<ID>__<slug>.md` | <phase> | ticket | <one line> | — |

<!-- kind ∈ ticket | human | gate | skeleton | capstone | reconcile | docs; marker rows interleaved in order -->
<!-- a row leaves the nextTicket order only by a gate-cell token: superseded-by(<ids>) · superseded-by-split · deferred(<D-id>) · unused (V2) -->

## Milestone gates
<the gate thresholds, quoted verbatim from the spec; pre-registered, never guessed past, never pre-answered>

## Phase gates & ownership notes
<barriers; external-dependency rows that must never block the chain; logic several tickets consume>

## Cross-cutting invariants
<the "every ticket re-checks" rules; the capstone re-checks all>

## Operating rules (binding on every ticket)
<!-- Short forms; full text in build-memory layout.md. Append the project's own OPERATING MODE rules below. -->
- **Clock (BM-CLOCK-01).** Every date written is `date -u` at that moment (or the git/GitHub time of the event, source named); never later than the commit that records it.
- **CI (BM-CI-01).** PR checks are read at every ticket boundary and recorded; red, pending or unreadable → `blockedOn`; nothing stacks on red; a local-only result is "locally-green".
- **Status layers (BM-STATUS-01).** Every status names its layer (engineered · fixture-verified · staging-verified · live-executed · public · human-completed); MET only at the requirement's own layer.
- **Gate records (BM-GATE-05…09).** Operator words verbatim with `date -u` + channel; tentative words get a yes/no confirmation; no proxy signatures; agent-drafted text labelled and hash-confirmed; pre-authorizations list item ids, `expires:`, `voided-by:`.
- **Production (BM-PROD-01).** No production mutation outside a ticket whose `Production mutations:` header names it (scripted path, pre-state capture, rollback).
- **Tests (BM-TEST-01).** Tests assert invariants, never the current value of a living record; a failing pin is converted or deleted in its own commit, never relaxed.
- **Harness (BM-HARNESS-01).** Harness + model id in CURRENT STATE `harness:` and every run-ledger header; commits trailered; a switch only at a ticket boundary, on the operator's words, recorded.
- **Records (BM-HIST-01).** Protected records only gain lines, at their ends (`check-build-memory.sh --staged` before the closeout commit); corrections are new dated entries.
- **Reporting (BM-DIGEST-01).** Progress lines name the layer reached; an operator digest at every pause and at the project's cadence; stop and ask rather than proceed on red CI, a date not from the clock, tentative words or a harness change.

## Out of scope
<what no ticket does; the capstone verifies none crept in>

## Requirement-ID → ticket index
<REQ id → owning ticket; authoritative for coverage>

## Spec amendments applied
<append-only: date -u +%F · section · before/after or pointer · approver · ADR>

## Decomposition decisions
<the split rationale, incl. the Phase-4 adversarial review record; the tail choice (tail=full names which REC rows read live state and why); any operator pre-authorization quoted verbatim>

## Plan extensions
<append-only: inserts (16a_…), splits (<ID>a/<ID>b, original marked superseded-by-split), rounds>
