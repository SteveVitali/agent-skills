<!--
  Template: docs/build/readouts/<GATE-G<k> | GATE-ACCEPT | HUMAN-H<k>>.md — a readout (BM-INDEX-03).
  Written by: orchestrate-build when it reaches the marker row (build-memory init also copies this
  file to docs/build/readouts/_TEMPLATE.md). APPEND-ONLY: the `Status:` line is the only line that
  ever changes; signing APPENDS the Signature block and never edits or deletes anything above it
  (not the guard sentence, not pending text, not a checkbox). Any text the agent wrote sits in the
  agent-drafted block with its sha256 (`shasum -a 256` of the block body). Dates: `date -u` (BM-CLOCK-01).
-->
# <GATE-G<k> | GATE-ACCEPT | HUMAN-H<k>> readout
Status: PENDING   <!-- the ONLY line that may change: → SIGNED | PASSED | SKIPPED-BY-OPERATOR | NOT-PASSABLE -->

> An operator or authorized human record supplies the decision; an agent must not sign or assume silence is
> approval.

## Criterion (verbatim)
<quoted verbatim from the marker / the spec §; thresholds as pre-registered>

## Evidence (per item: source, `date -u` of the read, layer reached)
- <item> — <source> — read <date -u +%FT%TZ> — layer: <BM-STATUS-01 word>

<!-- agent-drafted:begin sha256=<64 hex> -->
<any summary the agent wrote>
<!-- agent-drafted:end -->

## Signature   <!-- appended at signing; nothing above is edited or deleted -->
<!-- Appended only when the operator has answered; an agent never writes these lines on its own authority:
Operator decision (verbatim, received <date -u +%FT%TZ> via <channel>): "<exact words>"
GATE DECISIONS row: <date -u +%FT%TZ> | <gate>
Operator confirmation of agent-drafted text (verbatim, <date -u +%FT%TZ>): "<words>" — covers sha256:<first 12>
Signed by: the operator. Recorded by <harness/model>, which does not sign.
-->
