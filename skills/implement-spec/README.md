# implement-spec — Spec to Provably-Complete PR, Autonomously

`implement-spec.md` is a workflow/skill that packs the full software development lifecycle — branch,
plan, implement, test, review, verify, ship — into a single autonomous agent run whose input is an
**authoritative written spec** and whose output is a **pull request plus an evidence report** proving,
acceptance criterion by acceptance criterion, that the implementation matches the spec.

It is deliberately *not* a "do the task and open a PR" prompt. It is a harness-in-prose: a structured
sequence of externally-verifiable feedback loops, durable on-disk state, and independence-preserving
review gates, designed around what the frontier AI-engineering literature says actually fails when
agents run long and unsupervised.

This document explains the design: what the literature says, how each phase responds to it, and why
the specific mechanisms chosen here are the right ones.

---

## 1. The problem: what breaks when you put the whole SDLC in one run

A spec-to-PR run is a long-horizon task — hours of wall-clock time, hundreds of tool calls, multiple
build/test cycles, potentially multiple context windows. Empirically, three failure classes dominate.
None of them are fixed by using a smarter model, because none of them are capability failures — they
are *structural* failures of the run itself:

1. **Completion over-claiming.** Agents report "done" based on plausibility rather than evidence.
   Anthropic's long-running-harness work documents this directly: models "tended to mark a feature as
   complete without proper testing … would fail to recognize that the feature didn't work end-to-end"
   even after unit tests and `curl` checks passed ([Effective harnesses for long-running agents][harness]).
2. **Context decay.** Fine-grained early details — exactly the kind a spec's requirement list is made
   of — degrade under compaction and disappear at context resets. Anthropic's context-engineering
   guidance identifies compaction, structured note-taking, and sub-agent architectures as the levers,
   and warns that "overly aggressive compaction can lose subtle but critical context whose importance
   only becomes apparent later" ([Effective context engineering for AI agents][context]).
3. **Self-evaluation bias.** The agent that wrote the code is a systematically unreliable reviewer of
   it. This is the most quantified of the three failures (see §2.1–2.2).

`implement-spec` is organized so that every phase either produces external evidence, persists state to
disk, or restores judgment independence. Everything else — the actual engineering — is left to the
model's own competence.

## 2. What the literature says

### 2.1 Self-correction only works with external feedback

The critical survey of LLM self-correction (Kamoi et al., *When Can LLMs Actually Correct Their Own
Mistakes?*, TACL 2024) reaches a precise conclusion: **the bottleneck is feedback generation, not
refinement**. Models refine well when handed reliable feedback; they generate unreliable feedback
about their own outputs when reasoning intrinsically. Self-correction works in exactly two regimes:

- when **external tools provide the feedback signal** — compilers, test suites, running systems
  (code generation is the survey's canonical example), and
- when **verification is much easier than generation** — e.g., checking a decomposable claim against
  a citation is easier than producing the claim.

Huang et al. (*Large Language Models Cannot Self-Correct Reasoning Yet*, ICLR 2024) showed the
degenerate case: prompted intrinsic self-correction without external signals often makes answers
*worse*.

**Design consequence:** every review loop in `implement-spec` is anchored to an external signal or a
citation obligation. Phase 3 loops against `verify.sh` (build/test/lint). Phase 4's gap table makes
"met" a *citation task*, not a claim: a requirement is met only if the agent can cite the file:line,
symbol, or test that proves it — deliberately moving the check into the verification-easier-than-
generation regime. Phase 5 anchors against the live running system. There is no phase whose output is
"the model thinks it's fine."

### 2.2 LLM evaluators favor their own generations

Panickssery et al. (*LLM Evaluators Recognize and Favor Their Own Generations*, NeurIPS 2024) showed
self-preference bias in LLM judges and — critically — that the bias scales with the evaluator's
ability to *recognize* its own output. Wataoka et al. (*Self-Preference Bias in LLM-as-a-Judge*,
2024) quantified the same effect. A reviewer whose context contains the entire history of writing the
code is the limiting case of self-recognition: it doesn't just recognize the output, it remembers the
intent, and reads the intent into the code.

Anthropic reached the same conclusion from the engineering side. Their three-agent harness for
long-running app development split the work into planner / generator / **evaluator** precisely
because generator self-evaluation kept passing applications that "looked impressive but still had
real bugs when you actually tried to use them." The evaluator ran with fresh context and drove the
app through Playwright like a user ([Harness design for long-running application development][harness-design]).

**Design consequence:** `implement-spec` requires independence at both review points. Phase 3 Pass 2
(design critique) and the Phase 4 gap walk should run in a **fresh subagent context given only the
spec, the diff, and the ledger** — not the implementation history — wherever the harness supports
subagents. Where it doesn't, the fallback discipline is explicit: every judgment must be argued from
what is on disk, re-read in full, never from memory of writing it. This doesn't eliminate
self-preference (same model weights), but it removes the strongest known amplifier — in-context
self-recognition and intent anchoring.

### 2.3 Long-horizon coherence requires durable external state

Anthropic's long-running-agent research converged on a consistent architecture: the unlock for
multi-context-window coherence was **structured on-disk artifacts**, not better prompting — an
initializer that writes a feature list (as JSON, with every item initially failing), a progress file,
an `init.sh`, and git history as recoverable state; then incremental one-feature-at-a-time sessions
that read those artifacts to get their bearings ([Effective harnesses for long-running agents][harness]).
Two details are worth keeping:

- they chose **JSON over Markdown for the pass/fail artifact** because models were less likely to
  inappropriately rewrite it, and protected it with strongly-worded rules ("it is unacceptable to
  remove or edit tests");
- the "getting up to speed" ritual — read progress file, read feature list, check git log, smoke-test
  the app — is what made sessions resumable and prevented agents from building on a broken base.

**Design consequence:** `implement-spec` Phase 0.4 creates a **run ledger** on disk (in a canonical,
gitignored scratch location) holding the spec's requirement + acceptance-criteria checklist, the test
matrix, the gap table, the shared-store fixtures list, and the evidence log. Every phase transition
updates it. The ledger is simultaneously the compaction-proof checklist, the crash/reset resume
point, and the raw material of the final evidence report. Phase 1.2's baseline health check is the
"smoke-test before you build" ritual; Phase 2's checkpoint-commit allowance and the autonomy
contract's resume protocol ("fresh session resumes from ledger + `git log`, never restarts from
scratch") are the recoverability half.

### 2.4 Agents don't verify end-to-end unless forced to — and live verification can lie

The single most documented failure in Anthropic's harness work: agents make code changes, run unit
tests, even `curl` a dev server — and still ship features that don't work end-to-end. The fix that
"dramatically improved performance" was explicitly requiring human-like driving of the real system
(browser automation, real interactions) before marking anything complete ([harness][harness]).

`implement-spec` Phase 5.3 generalizes that finding beyond web apps: stand up the real local
environment, derive a live test matrix from the spec's acceptance criteria (including negative and
back-compat cases, not just happy paths), drive each scenario agentically, and verify against
multiple independent signals (responses, state reads, server logs, rendered UI).

One addition comes from operational experience rather than the published literature, and deserves the
emphasis it gets in the skill: **the freshness guard**. A compiled change that isn't actually inside
the running process invalidates every interactive result — the live system "passes" because you're
testing yesterday's binary. Phase 5.3 requires asserting live-build == HEAD (version endpoint,
process-start-time check) before trusting any interactive evidence. This is the most common way live
verification silently lies, and almost no published harness checks for it.

### 2.5 Tests derived from the spec beat tests derived from the code

Anthropic's harness seeds the entire run with a spec-derived feature list marked failing — the
external target exists *before* the implementation. The TDD-for-agents pattern in Claude Code
guidance points the same way. The underlying mechanism: tests written after the code tend to assert
**what the code does**, inheriting the implementation's misreadings of the spec — which quietly
corrupts the gap table too, because a spec-misreading test becomes false "evidence" for a met row.

**Design consequence:** Phase 1.4 translates every acceptance criterion into a concrete test matrix
*before implementation*; Phase 2 writes each logical group's tests alongside the group; Phase 5
*runs* and evidences rather than first-writes. The verification target is fixed by the spec before
the implementation can bias it.

### 2.6 Skill authoring: conciseness, degrees of freedom, feedback loops, few options

Anthropic's skill-authoring guidance ([Skill authoring best practices][skill-bp],
[Equipping agents for the real world with Agent Skills][skills-blog]) supplies the meta-principles
for how a document like this should be written:

- **"Concise is key" / "assume the model is smart":** only add context the model doesn't have.
  `implement-spec` spends its tokens on repo bindings, failure modes, and state/independence rules —
  not on explaining what a PR is or how to write good code in the repo's language (that lives in the
  repo's AGENTS.md hierarchy, loaded just-in-time in Phase 0.3, which is itself the
  progressive-disclosure pattern the guidance recommends).
- **Degrees of freedom must match fragility:** exact commands for fragile, must-be-exact operations;
  heuristics for judgment work. See §4.
- **Feedback loops ("run validator → fix → repeat") greatly improve output quality** — the skeleton
  of Phases 3–5 — and **bounded iterations** (max 3 per loop here) prevent the unproductive
  self-refinement spirals that the self-correction literature predicts for intrinsic-feedback loops.
- **Avoid offering too many options:** one default path, few conditionals. `implement-spec`'s
  "deliberate omissions" section (no merge-main, no CI polling, no Slack) is this principle applied
  to scope: those concerns compose on top; they are not on the critical path.

### 2.7 Spec-driven development: where this skill sits

GitHub's Spec Kit formalizes SDD as *constitution → specify → plan → tasks → implement*, with
`/speckit.analyze` (cross-artifact coverage analysis), `/speckit.checklist` ("unit tests for
English"), and `/speckit.converge` (assess the codebase against the spec and append remaining work)
as quality gates ([Spec Kit][speckit]). AWS Kiro's spec loop (`requirements.md` → `design.md` →
`tasks.md` → grind) adds EARS-notation requirements and requirement-to-task traceability, plus a
discipline this skill adopts in ledger form: don't hand-edit the task state mid-grind; keep one
source of truth ([Kiro docs][kiro]).

`implement-spec` is the **back half of SDD**: it assumes the spec already exists and is authoritative
(the front half — clarify, plan, checklist the spec itself — happens before this skill is invoked).
Its Phase 4 is Spec Kit's `analyze` + `converge` made *mandatory and evidence-bearing* rather than
opt-in.

The published criticisms of SDD tooling informed the design as much as the features did. Reviewers
consistently report **process weight** — "a sea of markdown documents, long agent run-times …
reviewing markdown or waiting for the agent to churn out more markdown" (Scott Logic, on Spec Kit) —
and **nondeterminism**: prose specs are interpreted, not executed, so nothing proves the code
conforms. `implement-spec` answers the first by generating exactly one process artifact (the ledger,
which triples as checklist, resume point, and report) and scaling rigor to the change ("skip only for
genuinely trivial specs"; Phase 5 levels apply only where the change has a surface). It answers the
second with the evidence obligation: conformance is never asserted, it is *cited* — and the citations
ship in the PR.

## 3. Configuration: opt-out toggles

Every rigor phase is independently disableable (`ledger`, `self_review`, `gap_analysis`, `tests`,
`live_verification`, `evidence_report` — all default on), because proportionality is itself a
best practice: Anthropic's authoring guidance warns against one-size-fits-all process weight, and the
SDD critiques (§2.7) show what happens when full ceremony is applied to small changes. Two invariants
survive every configuration: the **green gate** (existing builds/tests must pass before a
ready-for-review PR) and the **no-false-claims rule** (an unrun check is never reported as passed).
The toggles remove work, never honesty.

## 3b. Anatomy: phase → mechanism → grounding

| Phase | Mechanism | Grounding |
|---|---|---|
| 0.1–0.2 | Pin worktree/cwd; record base commit | Multi-agent machine hygiene; exact commands for fragile ops (§2.6) |
| 0.3 | Read spec in full; extract requirements + ACs; load AGENTS.md hierarchy just-in-time; open integration anchors, escalate on drift | Progressive disclosure (§2.6); specs drift against live codebases (§2.7) |
| 0.4 | **Run ledger** on disk: checklist, test matrix, gap table, fixtures list, evidence log | Durable-state finding (§2.3) |
| 1.1–1.2 | Scope, verification-target mapping, evaluator coverage guard, **baseline health check** | External-verifier anchoring (§2.1); "smoke-test before building" (§2.3) |
| 1.4 | **Test matrix derived from ACs before implementation** | Spec-derived targets (§2.5) |
| 2 | Implement in planned order, tests alongside each group, build kept green, optional checkpoint commits | Incremental progress + git as recoverable state (§2.3) |
| 3 | Two-pass self-review against `verify.sh` + checklists; **fresh-context Pass 2**; design deferrals allowed, mechanical failures never | External feedback (§2.1); self-preference mitigation (§2.2) |
| 4 | **Re-read the spec**, rebuild the requirement list fresh, evidence-mandatory gap table in the ledger, fresh-context gap walk, bounded closure loop | Verification-easier-than-generation (§2.1); don't diff against your own lossy extraction (§2.3); independence (§2.2) |
| 5 | Unit → integration → **interactive live verification** with freshness guard, negative cases, multi-signal checks, fixtures ledger | End-to-end verification failure mode (§2.4) |
| 6 | **Green gate** (red build never reaches ready-for-review), intentional staging, AC-evidence table in the PR body, ledger-derived report | Over-claiming (§2.4); durable deliverable (§2.3) |
| Autonomy contract | No mid-run check-ins; two surface conditions; resume-from-ledger protocol | Long-horizon autonomy (§2.3) |

## 4. Degrees-of-freedom calibration

Anthropic's authoring guidance frames specificity as a function of *fragility*, not model capability
("narrow bridge with cliffs" vs "open field"). `implement-spec` applies that split deliberately:

- **Low freedom (exact commands):** branch/worktree setup, `verify.sh` invocation, staging and
  commit mechanics, PR creation. These are fragile, consistency-critical, and encode repo policy
  (branch naming, harness-dir exclusions) that the model cannot infer.
- **High freedom (heuristics):** how to close a gap "the way a reviewer familiar with the spec would
  consider obviously correct," how to design live scenarios, how to weigh signals. Frontier models do
  this better unconstrained; proceduralizing it would make outcomes worse.

The result is that for an Opus-class model, the skill adds almost no "how to engineer" content — it
adds **state durability and judgment independence**, the two properties model intelligence cannot
self-supply because they are properties of the run, not of the model. That is the central calibration
insight from reviewing this workflow against the literature: when a skill for a frontier model feels
like it needs more instructions, what it usually needs is more *structure*.

## 5. Honest limitations

- **Residual self-preference.** Fresh-context review removes in-context self-recognition, but judge
  and author still share weights; Panickssery et al. show recognition (and thus bias) persists above
  chance across contexts. A genuinely independent human or different-model review remains stronger.
  The evidence report is designed to make that human review fast, not to replace it.
- **Prose specs are interpreted, not executed.** The Spec Kit criticism applies here too. The
  gap table bounds interpretation drift per-requirement and makes it visible, but two runs from one
  spec can still legitimately differ. The escalation rule (spec contradiction that changes the design
  = hard blocker, never silent improvisation) is the mitigation, not a solution.
- **Verification is only as good as the evaluator coverage.** `verify.sh`/`detect-targets.sh` map a
  subset of the monorepo; the coverage guard forces honesty about the boundary, but outside it the
  agent falls back to subproject-documented commands, which vary in rigor.
- **Single-agent vs specialized multi-agent is an open question.** Anthropic's stated future
  direction is specialized testing/QA/cleanup agents; this skill approximates that with fresh-context
  subagent review inside one workflow. If the harness ecosystem standardizes cheap multi-agent
  orchestration, Phases 3–5 are the natural seams to split along.
- **Not yet eval-hardened.** Anthropic's guidance treats skills as software: build evaluations,
  watch real runs, patch where the model deviates. The highest-signal observable for this skill is a
  thin Phase 4 gap table on a non-trivial spec — that is where instruction-following goes
  performative. Iterate there first.

## 6. Portability

The workflow is harness-agnostic prose (Claude Code, Cascade/Windsurf, Cursor, Codex-style agents).
The repo-specific bindings are the adapter layer to re-point when porting:

- **A changed-files → verification mapper** (a `detect-targets`/`verify` script or equivalent) — the
  mechanical feedback loop. Any "map my diff to build/test/lint commands" tool works; absent one, the
  skill falls back to deriving commands from the repo's docs and build system.
- **A stable, gitignored scratch location** for the run ledger (`$AGENT_SCRATCH_DIR` or the default
  `.agents/scratch/` under the main worktree). Keep it *outside* per-worktree state if multiple
  checkouts share a machine.
- The `AGENTS.md` / `agent_docs/` hierarchy — the just-in-time knowledge layer Phase 0.3 loads.
- The sibling `self-review` skill — the two-pass review procedure Phase 3 invokes.
- **The repo's local-dev launcher** — the Phase 5.3 environment; discovered from the repo's docs.

## References

- Anthropic — [Effective harnesses for long-running agents][harness] (2025)
- Anthropic — [Effective context engineering for AI agents][context] (2025)
- Anthropic — [Harness design for long-running application development][harness-design] (2025)
- Anthropic — [Skill authoring best practices][skill-bp] (Claude platform docs)
- Anthropic — [Equipping agents for the real world with Agent Skills][skills-blog] (2025)
- Kamoi, Zhang, Zhang, Han, Zhang — *When Can LLMs Actually Correct Their Own Mistakes? A Critical
  Survey of Self-Correction of LLMs*, TACL 2024 — [arXiv:2406.01297](https://arxiv.org/abs/2406.01297)
- Huang et al. — *Large Language Models Cannot Self-Correct Reasoning Yet*, ICLR 2024 —
  [arXiv:2310.01798](https://arxiv.org/abs/2310.01798)
- Panickssery, Bowman, Feng — *LLM Evaluators Recognize and Favor Their Own Generations*,
  NeurIPS 2024 — [arXiv:2404.13076](https://arxiv.org/abs/2404.13076)
- Wataoka, Takahashi, Ri — *Self-Preference Bias in LLM-as-a-Judge*, 2024 —
  [arXiv:2410.21819](https://arxiv.org/abs/2410.21819)
- GitHub — [Spec Kit][speckit]; GitHub Blog — [Spec-driven development with AI](https://github.blog/ai-and-ml/generative-ai/spec-driven-development-with-ai-get-started-with-a-new-open-source-toolkit/)
- AWS — [Kiro][kiro] (spec-driven development: requirements/design/tasks + steering files)
- Scott Logic — *Putting Spec Kit Through Its Paces* (2025) — the process-weight critique

[harness]: https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents
[context]: https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents
[harness-design]: https://www.anthropic.com/engineering/harness-design-long-running-apps
[skill-bp]: https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices
[skills-blog]: https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills
[speckit]: https://github.com/github/spec-kit
[kiro]: https://kiro.dev/docs/specs/
