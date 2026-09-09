<!--
  Template: docs/research/CONVENTIONS.md (BM-SYNTH-02). Written by synthesize-spec mode=plan.
  The required shape of every research/design note. Notes are NN_<slug>.md under docs/research/
  or docs/design/. Frozen once written.
-->
# Research & design note conventions

## File header (required)

```
# <NN>_<slug> — <title>

**Stream:** <ledger stream id, e.g. A>
**Researched:** <ISO date>
**Author:** <agent id>
**Ledger rows covered:** <the ledger row ids this note answers>
**Confidence overall:** high | medium | low
```

## Finding format (required for every material claim)

```
### F<n> — <short claim>

**Claim:** <one sentence>
**Status:** VERIFIED | PARTIALLY VERIFIED | UNVERIFIED | CONTRADICTED | INACCESSIBLE
**Evidence:** <URL(s) actually fetched, with what they said>
**Retrieved:** <ISO date>
**Implication for the spec:** <what the design must do about it>
**Outline delta:** CONFIRMS | CORRECTS | EXTENDS | CONTRADICTS §<x> — <detail>
```

## Rules
1. Nothing cited that was not read; every material claim carries a fetched-source URL + date.
2. Every note ends with `## Open questions` and `## Spec requirements emitted` (numbered,
   each id `REQ-<STREAM>-<n>`).
3. A note answers ledger rows; it does not restate the spec.
4. Status is honest: `UNVERIFIED`/`INACCESSIBLE` is a valid outcome, not a gap to paper over.
