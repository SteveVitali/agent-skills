<!--
  Template: docs/build/reports/audits/<date -u +%F>_<audit-id>.md (append-only; never edit an earlier
  report: a re-audit writes a new one that cites it). The front-matter keys are parsed by
  scripts/audit-scope.sh: keep them one per line, as `key: value`.
-->
---
audit-id: A<date -u +%Y%m%d>-<short head sha>
mode: audit            # audit | evaluate
scope: <since-last | last=N | tickets=… | range=…>
audited-through: <last in-scope ticket id>
head: <full sha audited>
previous-audit: <audit-id | none>
auditor: <harness>/<model-id> (effort as reported: …; requested: …)
verifier: <harness>/<model-id> (effort as reported: …; requested: …)
blind: <true | false> (held: <n/N guesses wrong or low-confidence>)
recorded: <date -u +%FT%TZ>
---

# Audit <audit-id>

## Verdict

| ticket | implementer | stratum | verdict (clean / fixes-needed / blocked) | confirmed b/M/m/n | routes |
|---|---|---|---|---|---|

## Findings (confirmed and plausible, most severe first)

### <finding-id> · <severity> · <category> · <ticket>
- **Claim:** …
- **Evidence:** file:line · reproduction `…` → observed output …
- **Failure scenario:** …
- **Verifier:** <verdict> (`…`)
- **Origin:** … · **Route:** repair on PR #… | return pass | insert via decompose-spec | operator (spec)
- **Blast radius:** dependent tickets checked: …

## Earlier findings re-checked
| finding | earlier audit | status (fixed / still-open / regressed) | evidence |
|---|---|---|---|

## Cross-ticket (Pass D)
Duplication · interface drift · invariants at head · regressions · records · process.

## Measurements
| context | role | tokens | wall time | notes |
|---|---|---|---|---|

Mutation sample: <killed>/<total> (per ticket: …).

## Limitations
What was sampled rather than exhaustively checked; what could not run, and why; how independent and
blind the audit actually was; known auditor bias.

## Recommended coordinator actions
Routes per finding; `pauseRequested: true` if any blocker exists (finding ids).

<!-- evaluate mode only: -->
## Evaluation results
Per stratum: Q1 k/n [Wilson 95%] · Q2–Q5 tables · auditor precision · kappa · Lincoln–Petersen ·
seeded recall · Q7 cost. Paste the `audit-stats.py` output verbatim.

## Recommended audit policy
The rule, the numbers that drove it, the re-evaluation trigger and the threats to validity.
