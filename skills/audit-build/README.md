# audit-build: design rationale

## The problem

Implementation is the expensive part of a long build, and the obvious way to cut cost is a cheaper model
for the routine tickets. The risk is that a cheaper implementer's defects *compound*: each ticket builds on
the last, and `implement-spec`'s in-ticket review is run by the same harness, often the same model family,
under the same context pressure. A defect it misses is inherited by every later ticket.

`audit-build` is a separate, later line of defense. A fresh context, ideally on a stronger model,
re-reviews several landed tickets together. It is not anchored on the author's conclusions, it can see
across tickets, and it routes what it finds through the build's existing repair mechanisms.

## Why it measures before it polices

"Audit every five tickets" is a guess. The right amount of auditing depends on the implementer, the
harness, the kind of ticket and the cost of an escaped defect. Those are measurable, so the skill ships an
evaluation mode built like a small study:

- **Pre-registration.** The questions, strata, sample, decision rule and analysis are fixed before any
  results are seen, so the conclusions can't be fitted to the data afterwards.
- **A control group.** Tickets from a reference implementer go through the same protocol. Auditors almost
  always find *something*; only a comparison shows whether the cheaper implementer is actually worse.
- **Blinding.** Pass A never sees who built the ticket or what they claimed, and auditors record a guess
  so we know whether the blinding held.
- **Independent verification.** A separate context reproduces every finding. That yields auditor
  precision, and it keeps refuted findings out of the action list.
- **A duplicate subset.** Some tickets are audited twice, independently. That measures auditor agreement
  (Cohen's kappa) and gives a rough recall estimate (Lincoln–Petersen capture–recapture).
- **Optional seeded defects.** Planted bugs give a direct recall measurement.
- **Honest uncertainty.** Rates are reported with Wilson intervals. Per-stratum samples are small, and the
  report says so instead of hiding it in a point estimate.
- **A derived policy.** Audit everything in a stratum when the upper bound of its defect rate, times the
  cost of an escape, exceeds the cost of an audit. Otherwise sample in proportion to that ratio. Re-evaluate
  when anything about the implementer changes.

For the same reason, the skill adds no hook or default schedule to `orchestrate-build`. A cadence should be
an operator decision backed by that evidence.

## Why it never fixes

An audit that also fixes stops being independent: it starts grading its own work. And the build already
has disciplined ways to fix things: a bounded repair on an open PR, a return pass, or an insert through
`decompose-spec mode=extend`. Each runs in a fresh context with its own review. The audit only routes.

## Why two passes per ticket

Pass A (blind conformance) establishes what the code actually does against the contract, before the auditor
reads any claims. Pass B (claims) then compares the run ledger, PR body and closeout with that independent
picture. Overclaiming ("met at fixture layer", "all fixed", "CI green") is a common and costly failure for
autonomous implementers, and it can only be measured if the auditor formed its own view first.

## Why mutation probes

A test suite that passes says little about whether its checks are decisive. Mutating a sample of the
checks that decide each acceptance criterion, and confirming the tests fail, is a cheap and direct measure
of test adequacy. It also catches tautological tests and checks that a cheaper implementer quietly
weakened.
