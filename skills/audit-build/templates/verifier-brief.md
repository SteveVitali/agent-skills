<!--
  Template: the brief for a fresh verifier context. It gets the finding's claim and reproduction, but
  not the auditor's reasoning or other findings. One finding, or a small batch on the same ticket.
-->
# Verify: {{finding_ids}} ({{audit_id}})

Your job is to decide whether each claim is real. Do not improve or extend it.

## Boundaries
- {{read_boundary}}: follow the project's AGENTS.md read and isolation rules.
- Read-only. Run code only in a scratch checkout of {{head_ref}} and remove it afterwards. Never keep a
  change.

## Each finding
{{finding_claims}}: for each, the claim, its file:line, the reproduction command and the stated failure
scenario.

## Do
For each finding:
1. Run the reproduction, or an equivalent, in the scratch checkout.
2. Give a verdict:
   - `confirmed`: reproduced as stated.
   - `plausible`: not reproduced, but specific and checkable; say what blocked it.
   - `refuted`: show why.
3. Check the severity against the rubric ({{rubric_path}}). You may adjust it, with a one-line reason.

## Return
Per finding: `id`, `verdict`, `verifier_evidence` (command and observed output),
`severity_adjusted` (or null) with its reason. Also state your actual harness, model and effort as your
environment reports them.
