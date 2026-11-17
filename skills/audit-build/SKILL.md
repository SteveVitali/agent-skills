---
name: audit-build
license: MIT
description: "Independent, fresh-context critical re-review of tickets that have already landed in a multi-session build. It covers the last N tickets, every ticket since the previous audit, named tickets, or a git range. Each ticket's acceptance criteria are re-checked against the code, tests and evidence, and claims are compared with what is verified. Faked or weakened checks, cross-ticket duplication and sole-owner violations are hunted down. Every finding is verified before it is reported, and fixes are routed through the build's own repair mechanisms. It also has an evaluation mode: a pre-registered, blinded measurement study of an implementer's work, which estimates how much auditing is actually needed, where and why. Use it to keep cheaper implementation models in check with periodic review by a stronger model, and to decide on evidence how often that review should run. Read-only on the build; never fixes, merges or edits landed records."
inputs:
  - name: mode
    required: false
    description: "'audit' (default): critical re-review of a scope, with findings and remediation routes. 'evaluate': a pre-registered measurement study (modes/evaluate.md) whose output is defect-rate estimates with uncertainty and an evidence-based audit policy."
  - name: scope
    required: false
    description: "Which landed tickets: 'since-last' (default: everything after the last audit record's `audited-through`), 'last=<N>', 'tickets=<ID,ID,…>', or 'range=<BASE>..<HEAD>'. Resolved by scripts/audit-scope.sh."
  - name: ledger
    required: false
    description: "Path to docs/build/LEDGER.md (default: resolved via build-memory memory-root.sh)."
  - name: blind
    required: false
    description: "Default true in evaluate mode and false in audit mode. When true, the auditor brief omits the implementer's identity and conclusions (run ledger, PR body, harness/model fields) until the claims pass."
  - name: verify_cmd
    required: false
    description: "The repo's test/lint command (default: discovered from AGENTS.md / Makefile / package manifests, as self-review does)."
  - name: max_parallel
    required: false
    description: "Upper bound on concurrent read-only auditor contexts (default 3). Only reads are parallelized; all writes stay single-threaded."
---

# Audit Build

Re-review work that has **already landed**, using a fresh context and the strongest model you have. The goal is
that an implementer can be cheaper than its reviewer without the build drifting. `implement-spec` already runs
an in-ticket independent review. This skill is the second, later line of defense: one auditor that sees several
tickets together, sees how they fit together, and is never anchored on what the author concluded.

> **Measure before you police.** How often to audit, and how deep, is an empirical question about a particular
> implementer on a particular kind of ticket. Run `mode=evaluate` first (modes/evaluate.md) to estimate defect
> rates per stratum with honest uncertainty. Set any audit cadence from those numbers, not from intuition, and
> re-estimate when the implementer, model, harness or ticket mix changes. This skill ships **no default
> cadence** and no hooks into `orchestrate-build`. It runs when an operator or coordinator invokes it.

It reads the committed build memory defined in `skills/build-memory/layout.md`: BUILD_INDEX, run ledgers,
PR bodies, DEFERRALS, ADRs, the ledger's OPEN FINDINGS and the manifest. It cites that file and does not
restate it. Its own records go under `docs/build/reports/audits/`.

## Non-negotiables

1. **Read-only on the build.** Never edit code, tests, landed records or another ticket's files. Never
   commit to a chain branch, merge, approve or retarget. Code runs only in a **scratch checkout**
   (`git worktree add <tmp> <ref>`), and the scratch checkout is removed afterwards. The only build files you
   write are this skill's own outputs (§ Outputs).
2. **Respect the project's read boundary.** Follow the repo's AGENTS.md and any recorded isolation or
   held-data rules before running scanners, tests or history checks. An audit never widens a boundary.
3. **Independence.** Auditors get the contract, its named sources and the code, never the author's
   conclusions, until the claims pass (§ The passes). When `blind=true`, implementer identity is withheld as
   well. Whether blinding actually held is recorded.
4. **Verify every finding.** A finding is reported only after a separate verifier context has reproduced
   it (verdict `confirmed`) or judged it plausible with a stated reason. Refuted findings are kept in the JSON
   record, which is how auditor precision gets measured, and left out of the report's action list.
5. **No silent fixes.** Every confirmed finding gets a remediation route the build already has: a bounded
   repair on the ticket's still-open PR, a return pass, or an insert through `decompose-spec mode=extend`.
   The audit recommends; the coordinator dispatches. A `blocker` recommends `pauseRequested: true`.
6. **Evidence over adjectives.** Each finding carries a file:line, the exact command that reproduces it, its
   observed output and a concrete failure scenario. "Looks fragile" is not a finding.
7. **Honest identity.** Record the auditor's and verifier's actual harness, model and effort as the harness
   reports them. If an agent's self-reported settings disagree with what was requested, record both.
   Self-report is not proof.

## Orient

- Resolve the memory root (build-memory `memory-root.sh`). Run `check-build-memory.sh .` and record the
  result, but don't stop on a red validator: inconsistency is itself an audit finding.
- Resolve the scope: `scripts/audit-scope.sh --root . <scope>` prints one TSV row per in-scope ticket (seq,
  ticket, branch, PR, base, landed, harness), plus the previous audit's id and its `audited-through` ticket.
  An empty scope ends the run with a one-line report.
- Read the global rules and invariants (manifest, AGENTS.md), the **full** DEFERRALS file and OPEN FINDINGS.
  Also read every OPEN finding from earlier audits, because re-checking those is part of this run.
- Read the CI state for each in-scope PR (`orchestrate-build/scripts/ci-boundary.sh --pr <n> --stack
  --no-wait`, or the forge's API). Treat a missing check as missing, never as a pass.

## The passes (per ticket; read-only contexts may run in parallel up to `max_parallel`)

Brief each auditor with `templates/auditor-brief.md`. One ticket per fresh context. If the harness has no
subagents, run each brief as a separate fresh session, and never do it in the coordinating context.

**Pass A, blind conformance.** Inputs: the ticket contract (including every dated amendment), its named
sources, the diff (`git diff <base>..<head>`) and the code it touches. For every acceptance criterion:
- What the contract requires, and at which evidence layer.
- Whether the code does it.
- Which test proves it, and whether that test would fail if the behavior were removed.

Look for the failure modes in `rubric.md` § Defect classes:
- **Logic and boundaries:** wrong logic, missed boundary or negative cases, concurrency and transaction
  hazards, security and isolation gaps.
- **Weakened evidence:** expected values edited to match output, tautological tests, checks weakened or
  skipped.
- **Ownership violations:** a second implementation of something one owner is supposed to own.

**Pass B, claims audit.** Only now read the run ledger, the PR body, the closeout records and the
implementer's ADRs. Compare every claim (AC status, layer reached, test counts, CI line, deferrals
opened/closed, reviewer findings "fixed") with what Pass A verified. An overclaim is a finding in its own
right (`claims` class), even when the code is fine.

**Pass C, adversarial probes** (in the scratch checkout):
- Run the ticket's tests and the repo's `verify_cmd`.
- Mutate a sample of decisive checks (at least one per AC with a decisive check; more for blocker/major-risk
  areas): change one condition, run the targeted tests, record killed/survived, revert.
- Probe the stated threat or negative cases with inputs the tests didn't use.
- Never commit a mutation.

**Pass D, cross-ticket (once per audit, after all tickets).**
- **Duplication:** does a second implementation of a single-owner concern exist?
- **Interface drift:** do consumer notes and ADRs match the code?
- **Invariants:** do security, isolation and grant invariants still hold at the audit head?
- **Regressions:** did an earlier ticket's tests or guarantees break?
- **Records:** are deferral flips, ledger state and append-only history consistent?
- **Process:** were reviewers independent, are harness and effort records honest, were context
  measurements recorded?
- **Blast radius:** for each confirmed major or blocker, list the landed tickets that consume the defective
  interface, and check them too.

**Verification.** Brief a separate verifier context per finding (or per batch) with
`templates/verifier-brief.md`. It gets the finding's claim and reproduction, not the auditor's reasoning. It
reproduces the finding, gives a verdict (`confirmed` / `plausible` / `refuted`), and may adjust the severity
with a reason.

## Outputs

All outputs are appended. Earlier audit records are never edited.
- `docs/build/reports/audits/<date -u +%F>_<audit-id>.md`, from `templates/AUDIT_REPORT.md`. Its front
  matter carries `audit-id`, `mode`, `scope`, `audited-through` (the last in-scope ticket id), `head` (the
  sha audited), and the auditor and verifier identities. The body holds the verdict per ticket, verified
  findings ordered by severity, remediation routes, blast radius, measurements and limitations.
- The dataset that `scripts/audit-stats.py` aggregates across audits, in three files next to the report.
  Each has the report's `<date -u +%F>_<audit-id>` prefix, and every finding's `audit_id` field equals that
  id:
  - `<audit-id>.findings.jsonl`: one JSON object per finding, including refuted ones, conforming to
    `templates/finding.schema.json`;
  - `<audit-id>.tickets.tsv`: one row per audited ticket and round, **clean tickets included**, because
    they are the denominator. Columns: `ticket implementer stratum audit_round auditor blind_guess tokens`;
  - `<audit-id>.mutations.tsv`: one row per mutation probe. Columns: `ticket site killed` (`1`/`0`).
- The ledger:
  - one OPEN FINDINGS line per confirmed finding of severity minor or worse, citing the report;
  - one PHASE LOG `audit` entry at the end of the file:
    `- <date -u +%F> — <audited-through> audit — scope · tickets n · findings b/M/m/n (confirmed) · routes · report <path> · harness: <auditor>`.
  - Nothing else in the ledger changes, unless the coordinator acts on a recommended `pauseRequested`.
- A short summary for the operator: the verdict per ticket, every blocker and major with its route, and
  what the audit could not check.

## Severity and routing

Use `rubric.md` § Severity, so that one audit's "major" means the same as another's. The routes:

| Ticket state | Route |
|---|---|
| PR still open | A bounded repair on the same branch, verified by the coordinator, plus a PHASE LOG `repair — close:` entry |
| Landed, and the defect is local | A return pass, or a repair PR from a fresh context that names the finding id |
| Landed, and the defect spans tickets or needs a contract change | An insert through `decompose-spec mode=extend`, with a fresh contract review |
| The defect is in the spec or the plan | Report it to the operator; it may need a spec amendment |

## Modes

| Mode | File | Produces |
|---|---|---|
| `audit` | [modes/audit.md](modes/audit.md) | the report and findings above, for a scope |
| `evaluate` | [modes/evaluate.md](modes/evaluate.md) | a pre-registered evaluation plan, blinded audits of a stratified sample, a duplicate-audit subset for auditor agreement, defect-rate estimates with intervals per stratum, and a recommended audit policy with its re-evaluation trigger |

## Scripts (bash 3.2+ or python3 stdlib; read-only)

| Script | Role |
|---|---|
| `scripts/audit-scope.sh` | Resolves the ticket set from BUILD_INDEX and the previous audit record; prints TSV |
| `scripts/audit-stats.py` | Aggregates an audits directory (findings, tickets and mutations files): confirmed findings per ticket by stratum, Wilson 95% intervals for "ticket has a confirmed major+ defect", auditor precision, mutation kill rate, and Cohen's kappa on duplicate audits |

## What this skill does NOT do

- **No fixing.** It routes; fixes run through the build's own repair or insert paths, in fresh contexts.
- **No cadence of its own.** It doesn't change `orchestrate-build`. Any schedule is the operator's, ideally
  derived from `mode=evaluate`.
- **No claims of absence.** "No findings" means none were found in the scope at the recorded depth. The
  report states what was sampled and what was not.
- **No merging, approving, CI fixing, or production or external actions.**
