<!--
  Template: docs/build/reports/audits/<date -u +%F>_<eval-id>.plan.md. Commit it BEFORE any evaluation
  audit runs. After that, only append to the Deviations section.
-->
# Evaluation plan <eval-id>

- **Recorded:** <date -u +%FT%TZ>
- **Head:** <sha>
- **Recorder:** <harness>/<model-id>

## Questions
Keep, drop or extend Q1–Q7 from modes/evaluate.md § 1. Name the primary question.

## Population, strata and sample
- Eligible tickets: …
- Strata per ticket: implementer · kind (primitive / consumer / fixture-oracle / integration / ui) · size.
  The table is fixed before auditing.
- Sampling: all, or stratified random (seed: …, draw: …). Exclusions and reasons: …
- Baseline / control implementer and its matched tickets: …

## Blinding
What is withheld in Pass A, and how the guess-the-implementer check is recorded.

## Duplicate subset
Ticket ids (≥ 20% and ≥ 3), with an independent auditor context per round.

## Positive control (optional)
Tickets, the planting context, and where the sealed defect list lives.

## Auditor and verifier
Harness, model and effort requested; how the actual values are recorded.

## Decision rule
The default from modes/evaluate.md § 4, or a replacement. C_escape (operator's value or ratio): … · risk
threshold: … · re-evaluation trigger: …

## Analysis
The exact `audit-stats.py` invocation, and the tables the report will contain.

## Deviations (append-only)
- <date -u +%FT%TZ> — …
