# synthesize-spec — design rationale

`decompose-spec` and `implement-spec` assume a finished spec arrives from nowhere. In both production builds it
did not: the spec was itself a multi-day, multi-context effort — web research, design exploration, architecture
decisions, and several rounds of operator questions — before a single ticket existed. `synthesize-spec` is that
upstream half, given the same structure as the build so the same machinery drives it.

## Why a ledger of fresh-context rows, not one prompt

A spec worth decomposing is synthesized from more sources than one context can hold accurately. The **Context Rot
/ Lost-in-the-Middle** evidence that justifies fresh contexts per *ticket* applies just as hard to *research*: a
context that reads forty sources to write a spec has forgotten the first twenty by the end. So research and
design are **rows in a durable ledger** (`docs/research-ledger.md`), each executed in its own fresh context that
reads exactly its sources and writes one durable **note** in a fixed finding format (claim · status · evidence ·
retrieved · implication · outline delta). The spec is synthesized from the *notes*, not from a decayed context —
and because the ledger has a `CURRENT STATE` block, `drive-build.sh --skill synthesize-spec` drives it exactly
like a build.

## Why the review pass is fresh-context

`review` is deliberately a separate, fresh-context pass. A model reviewing a spec it just authored exhibits
**self-preference bias** — LLM evaluators measurably favour their own generations (Panickssery et al., NeurIPS
2024), the same finding behind `implement-spec`'s independent Pass 2 and `decompose-spec`'s adversarial Phase 4.
The review is given the spec and the ledger, never the authoring history, and dispositions every finding with the
`accept / adapt / rebut / defer` vocabulary `respond-to-review` uses — one shared epistemology across the repo.

## Why ratification is operator-gated

A spec that goes `canonical` on the model's own say-so launders unresolved questions into "decided." The `§Q`
operator-decisions register and the `⚑` fixed-constraint markers make the human's rulings part of the durable
record, and `ratify` is the one place they are *required*: open questions block ratification, answers are
recorded verbatim, and only then does the spec flip and the `decomposition-prompt.md` hand-off get written.

## The round structure

A round is research → synthesize → review. A second round is a **delta** over the first (the spec's delta
paragraph and a delta-only review), because re-reviewing an unchanged spec wholesale wastes the fresh context on
text that did not move. Operator answers at ratification can open a new round rather than being absorbed silently.

## Honest limitations

- **Research quality is bounded by source access.** A source the tools cannot fetch is recorded `INACCESSIBLE`,
  never paraphrased into a claim — but that means some questions stay `UNVERIFIED` and surface as risks, not
  answers.
- **Superset coverage is checked structurally, not semantically.** `OUTLINE_TRACE.md` proves every `OL-*`
  obligation maps to a section or a conscious de-scope; it cannot prove the section actually *satisfies* the
  obligation — that is the review pass's judgment.
- **It does not decompose or implement.** The deliverable is a ratified spec + the `decomposition-prompt.md`
  hand-off; `decompose-spec` takes it from there and begins the committed build memory.
- **`drive-build.sh --skill synthesize-spec` still needs an external initiator** (a headless CLI or subagent);
  on IDE-only harnesses the honest floor is a human re-invoking per unit, same as `orchestrate-build`.

## References

- The layout it reads/writes: `skills/build-memory/layout.md` (`research-ledger.md`, `research/`, `design/`,
  the spec, `decomposition-prompt.md`).
- Panickssery, Bowman, Feng — *LLM Evaluators Recognize and Favor Their Own Generations*, NeurIPS 2024.
- Hong et al. — *Context Rot* (Chroma, 2025); Liu et al. — *Lost in the Middle*, TACL 2024.
- The sibling execution half: `decompose-spec` (planning) and `orchestrate-build` (execution).
