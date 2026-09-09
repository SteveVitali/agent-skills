---
name: synthesize-spec
license: MIT
description: "Turn a brief into a ratified, decomposable spec the way orchestrate-build turns a plan into a build: a durable research ledger whose rows are executed in fresh contexts, then synthesis, adversarial review, and operator ratification. Use it for the UPSTREAM half of a large build — when the spec does not yet exist or is still a moving target and the work spans research, design, and operator decisions across multiple sessions. Pairs with decompose-spec (it writes the decomposition-prompt.md hand-off). For a spec that already exists, skip this and run decompose-spec."
inputs:
  - name: brief
    required: true
    description: "The founding brief / prompt — a file path (preferred). The seed the whole synthesis traces back to; an OUTLINE_TRACE proves the spec is a superset of it."
  - name: spec_out
    required: false
    description: "Where the synthesized spec is written. Default: docs/<build_name>-spec.md."
  - name: build_name
    required: false
    description: "Short kebab slug for the build. Derived from the brief title if omitted."
  - name: rounds
    required: false
    description: "Default 1. How many research→synthesize→review rounds to plan before ratification (a second round is a delta over the first)."
  - name: adversarial_review
    required: false
    description: "Default true. Run the fresh-context adversarial review pass (mode review) before ratification."
  - name: outline_trace
    required: false
    description: "Default true when a brief exists. Maintain OUTLINE_TRACE.md of OL-* obligations and prove superset coverage in an appendix."
  - name: operator_questions
    required: false
    description: "Default true. Accumulate open questions in the ledger's Q register and require operator answers at ratification."
  - name: mode
    required: false
    description: "'plan' | 'run' | 'synthesize' | 'review' | 'ratify'. Default: auto-resolved from docs/research-ledger.md CURRENT STATE (like orchestrate-build §0)."
---

# Synthesize Spec

Produce a **ratified, decomposable spec** from a **brief** — the upstream half of a large build. Both reference
builds' upstream halves were multi-day, multi-context efforts with operator decision rounds; a single-context
"write me a spec" call cannot hold that. So this skill has the **same shape as the build itself**: a durable
**research ledger** whose rows are executed in **fresh contexts**, exactly as `orchestrate-build` executes
tickets, then synthesis, adversarial review, and operator ratification.

> **The mental model.** State lives on disk (`docs/research-ledger.md`). Cognition lives in fresh contexts (each
> research/design row; the review pass). Sequencing is a loop that reads the ledger, runs the next unit, writes
> the ledger back — so `drive-build.sh --skill synthesize-spec` can drive it, honoring `pauseRequested` and
> stopping at operator-decision points. It hands off to `decompose-spec` by writing `docs/decomposition-prompt.md`.

The layout it reads and writes (`docs/research-ledger.md`, `docs/research/`, `docs/design/`, the spec,
`docs/decomposition-prompt.md`) is defined in `skills/build-memory/layout.md`; this skill cites it and does not
restate the tree.

## Orient (every invocation)

Resolve the mode from the ledger, the way `orchestrate-build` orients:

- No `docs/research-ledger.md` yet → **`plan`** (§ `modes/plan.md`).
- Ledger present → read its `CURRENT STATE` block (`nextUnit`, `projectStatus`, `round`). `projectStatus: DONE`
  or spec Status `canonical` → nothing to do; report and stop. An open research/design row is `nextUnit` →
  **`run`**. All rows done, no spec yet (or a new round) → **`synthesize`**. Spec written, not yet reviewed →
  **`review`**. Reviewed and dispositioned, awaiting operator → **`ratify`**.
- An explicit `mode` input overrides.
- `pauseRequested: true` or an unanswered operator-decision (`⚑`) row that blocks progress → report and stop
  (this is the human's decision surface, like a gate).

Then follow the matching mode file below; each ends by updating the ledger's `CURRENT STATE` + change log and
returning here.

## The modes

| Mode | File | What it does |
|---|---|---|
| `plan` | [modes/plan.md](modes/plan.md) | Seed `docs/research-ledger.md`: theses, lettered research/design streams as `\| id \| item \| owner \| status \| evidence \|` tables, the §O process, the §Q operator register, and a `CURRENT STATE` block so the loop can drive it. |
| `run` | [modes/run.md](modes/run.md) | Execute **one** open ledger row per fresh context → a note under `docs/research/` or `docs/design/` in the `CONVENTIONS.md` finding format, emitting `REQ-<STREAM>-<n>` requirements and open questions. |
| `synthesize` | [modes/synthesize.md](modes/synthesize.md) | Write the spec: front matter, §0 how-to-read + requirement-ID convention, decision register, appendices A–E, and (with a brief) `OUTLINE_TRACE.md` proving superset coverage. |
| `review` | [modes/review.md](modes/review.md) | Fresh-context adversarial pass (consistency, coverage of every ledger row, MVP realism, self-contradiction); delta-only when a prior version exists; findings dispositioned in Appendix E. |
| `ratify` | [modes/ratify.md](modes/ratify.md) | Present open Q rows, record answers, flip the spec to `canonical`, freeze the ledger, and write `docs/decomposition-prompt.md` — the hand-off to `decompose-spec`. |

## Why fresh contexts and a ledger (not one big prompt)

- **Research is broad and lossy.** A single context that reads dozens of sources to write a spec has forgotten
  the early sources by the end. Each row's fresh context reads exactly its sources and writes a durable note; the
  spec is synthesized from the **notes**, not from a decayed context.
- **Review must be independent.** A context that just wrote the spec is a biased reviewer of it (the same
  self-preference bias `implement-spec` and `decompose-spec` guard against). `review` runs in a fresh context
  given the spec + the ledger, not the authoring history.
- **Operator decisions are first-class.** The `§Q` register and `⚑` markers make the human's rulings part of the
  durable record, and `ratify` is the one place they are required — no spec goes `canonical` with open questions.

## What this skill does NOT do

- **No decomposition, no implementation** — it produces the spec and the `decomposition-prompt.md` hand-off;
  `decompose-spec` and `implement-spec` take it from there.
- **No inventing findings** — nothing is cited that was not read (the ledger's standing rule); an inaccessible
  source is recorded as `INACCESSIBLE`, never paraphrased into a claim.
- **No ratifying on the model's own say-so** — `canonical` requires the operator's answers to the open Q rows.
