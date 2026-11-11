# Demo build manifest — the ticket chain

> **Committed contract record.** These ticket docs are a derived build artifact; they *cite*
> the spec and its requirement ids, never copy the design.
> **Cite, don't copy.** To change a requirement: amend the spec, bump its version, add a
> `## Spec amendments applied` line with before/after and approver, write an ADR when a design
> decision changes, then update affected tickets' Load/AC lines.
> **Deferrals companion:** owed work lives in `DEFERRALS.md` in this directory; read it first every run.

companions: DEFERRALS.md, _TEMPLATE.md
req_id_pattern: BM-[A-Z]+-[0-9]+

## How to build
Stacked-PR chain. Rules: (1) go in table order; (2) between tickets stay on the previous
ticket's branch; (3) STOP at GATE rows; (4) never let a code ticket block on a HUMAN row.
Run line: `implement-spec spec=docs/tickets/<file>`. `orchestrate-build` drives it from `LEDGER.md`.

## Human prerequisites
(none)

## The chain

| # | file | phase | kind | scope | gate |
|---|---|---|---|---|---|
| 1 | `01_T1__seed-schema.md` | schema | ticket | seed the schema | — |
| 2 | `02_T2__wire-consumers.md` | wiring | ticket | wire the consumers | — |

## Milestone gates
(none)

## Phase gates & ownership notes
T1 owns the schema shape; T2 consumes it.

## Cross-cutting invariants
- Additive / back-compat when the new table is empty.

## Out of scope
- No UI work.

## Requirement-ID → ticket index
- BM-DEMO-01 → T1
- BM-DEMO-02 → T2

## Spec amendments applied
(none)

## Decomposition decisions
Two tickets; tail omitted for the fixture. Phase-4 adversarial review: clean.

## Plan extensions
(none)
