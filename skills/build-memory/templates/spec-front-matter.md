<!--
  Template: the front matter + §0 of a synthesized spec (BM-SYNTH-03). Written by synthesize-spec
  (mode synthesize) at the head of docs/<build_name>-spec.md. The spec body (the numbered sections
  and appendices A–E) follows; this template covers only the front matter, §0 how-to-read, and the
  requirement-ID convention. Status flips to "canonical" at ratification (mode ratify).
-->
# <Build> — <Product / systems> design specification

- **Status:** Draft for operator review · <date>   <!-- flips to "canonical <date> — ratified by the operator (Q-* resolved)" at ratify -->
- **v<prev> → v<this> delta, one paragraph:** <what changed since the prior version, and why — "initial" for round 1>
- **Synthesized from:** the research/design notes under `docs/research/` and `docs/design/` (see Appendix C) and the founding brief `docs/brief.md`; binding inputs are the brief and the operator decisions register (`docs/research-ledger.md` §Q).
- **Supersedes:** every design note on any point where they disagree.

## 0. Front matter

### 0.1 How to read this document
One self-contained spec. The contracts adopted **by reference as normative** are: <list them>. Section map:
<which section ranges cover product / UI-UX / systems / ops / appendices>. Wireframes are ASCII; diagrams are
Mermaid.

### 0.2 Requirement-ID convention
Every requirement carries a stable identifier **`REQ-<FAMILY>-<n>`**, **append-only** (an id is never renumbered
or reused; a fold-back gets a new id in its family). Families → source: <enumerate the families, e.g. CORE, UI,
DATA, ARCH, OPS, …>. Reserved ids: <any held back>. The machine-readable pattern the decomposition and the
validator use: `req_id_pattern: REQ-[A-Z]+-[0-9]+`.

### 0.3 Decision register summary
<the synthesis rulings that resolved conflicts between notes — a table `| # | conflict | ruling |`; full detail in Appendix B>

### 0.4 Table of contents
<numbered sections + appendices A (requirement index) · B (decision register) · C (research index) · D (glossary + reserved strings) · E (review dispositions)>
