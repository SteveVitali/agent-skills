# decompose-spec — Optimal Partitioning of a Large Spec

`decompose-spec` (`SKILL.md`) turns one large spec into the **fewest self-contained tickets that each fit a
single fresh context**, then seeds the durable build ledger `orchestrate-build` drives. It is the **planning
half** of a multi-session build; the per-ticket worker is `implement-spec`.

It exists because, in a multi-session build, **the decomposition is the ceiling on everything downstream**. A
bad split produces tickets with hidden cross-dependencies that violate the fresh-context and single-writer
assumptions the whole system rests on — and no amount of per-ticket rigor recovers from it. This is the direct
analogue of "the build is only as good as its spec," one level up: *the build is only as good as its
decomposition.* So this skill spends its effort on getting the cut right, and on making the cut **revisable** at
run time, because a static partition of a genuinely large spec is wrong somewhere.

---

## 1. The problem is a constrained optimization

Partitioning is not "chunk the spec into roughly equal pieces." It is:

> **minimize the ticket count `N`** subject to, per ticket: (1) fits one fresh-context `implement-spec` run with
> rigor headroom, (2) is one coherent, independently-landable concern, (3) respects the dependency order, (4)
> falls on the weakest-coupling seam.

The interesting part is that `N` is pulled in *opposite* directions by two well-documented failure modes, and
"optimal" is the point where their marginal costs balance.

## 2. The upper bound: context rot (don't under-factor)

Making tickets bigger reduces `N` but pushes each ticket toward context degradation — which begins **far below**
the advertised window and is driven by more than raw token count:

- **Chroma, *Context Rot* (2025)** — 18 models, 194,480 calls: performance degrades non-uniformly as input grows
  *even on trivial tasks*, and *even with the relevant content held constant* (their LongMemEval "focused ~300
  tokens" vs "full ~113K tokens" comparison). **A single distractor** measurably lowers accuracy, independent of
  length; distractors compound.
- **NoLiMa (ICML 2025)**: at 32K tokens, 11 of 13 models fall below half their sub-1K baseline.
- **RULER (COLM 2024)**: "effective length" is routinely a fraction of the claimed window.
- **Lost in the Middle (TACL 2024)**: a U-shaped curve — 20–30 point accuracy drops for mid-context material.
- **Anthropic** frames the mechanism as an **"attention budget"** stretched thin by n² attention, and adopts the
  term "context rot" directly.

**Design consequence:** rule 1 targets each ticket's *working set* — spec slice + code read + tests + the
self-review/gap/verify passes `implement-spec` runs *inside* the ticket — at **well under half** the window, not
merely "under the limit." And because a **subagent cannot compact across windows** (it fails on overflow), the
`dispatch_target` turns this into a *hard* ceiling on the subagent path and a *soft* one (compaction, at a
fidelity cost) on the headless/manual paths — so the skill sizes to the declared target.

## 3. The lower bound: fragmented decisions + fixed cost (don't over-factor)

Making tickets smaller also has a cost, and the coding-specific literature is emphatic that it is a real one:

- **Cognition, *Don't Build Multi-Agents* (2025):** "actions carry implicit decisions, and conflicting decisions
  carry bad results." Splitting one concern across units disperses implicit decisions (a name, a shared helper, a
  pattern) that then collide — the dominant failure mode of naive multi-agent coding. Prescription: keep a unit
  of work whole; don't fragment shared decisions.
- **Anthropic, *multi-agent research system* (2025):** explicitly flags coding as a *poor* fit for splitting —
  "fewer truly parallelizable tasks… agents are not yet great at coordinating in real time"; shared-context,
  dependency-heavy work is "not a good fit for multi-agent systems today."
- **Fixed per-ticket cost:** every ticket re-pays context bootstrapping (re-reading conventions, anchors, shared
  models) and every cut adds an integration seam plus a PR to review. Over-factoring multiplies both.

**Design consequence:** the **shared-decision rule** — *stop splitting the moment a cut would sever a shared
implicit decision* — is the lower bound, enforced by Phase 4's "fragmented decisions" check.

## 4. Where the soft proxies come from

The "one logical concern" target is grounded, but only as a *proxy for cognitive size*, never as a hard rule:
GitHub **Spec Kit** (`/specify → /plan → /tasks → /implement`, a numbered `tasks.md` with acceptance criteria and
dependencies) and AWS **Kiro** (requirements → design → tasks, ~1–4h each, traceable to a requirement) both
size tasks at one independently-verifiable concern; community coding-agent guidance converges on ~50–100 LOC /
≤~5 files. The skill states these as guides and explicitly notes a large mechanical change can be far bigger and
still trivial — LOC measures the wrong thing when the change is uniform.

## 5. Why Phase 4 is adversarial and fresh-context

The context that just authored the partition is a biased reviewer of it — **Panickssery et al. (NeurIPS 2024)**
and **Wataoka et al. (2024)** quantify LLM evaluators' self-preference, scaling with the evaluator's ability to
recognize its own output; a context that remembers *authoring* the split reads its own intent into it. So Phase
4 runs the critique in a **fresh context** (subagent where supported, else re-read-from-disk discipline), hunting
the specific failure modes a partition has — fragmented decisions, overflow risk, orphan seams, coverage/scope,
ordering, over-factoring. This is the same independence discipline `implement-spec` uses for its own review, applied
to the plan.

## 6. Anatomy: phase → mechanism → grounding

| Phase | Mechanism | Grounding |
|---|---|---|
| 0 | Read the spec + repo ground truth; extract requirements / ACs / invariants / out-of-scope | Progressive disclosure; specs drift vs live code |
| 1 | Dependency DAG + coupling-seam map | Cut on structure, not on guesses |
| 2 | Partition to the objective; classify chained vs out-of-chain, deterministic vs agentic | The constrained optimization (§1–§3) |
| 3 | Author execute-grade contracts where missing | `implement-spec` needs a CONTRACT to diff against |
| 4 | **Fresh-context adversarial split review** | Self-preference bias (§5) |
| 5 | Seed the ledger — grep-friendly `CURRENT STATE`, PHASE PLAN, invariants, SETUP/CAPSTONE templates | Durable external state (see orchestrate-build README) |
| 3+5 | Per-ticket contract files + `00_MANIFEST.md` runbook (default: scratch; `tickets_dir` relocates); cite-don't-copy; requirement-ID stamping; non-code rows | Two production builds hand-rolled it (§7) |

## 7. Per-ticket files + a manifest runbook (default projection; `tickets_dir` relocates)

Two production builds (a 46-ticket chain and a second large build) independently hand-rolled the same artifact
layout when driving tickets through hand-chained fresh sessions rather than the automated loop: one contract
file per ticket plus a `00_MANIFEST.md` runbook, gitignored beside the canonical spec. Twice-reinvented
prompting is the definition of a missing affordance, so the skill now emits the projection **by default** — in
the gitignored scratch dir beside the ledger, zero repo-tree footprint — with `tickets_dir` relocating it into
the tree (gitignored) when the operator wants it browsable next to the canonical spec. The per-ticket file's
benefit is universal across dispatch tiers, not specific to hand-chaining, which is why it is not opt-in. The
layout earns its place on four grounds:

- **The per-ticket file is the §2 logic applied to the contract itself.** A fresh worker's working set should
  start at one small file — not a scan of a monolithic ledger for its slice.
- **Cite-don't-copy prevents spec forking.** A contract that restates the design diverges from the spec at the
  first amendment; citing sections + requirement IDs keeps the spec the single source of truth, with a manifest
  log recording each amendment applied.
- **Requirement-ID stamping makes coverage checkable** — at plan time (every in-scope ID → exactly one ticket)
  and at review time (the PR lists the IDs it satisfies).
- **Real chains contain non-code work.** Human prerequisites (accounts, outreach) and pre-registered milestone
  gates (a hard barrier, a go/no-go criterion) belong *in* the ordered plan — as marked non-ticket rows — or the
  chain silently blocks on them.

The ledger is still seeded and remains the machine truth for `orchestrate-build`; the manifest is the human
truth for the manual floor. Same plan, two projections.

## 8. Honest limitations

- **The estimate is a heuristic.** "Fits one fresh context" is judged, not measured; the mitigation is
  `orchestrate-build`'s run-time **split-on-overflow** (a ticket that overflows is re-decomposed) and
  **merge-trivial** adaptivity, plus sizing to the conservative (subagent) ceiling by default.
- **Optimality is not provable.** Minimum-`N` under these constraints is a graph-partition problem the skill
  approximates with judgment + one adversarial pass, not a solver. Two runs may legitimately differ.
- **Garbage in.** A spec with no derivable design cannot be decomposed — the skill hard-stops rather than
  inventing one.

## References

- Hong, Troynikov, Huber — *Context Rot: How Increasing Input Tokens Impacts LLM Performance*, Chroma (2025) — https://www.trychroma.com/research/context-rot
- Modarressi et al. — *NoLiMa: Long-Context Evaluation Beyond Literal Matching*, ICML 2025 — https://arxiv.org/abs/2502.05167
- Hsieh et al. — *RULER: What's the Real Context Size of Your Long-Context Language Models?*, COLM 2024 — https://arxiv.org/abs/2404.06654
- Liu et al. — *Lost in the Middle: How Language Models Use Long Contexts*, TACL vol. 12 (2024) — https://arxiv.org/abs/2307.03172
- Anthropic — *Effective context engineering for AI agents* (2025) — https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents
- Anthropic — *How we built our multi-agent research system* (2025) — https://www.anthropic.com/engineering/multi-agent-research-system
- Cognition (Walden Yan) — *Don't Build Multi-Agents* (2025) — https://cognition.com/blog/dont-build-multi-agents
- Panickssery, Bowman, Feng — *LLM Evaluators Recognize and Favor Their Own Generations*, NeurIPS 2024 — https://arxiv.org/abs/2404.13076
- Wataoka, Takahashi, Ri — *Self-Preference Bias in LLM-as-a-Judge*, NeurIPS 2024 Safe GenAI Workshop — https://arxiv.org/abs/2410.21819
- GitHub — *Spec Kit* — https://github.com/github/spec-kit · AWS — *Kiro* — https://kiro.dev/docs/specs/
