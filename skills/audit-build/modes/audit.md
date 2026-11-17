# mode=audit

A critical re-review of a scope of landed tickets. Use it at a phase boundary, after a run of tickets by a
cheaper implementer, before an expensive ticket starts building on recent work, or when an operator asks.
How often to run it should come from `mode=evaluate`. This mode does not set a schedule.

## Steps

1. **Orient and scope** (SKILL.md § Orient). Write down the audit id
   (`A<date -u +%Y%m%d>-<short head sha>`), the resolved scope, `head` and the auditor's identity before
   reading any code.
2. **Plan the depth.** For each ticket, list its ACs, the decisive checks you will mutate, and the threat or
   negative cases you will probe. Record which ACs are only sampled, so the report can state its limits.
   Spend more depth on tickets that create a primitive others consume (a kernel, a sole writer, a security
   boundary) than on those that only consume one.
3. **Passes A–C per ticket** (SKILL.md § The passes). Use one fresh context per ticket, briefed from
   `templates/auditor-brief.md`. Each auditor returns findings in the schema's shape (verdict left empty)
   and a short coverage note: what it checked and what it couldn't.
4. **Pass D across the scope.** Do it once, after all ticket audits return. Also re-check every OPEN finding
   from earlier audits: is it now fixed, still open, or worse?
5. **Verify.** Use separate verifier contexts (`templates/verifier-brief.md`). Do not let an auditor verify
   its own finding.
6. **Write outputs** (SKILL.md § Outputs). The report's per-ticket verdict is one of:
   - `clean`: no confirmed or plausible finding at minor or above;
   - `fixes-needed`: at least one minor or major;
   - `blocked`: at least one blocker.

   Always include the limitations section: what was sampled, what couldn't run (and why), and how
   independent and blind the audit was in practice.
7. **Hand off.**
   - Give the coordinator the routes.
   - If any blocker exists, recommend `pauseRequested: true` with the finding ids.
   - Write nothing else.

## Budget

An audit of N tickets costs roughly N auditor contexts plus verifier contexts plus one Pass D. Record
measured tokens and time per context in the report's measurements table. Those numbers are the "cost" side
of the audit policy that `mode=evaluate` derives.

## Re-audits

When an audit's fixes have landed, audit the scope again with `tickets=<the fixed ids>`. The new record
cites the earlier one, and each earlier finding gets a status: `fixed` (re-verified), `still-open` or
`regressed`. Earlier records are never edited.
