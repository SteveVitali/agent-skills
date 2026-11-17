# mode=evaluate: measure before you police

The question this mode answers: **how much auditing does this implementer's work need, where, and
why?** It is a small, pre-registered measurement study. Its outputs are estimates with honest
uncertainty and a policy derived from them. A single impression ("the cheap model seemed fine") is not an
output.

## 1. Pre-register (before any audit runs)

Write `docs/build/reports/audits/<date -u +%F>_<eval-id>.plan.md` from `templates/EVALUATION_PLAN.md`
and commit it before any auditing starts. It fixes:

- **Questions.** The defaults are below; keep, drop or add, but do it now, not after seeing results.
  - **Q1 Defect rate.** For each implementer and stratum, the proportion of tickets with at least one
    confirmed defect of severity major or worse.
  - **Q2 Profile.** How confirmed findings are distributed by `category` and `origin` (rubric.md).
  - **Q3 Escape rate.** The share of confirmed major+ findings in areas the in-ticket review covered,
    and therefore missed (`origin: in-ticket-review`).
  - **Q4 Claim accuracy.** Confirmed `claims` findings per ticket.
  - **Q5 Test adequacy.** Mutation kill rate on sampled decisive checks.
  - **Q6 Comparison.** Q1–Q5 against a baseline implementer on matched strata.
  - **Q7 Cost.** Auditor tokens and time per confirmed major+ finding.
- **Units and strata.** The unit is a landed ticket. Strata come from properties fixed before looking:
  - **Implementer:** harness/model.
  - **Ticket kind:**
    - *primitive*: creates a kernel, sole writer, registry or security boundary that others consume;
    - *consumer*: mounts or extends an existing primitive;
    - *fixture/oracle*: exact-bytes fixtures or case tables;
    - *integration*: composed journeys;
    - *ui*.
  - **Size:** the plan estimate.

  Write each ticket's stratum down before auditing it.
- **Sample.** Use every eligible ticket if there are 12 or fewer. Otherwise take a stratified random sample
  with a recorded seed and draw. Name exclusions and give reasons.
- **Baseline (control).** Audit tickets by a reference implementer from the same strata with the same
  protocol, auditor model and briefs, interleaved in a randomized order. Without a control you can't tell
  "the implementer is weak" apart from "auditors always find something".
- **Blinding.**
  - Pass A briefs exclude run ledgers, PR bodies, closeout and harness fields, commit messages and
    trailers, and ADRs that name the implementer. Diffs come from `git diff`; commit messages are not
    included.
  - After Pass A, each auditor writes down its guess of the implementer and its confidence. That records
    whether the blinding held.
- **Duplicate subset.** Audit at least 20% of sampled tickets (at least 3) twice, in independent auditor
  contexts.
- **Positive control (optional, recommended).** In a scratch copy of 1–3 tickets, a separate context
  plants known defects (recorded in a sealed list) and audits them blind. That measures auditor recall
  directly. Never commit a seeded copy.
- **Decision rule.** State it now (§ 4), including the operator's cost ratio or risk threshold.

## 2. Run

- Run each sampled ticket through mode=audit's passes A–C and verification, with `blind=true`. Pass D runs
  once over the union of sampled tickets.
- Write every finding to the JSONL and every audited ticket to the tickets TSV. Both carry the ticket's
  stratum and its `audit_round` (1, or 2 for the duplicate subset). The tickets TSV also carries the blind
  guess. Mutation probes go to the mutations TSV.
- Record deviations from the plan as they happen, in the plan file's `## Deviations` section (append-only).

## 3. Analyze (`scripts/audit-stats.py`)

`audit-stats.py <audits-dir> [--audit <id>…]` reports the following for each implementer and
stratum:

- **Q1** as `k/n` with a Wilson 95% interval. Say it plainly when n is small; for example, 0/5 has an upper
  bound near 43%.
- Confirmed findings per ticket by severity, plus the `category` × `origin` table (**Q2–Q4**).
- **Auditor precision:** confirmed ÷ (confirmed + refuted).
- **Mutation kill rate** (**Q5**), from the `mutation` field.
- On the duplicate subset:
  - **Cohen's kappa** on the per-ticket binary "has a confirmed major+";
  - finding-level overlap, as matched findings ÷ union;
  - a **Lincoln–Petersen** estimate of the total number of major+ defects (n₁·n₂/m) as a rough recall
    signal, reported only when m ≥ 1.
- If seeded, **recall** on the planted defects.

Interpret effect sizes and intervals, not single counts. Two strata whose intervals overlap heavily have
not been shown to differ.

## 4. Derive the policy

Default rule (keep it unless the plan replaced it). For each stratum s, let p̂ₛ be the Q1 estimate and uₛ its
upper 95% bound.

- **Audit every ticket** in s when uₛ · C_escape > C_audit.
  - C_escape is the operator-chosen cost of an undetected major+ defect, including its downstream blast
    radius.
  - C_audit is the measured audit cost per ticket (Q7).
- **Otherwise sample.** Audit a random fraction rₛ = min(1, p̂ₛ · C_escape / C_audit) of tickets in s, with
  at least one per phase.
- **Always audit:** primitives landed by a non-baseline implementer, and any ticket an in-ticket reviewer
  flagged as low-confidence.
- **Re-evaluate** when the implementer, model, harness or effort changes; when the ticket mix moves into a
  stratum with n < 5; or after the number of tickets the plan named.

The policy report (`<eval-id>.md`, from `templates/AUDIT_REPORT.md` with the evaluation sections filled in)
states the rule, the per-stratum numbers that drove it, and the re-evaluation trigger. It is a
recommendation for the operator to adopt or override.

## 5. Threats to validity (always report them)

- **Small n.** Per-stratum samples are usually tiny, so the intervals are wide.
- **Auditor bias.** A same-family auditor may share the implementer's blind spots, and a stronger one may
  over-report style issues. The severity rubric and the verifier mitigate this but don't remove it.
- **Non-determinism.** The duplicate subset measures it; it doesn't eliminate it.
- **Heterogeneity.** Ticket difficulty varies inside a stratum.
- **Drift.** Results describe the implementer and harness as configured during the study.
- **Contamination.** Auditors must not see earlier audit reports of the same tickets.
- **Awareness.** Implementers who know they are audited may behave differently.
