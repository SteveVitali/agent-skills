# Demo build manifest — the ticket chain

> **Committed contract record.** These ticket docs are a derived build artifact; they *cite*
> the spec and its requirement ids, never copy the design.
> **Cite, don't copy.** To change a requirement: amend the spec, bump its version, add a
> `## Spec amendments applied` line with before/after and approver, write an ADR when a design
> decision changes, then update affected tickets' Load/AC lines.
> **Deferrals companion:** owed work lives in `DEFERRALS.md` in this directory; read it first every run.

companions: DEFERRALS.md, _TEMPLATE.md
req_id_pattern: BM-[A-Z]+-[0-9]+
req_index_literal_from: 2

## How to build
Stacked-PR chain. Rules: (1) go in table order; (2) between tickets stay on the previous
ticket's branch; (3) STOP at GATE rows; (4) never let a code ticket block on a HUMAN row.
Run line: `implement-spec spec=docs/tickets/<file>`. `orchestrate-build` drives it from `LEDGER.md`.

## Human prerequisites
(none)

## The chain

### Round 1 — 2026-09-09 · seed

| # | file | phase | kind | scope | gate |
|---|---|---|---|---|---|
| 1 | `01_T1__seed-schema.md` | schema | ticket | seed the schema | — |
| 2 | `02_T2__wire-consumers.md` | wiring | ticket | wire the consumers | — |

### Round 2 — 2026-10-05 · state, lists, engine

| # | file | phase | kind | scope | gate |
|---|---|---|---|---|---|
| 3 | `03_T3__state-and-lists.md` | state | ticket | state versions and lists | — |
| 4 | `04_T4__engine-and-hypotheses.md` | engine | ticket | engine and hypotheses | — |

## Milestone gates
(none)

## Phase gates & ownership notes
T1 owns the schema shape; T2 consumes it.

## Cross-cutting invariants
- Additive / back-compat when the new table is empty.

## Out of scope
- No UI work.

## Requirement-ID → ticket index

### Round 1

| REQ family | id range | owning ticket |
|---|---|---|
| `BM-DEMO` | 1-2 | T1, T2 |

### Round 2

| REQ id | owning ticket |
|---|---|
| `BM-STATE-3` | T3 |
| `BM-LIST-2` | T3 |
| `BM-HYP-2` | T4 |
| `BM-ENG-3` | T4 |

## Spec amendments applied
(none)

## Decomposition decisions
Four tickets in two rounds; tail omitted for the fixture. Phase-4 adversarial review: clean.

## Plan extensions
- 2026-10-05 · Round 2 opened (T3, T4).
