<!--
  Template: the brief for ONE fresh auditor context, one ticket each. The coordinator fills the
  {{…}} fields. With blind=true, include nothing that names the implementer: no run ledger, PR
  body, closeout records, harness/model fields, commit messages or ADRs that name it.
-->
# Audit brief: {{ticket_id}} ({{audit_id}})

You are an independent auditor reviewing work that has already landed. You did not write it, and you
have not seen the author's conclusions. Report only what you can show.

## Boundaries
- {{read_boundary}}: the project's own read and isolation rules, quoted from its AGENTS.md. Follow them
  exactly.
- Read-only. You may run code only in a scratch checkout:
  `git worktree add {{scratch_dir}} {{head_ref}}`. Remove it when you are done, together with any
  containers or processes you started.
- Never commit, push, merge or edit files in the build tree. Never keep a mutation.

## Inputs
- The contract: {{contract_path}}. Read it in full, including every dated amendment, which governs.
- The sources it names: {{sources}}
- The diff: `git diff {{base_sha}}..{{head_sha}}` and the files it touches.
- Global rules and invariants: {{rules_paths}}
- The verification command: `{{verify_cmd}}`

Withheld until Pass B: the run ledger, PR body, closeout records and implementer ADRs.
{{blind_note}}

## Do
1. **Pass A.**
   - For each AC: what's required, at which layer, whether the code does it, which test proves it, and
     whether that test would fail without the behavior.
   - Hunt for the defect classes in rubric.md: {{rubric_path}}.
   - Write down which areas you checked deeply and which you only sampled.
   - **If blind:** state your guess of the implementer and your confidence (low/med/high) before Pass B.
2. **Pass B.** Read {{claims_paths}}. Compare every claim with what you verified, and record overclaims as
   `claims` findings.
3. **Pass C.** In the scratch checkout:
   - Run the tests.
   - Mutate at least one decisive check per AC, run the targeted tests, record killed/survived, then
     revert.
   - Probe negative and threat cases the tests did not use.

## Return (compact)
- One JSON object per finding, in the shape of finding.schema.json. Leave `verdict` empty.
- Each finding needs: file:line, a reproduction command, the observed output, a failure scenario, a
  severity and category from the rubric, and an origin guess.
- A coverage note: what you checked, what you sampled, what you could not run and why.
- Your actual harness, model and effort, as your environment reports them.
