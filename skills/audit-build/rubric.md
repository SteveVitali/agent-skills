# audit-build rubric

Findings are only comparable across audits, auditors and implementers when everyone uses the same
labels. Use these definitions exactly. If a finding fits two classes, pick the one whose remediation is
needed first, and name the second in `notes`.

## Severity

| Severity | Definition | Typical examples |
|---|---|---|
| `blocker` | Ships wrong behavior or broken safety that a later ticket will build on. It must be fixed before the chain continues. | Isolation or authorization bypass; data written by the wrong owner; a false completion claim on an AC that later tickets rely on; history rewritten. |
| `major` | An AC is not met at its claimed layer, or a correctness, security or invariant defect is reachable from a supported path. It must be fixed before the ticket can be trusted. | Missing negative or boundary case with a concrete failing input; a test that can't fail; an expected value edited to match the output; a second implementation of a sole-owner concern. |
| `minor` | A real defect with limited reach, or a gap in how the evidence supports an otherwise correct claim. Fix it soon; it doesn't block. | Diagnostic or format errors; an untested but correct branch (a surviving mutant); a stale consumer note; a record inconsistency with no behavioral effect. |
| `nit` | Clarity, naming or documentation. No behavioral or evidential effect. | Docstring wording; a misleading comment. |

Calibration rule: the severity follows the **worst credible consequence on a supported path** that the
reproduction shows. It does not follow how much effort the fix takes, and it is not raised for style.

## Defect classes (`category`)

| Class | Meaning |
|---|---|
| `correctness` | The code does the wrong thing for some valid input or state. |
| `boundary` | A negative, edge, limit, encoding or concurrency case is unhandled. |
| `security` | Authorization, isolation, injection, secrets, egress or supply-chain exposure. |
| `contract` | A deliverable or AC in the ticket is missing or met differently without a recorded decision. |
| `claims` | A record (run ledger, PR body, closeout, ADR) claims more than the evidence supports: a layer, a count, CI, "fixed". |
| `test-adequacy` | Tests would still pass with the behavior removed: surviving mutants, tautologies, over-mocking. |
| `evidence-integrity` | Expected values, fixtures or digests were changed to fit the output, or a check was weakened or skipped. |
| `ownership` | A second implementation of a concern the plan gives one owner, or work done in the wrong ticket. |
| `interface` | Drift between the code and its consumer notes, ADRs or a dependent ticket's contract. |
| `records` | Build-memory inconsistency: deferral flips, ledger state, append-only history. |
| `process` | Reviewer not independent, identity or effort misrecorded, required step skipped. |
| `spec` | The defect originates in the spec or the plan, not the implementation. |

## Origin (`origin`): where it should have been caught

`implementer` · `in-ticket-review` (the in-ticket review saw the area but missed the defect) · `contract`
(the ticket was ambiguous or wrong) · `spec` · `cross-ticket` (only visible across tickets) · `unknown`.
Origin is what makes an evaluation useful. A high `in-ticket-review` rate suggests a stronger in-ticket
reviewer; a high `contract` rate suggests fixing decomposition, not auditing more.

## Verdicts (from the verifier)

- `confirmed`: reproduced as stated.
- `plausible`: not reproduced, but the reasoning is specific and checkable. State what blocked
  reproduction.
- `refuted`: the reproduction shows the claim is wrong.

Report `confirmed` and `plausible` findings. Keep all three in the JSONL.
