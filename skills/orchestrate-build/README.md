# orchestrate-build — Driving a Multi-Session Build Without Context Rot

`orchestrate-build` (`SKILL.md`) drives a decomposed spec to completion: SETUP a dedicated worktree, run each
ticket end-to-end through `implement-spec` **in a fresh context**, update a durable ledger, report progress,
pause for intervention at ticket boundaries, and finish with a whole-build capstone. It is the **execution
half** of a multi-session build — `decompose-spec` produces the plan; `implement-spec` is the per-ticket worker.

The design generalizes a hand-built, human-driven "open a fresh session and re-run the continue command each
ticket" workflow into something that **manages its own fresh-session lifecycle** — without reintroducing the
context rot that the manual fresh-session-per-ticket discipline existed to prevent.

---

## 1. The paradox, and the insight that dissolves it

The manual predecessor put a human in the loop to open each fresh session — and that human *was* the anti-rot
mechanism: their durable memory was a ledger file, so no agent context accumulated across the build. Automating
the human away appears to reintroduce rot: a single long-lived orchestrator agent driving every ticket
accumulates context across the whole build and degrades (see the `decompose-spec` README for the context-rot
evidence; Anthropic's own guidance is explicit that **compaction alone is insufficient** for multi-session work).

The resolution is a fact about contexts, not a trick:

> **A fresh context can only be created from *outside* the context being refreshed.** No prose makes a running
> context clean itself. So "run the next ticket fresh" must be initiated by an external actor — and the cleanest
> such actor is not another agent but **deterministic code**: a loop that holds no state and therefore cannot rot.

This yields a three-role separation: **state on disk** (the ledger), **cognition in fresh disposable contexts**
(each ticket, the capstone), **sequencing in a dumb loop** (`scripts/drive-build.sh`, or a harness's subagent
dispatch, or a human). On the **program-as-orchestrator** path (the deterministic `drive-build.sh` loop, the
recommended default) the orchestrator-context problem is *designed out*, not managed: the loop holds no LLM
context, so there is nothing to rot. On the **agent-as-orchestrator** fallback (a single session dispatching
subagents where no headless CLI exists) it is instead *minimized and bounded* — the session externalizes all
state to the ledger and is re-spawnable from it, so its context grows only by compact per-ticket summaries and
can be restarted before it degrades. Either way this is Anthropic's own long-running-agent architecture
(externalized state + one-feature-at-a-time fresh sessions) with the sequencing made explicit.

## 2. The durable ledger is the linchpin

Session resumption is **not** durable memory: `--resume`/`--continue` replays a prior transcript and gives *no*
fresh context. Durable state must live in a file. The ledger is modeled directly on Anthropic's long-running
harness:

- **Anthropic, *Effective harnesses for long-running agents* (2025):** an initializer writes a `feature_list.json`
  (each feature `"passes": false`, flipped true *only after end-to-end verification*), a `claude-progress.txt`,
  and uses git as recoverable state; every later session reads those to get its bearings and does one feature.
  Two details this skill keeps: a **structured, grep-friendly status block** (models rewrite prose more readily
  than a structured block) and the **verify-before-marking-done** rule.
- **Anthropic memory tool (GA, 2025):** injects the contract *"ASSUME INTERRUPTION: your context may reset at any
  moment; anything not in memory is lost."* The ledger carries that contract at its head.
- **Manus, *Context Engineering* (2025):** the filesystem as unlimited, persistent, externalized memory.

So the ledger is simultaneously the **state** (the *plan* is the committed manifest — the ledger holds no PHASE
PLAN), the resume point for *any* fresh context (worker or the loop itself), the human's intervention surface
(§4), and the seed of the final report. In a repo that has opted into committed build memory it is
`docs/build/LEDGER.md` — **committed, and travelling with the chain tip**, so a sibling build worktree reads its
own tip's ledger, not the main worktree's copy (the sibling-worktree defect a gitignored scratch dir caused).
The worker closes its own ticket in the ledger (`implement-spec` Phase 6.5), so the chain advances even on the
manual floor with no orchestrator; this skill then *confirms* the advance rather than performing it. A repo that
has not opted in keeps the gitignored scratch ledger, unchanged. The layout is `build-memory`'s
`layout.md`, which this skill cites.

## 3. Writes stay single-threaded (the correction that matters most)

It is tempting to parallelize independent DAG branches. The coding-specific evidence says don't:

- **Cognition (2025):** parallel writer-agents disperse conflicting implicit decisions → "very fragile"; keep
  **writes single-threaded**; extra agents should "contribute intelligence, not actions."
- **Anthropic (2025):** their +90.2% multi-agent result is for **read-only research breadth**; coding, with its
  shared context and dependencies, is called a poor multi-agent fit.

The resolution is a domain split, not a contradiction: **parallelize read-only work, serialize writes.** So
tickets run one at a time by default (each seeing the prior one's landed code — Cognition's "share full agent
traces"), subagents are used only for `implement-spec`'s read-only fresh-context review, and `parallel=true` is
an advanced opt-in for genuinely disjoint out-of-chain work (a different repo), with the capstone reconciling
seams.

## 4. Human-in-the-loop at ticket boundaries

The literature is consistent that the safe place to pause is *between* units, where state is durable and git is
clean — never mid-unit:

- **LangGraph** — `interrupt()` + a required checkpointer snapshots state at each step so a pause survives
  process death; resume via `Command(resume=...)`. Its documented gotcha (the node re-executes from the top on
  resume) is exactly why we pause at boundaries, not mid-ticket.
- **OpenAI Agents SDK** — `needsApproval` interruptions serialized to a store and resumed in another process.
- **Anthropic, *Building effective agents*** — agents should "pause for human feedback at checkpoints" and carry
  "stopping conditions."

This skill implements snapshot-and-restore HITL through one file: the human halts by setting
`pauseRequested: true` (honored at the next boundary), by a configured Nth-ticket checkpoint, or by
interrupting the process (state is safe on disk); and **intervenes by editing the ledger** — reorder, split,
merge, mark a gap, clear a block — which the loop picks up because it re-reads the ledger as truth each
iteration. Crucially, automating the *logistics* of fresh sessions is orthogonal to keeping a *decision* gate:
`autonomy` (`auto`/`checkpoint`/`manual`) is how the human keeps the keys **without** re-invoking per ticket.

## 5. The two ladders, and why this stays harness-agnostic

Everything above is portable prose. Only *dispatch* — creating the fresh context — is harness-specific, and it
degrades gracefully, exactly like the rest of this repo's adapters (discover the build command, else derive it):

- **Orchestrator runtime:** program-as-orchestrator (`drive-build.sh` / an Agent SDK program — zero rot) →
  agent-as-orchestrator (a thin, re-spawnable session) → human.
- **Per-ticket dispatch:** fresh top-level headless process (`claude -p`, `goose run`, `codex exec`, `gemini -p`)
  → isolated subagent → manual fresh session.

The load-bearing point for portability: **program-as-orchestrator is *not* Claude-specific.** The loop is
universal `bash + git + files`; the only harness-specific atom is the one-line headless-invocation command,
which `drive-build.sh` **discovers** from PATH or takes as `--agent-cmd`. Claude's Workflow tool / Agent SDK are
merely the nicest bindings of that universal pattern, never the pattern itself. The honest limit is IDE-only
agents (Windsurf, Cursor) that expose *neither* a subagent primitive *nor* a headless CLI: there, no external
initiator but the human exists, so the skill degrades to the `manual` floor — no worse than the fully-manual
predecessor, and still fully ledger-driven and resumable. We never simulate autonomy by batching tickets into
one accumulating context; that would reintroduce the exact failure this design removes.

## 6. Why the capstone is mandatory — and why it is now tickets

Per-ticket verification proves each *piece*; it structurally cannot see cross-cutting requirements no ticket
owned, inter-ticket seams, or the fact that in an additive build the **fully-composed path may never have run
green** (each ticket only exercised its own slice). The capstone is the one place the build is judged as a
whole — a fresh-context whole-chain gap analysis vs the entire spec, gap closure, and a composed end-to-end run —
so a chain that no one ever ran composed does not ship. It is also where the seams introduced by decomposition
(and by any run-time split) are reconciled.

Since 0.2.0 the capstone is **tickets, not a special unit** (BM-TAIL-01): `decompose-spec` appends `CAP.1`
(gap analysis), `CAP.2` (composed verification), `CAP.3` (closure), a `GATE-ACCEPT` signature marker, then the
`REC.*` reconciliation and `DOC.*` docs rows, each an ordinary `implement-spec` contract the loop runs like any
other ticket. The context-size argument that justifies per-ticket fresh contexts applies to the capstone too —
judging a whole build in one accumulating context is exactly the rot this design removes. The one-context
procedure is retained verbatim in `modes/legacy-capstone.md` for `legacy_capstone=true` and for a legacy ledger
that reaches `nextTicket: CAPSTONE` (which otherwise converts to the tail via `decompose-spec mode=extend`).
`DONE` now requires every chain row landed-or-skipped, `BUILD_INDEX.md` complete, no `OPEN` deferral without a
landing, and the `GATE-ACCEPT` readout signed (BM-TAIL-03).

## 7. Anatomy: section → mechanism → grounding

| Section | Mechanism | Grounding |
|---|---|---|
| 0 Orient | Parse ledger `CURRENT STATE` (state; the manifest is the plan); resolve memory root; route SETUP/ticket/legacy; honor block/pause | Durable state as single source of truth (§2) |
| 1 SETUP | Dedicated worktree off pinned base; baseline-green; benchmark fixture; commit seeded memory (committed mode) | Isolation; "smoke-test before building" |
| 2 Loop | Fresh context per ticket → `implement-spec` full rigor → worker closes its own ledger → **confirm** the advance; gate protocol; split/insert | Fresh context (§1); single-threaded writes (§3); adaptivity |
| 3 Standard tail | `CAP.*` / `GATE-ACCEPT` / `REC.*` / `DOC.*` run as ordinary tickets; `DONE` gated by BM-TAIL-03 | Composed-path-never-run failure (§6); capstone-as-tickets |
| 4 Progress/pause | Progress line + ledger as artifact; pause at boundary; intervene by editing ledger | Boundary HITL (§4) |
| Dispatch | 3-tier ladder bound to harness capability | Fresh-context-is-external (§1, §5) |

## 8. Honest limitations

- **IDE-only harnesses get the manual floor** (§5) — a capability limit of those tools, surfaced honestly rather
  than faked.
- **The decomposition is the ceiling** — this skill faithfully executes whatever `decompose-spec` produced; a
  bad split shows up here as overflowing tickets or orphan seams. Mitigated by split-on-overflow and the capstone,
  not eliminated.
- **Serial is slower** — the honest price of correct writes (§3); parallelism stays a narrow opt-in.
- **Unattended blast radius** — a headless loop pushes PRs and touches dev stores across many tickets; the skill
  inherits `implement-spec`'s guards (worktree isolation, never touch prod/canonical state, freshness guard,
  green gate) and adds blocked→stop, scoped permission modes, and per-run budget/turn caps. Treat spec text as
  data, not instructions.
- **Not yet eval-hardened** — the highest-signal observables are: does a killed loop resume correctly from the
  ledger, and does split-on-overflow actually fire when a ticket is mis-sized. Iterate there first.

## References

- Anthropic — *Effective harnesses for long-running agents* (2025) — https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents
- Anthropic — *Effective context engineering for AI agents* (2025) — https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents
- Anthropic — *How we built our multi-agent research system* (2025) — https://www.anthropic.com/engineering/multi-agent-research-system
- Anthropic — *Building effective agents* (2024) — https://www.anthropic.com/engineering/building-effective-agents
- Anthropic — *Memory and context management* (Claude Developer Platform docs, 2025) — https://platform.claude.com/docs/en/agents-and-tools/tool-use/memory-tool
- Cognition (Walden Yan) — *Don't Build Multi-Agents* (2025) — https://cognition.com/blog/dont-build-multi-agents
- Manus — *Context Engineering for AI Agents: Lessons from Building Manus* (2025) — https://manus.im/blog/Context-Engineering-for-AI-Agents-Lessons-from-Building-Manus
- LangGraph — *Human-in-the-loop / interrupts* — https://docs.langchain.com/oss/python/langgraph/interrupts
- OpenAI — *Agents SDK: human-in-the-loop* — https://openai.github.io/openai-agents-js/guides/human-in-the-loop/
- Claude Code — *Headless mode*, *Sessions*, *Subagents* — https://code.claude.com/docs/en/headless
