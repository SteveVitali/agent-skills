---
id: execute-task
description: "Spec-driven, autonomous end-to-end: branch → plan + test matrix → implement (tests alongside) → self-review → gap-analysis vs spec → close gaps → rigorous downstream verification → PR + evidence report"
inputs:
  - name: spec
    required: true
    description: "The authoritative spec/ticket to implement — a file path (preferred) or inline instructions. This is the CONTRACT the gap-analysis phase diffs the implementation against."
  - name: base_branch
    required: false
    description: "Branch to create from (default: current branch)"
  - name: branch_name
    required: false
    description: "Name for the feature branch (username/short-description; will ask if not provided and not autonomous)"
  - name: worktree
    required: false
    description: "If given, run in this git worktree path instead of the current checkout (isolation from other concurrent agents). The workflow assumes the worktree + branch already exist unless told to create them."
  - name: autonomous
    required: false
    description: "Default true. When true, run to completion without check-ins — surface only at the end with the PR link + evidence report. When false, pause for plan confirmation on large/cross-cutting tasks (execute-ticket behavior)."
---

# Execute Task

Turn an **authoritative spec** into a reviewable, spec-complete, rigorously-verified PR — autonomously.

This is the spec-driven sibling of `execute-ticket`: same context-loading, implementation discipline,
self-review-before-commit, and clean PR — minus the merge-main / CI-polling / Slack steps — plus the two phases
a spec-driven autonomous run needs: **gap analysis vs the spec** (Phase 4) and **rigorous downstream
verification** (Phase 5). The output is a PR **plus an evidence report** that proves completeness/correctness
against the spec — not just "it builds."

> **When to use `execute-task` vs `execute-ticket`:** use `execute-task` when there is an authoritative written
> spec, when the run must be fully autonomous to completion, and when "done" means *provably matches the spec*
> (not just "compiles + self-reviewed"). Use `execute-ticket` for a rough idea that needs a quick clean PR.

---

## Phase 0: Setup

### 0.1 — Resolve the working checkout

If `worktree` was provided, all git/build/test commands run **inside that worktree**. Pin it up front so no
command leaks into the wrong checkout (critical when other agents share the machine):

```bash
export TASK_ROOT="${worktree:-$(git rev-parse --show-toplevel)}"
# Run EVERY subsequent command with cwd = $TASK_ROOT: `cd` once in a persistent shell, or set the command's
# working directory in harnesses that forbid `cd`.
# For this repo's dev CLI, also pin the worktree so `crawl` targets the right slot/ports:
export CRAWL_DEV_WORKTREE="$TASK_ROOT"
git rev-parse --show-toplevel   # confirm you are where you think you are
```

If the worktree does not yet exist and the operator asked you to create it, create it from the base ref (see
0.2). Otherwise assume it exists and is on the intended branch.

### 0.2 — Determine base + feature branch

- `BASE_BRANCH` = provided `base_branch`, else `git branch --show-current`.
- `branch_name`: if not provided and `autonomous=false`, ask; if not provided and `autonomous=true`, derive one
  (`username/short-description`) from the spec title and proceed. Branch names follow `username/short-description`.

If the branch/worktree still need creating:

```bash
git fetch origin
# either an in-place branch:
git checkout "$BASE_BRANCH" && git pull origin "$BASE_BRANCH" && git checkout -b "$branch_name"
# …or an isolated worktree off a remote ref (preferred when other agents are active):
git worktree add -b "$branch_name" "$TASK_ROOT" "$BASE_BRANCH"
```

Record the exact base commit for the gap-analysis + PR:

```bash
git rev-parse HEAD          # base tip you branched from
```

### 0.3 — Load the spec + codebase context

1. **Read the spec in full.** If `spec` is a file path, read the whole file (and any companion docs it points
   to). Extract two structured lists you will use in Phase 4:
   - **Requirements** — every "shall/add/wire/implement" item, by section.
   - **Acceptance criteria** — the spec's explicit AC list (if present) plus any implied "must hold" invariants.
   This becomes the ledger's working checklist (0.4) for the whole run.
2. **Read the AGENTS.md hierarchy** (repo root → subproject → package) for conventions and "ask-first"
   boundaries, exactly as `execute-ticket` Phase 0.3 does. For this monorepo: `AGENTS.md`,
   `fsq-places/crawl/AGENTS.md`, and the relevant `fsq-places/crawl/agent_docs/*` (e.g. `scala_style.md`,
   `common_pitfalls.md`, `mongo_models.md` for models, `frontend_patterns.md` for UI, `local_dev.md` for the
   `crawl` CLI, `build_and_test.md` for targets).
3. **Read the spec's integration anchors.** A good spec names file:line anchors — open each so you implement
   against the real current code, not an assumed shape. Anchors drift: if the referenced code moved or changed
   since the spec was written, record the drift in the run ledger (0.4) and adapt; if the drift invalidates the
   spec's design, that is a hard blocker per the autonomy contract — surface it rather than silently improvising
   a new design.

### 0.4 — Create the run ledger (durable state)

Context is lossy over a run this long — compaction and session resets degrade exactly the fine-grained early
details Phase 4 depends on. Everything the later phases need must live on disk, not in the context window.
Create one ledger file in the canonical agent scratch dir (see AGENTS.md — never a worktree-local path):

```bash
SCRATCH="$(fsq-places/crawl/bin/agent-scratch-dir)"
LEDGER="$SCRATCH/execute-task_${branch_name//\//-}_$(date +%Y%m%d).md"
```

Seed it with: spec path, base commit, branch, and the Phase 0.3 requirements + acceptance-criteria checklist;
leave placeholder sections for the test matrix (1.4), the gap table (4.1), and the evidence log (5.4). Keep it
current at every phase transition. The ledger is three things at once:
- the **compaction-proof working checklist** for the whole run,
- the **resume point** if the session dies (a fresh session reads ledger + `git log` and continues), and
- the **seed of the Phase 6 evidence report**.

---

## Phase 1: Plan

Produce a brief implementation plan (skip only for genuinely trivial specs) and record it in the ledger.

### 1.1 — Scope + targets
- Which files change, which packages are affected, which "ask-first" boundaries are touched
  (e.g. `CrawlModels.scala`, new Maven deps, Kafka topics)?
- Map verification targets upfront:
  ```bash
  echo "<files you plan to change>" | .dev/evaluators/detect-targets.sh
  ```
- **Coverage guard:** the evaluators currently map only `fsq-places/crawl` + `fsq-places/common`. If your files
  fall outside that, a green `verify.sh` proves nothing — derive the real build/test commands from the affected
  subproject's AGENTS.md, use them everywhere this workflow says "verify," and say so in the final report.

### 1.2 — Baseline health check
Before changing anything, confirm the baseline is green: the mapped targets build/pass at the base commit, and —
if the change has a runtime surface you will dev-test in Phase 5 — the local stack starts clean. Pre-existing
breakage discovered mid-run gets misattributed to your change and burns hours; find it now, while attribution is
unambiguous.

### 1.3 — Approach + PR shape
- Summarize the approach in a few bullets: what changes in what files, which existing code is the template,
  and any design decisions/tradeoffs.
- If the spec suggests a PR shape / logical grouping, adopt it as your implementation order.

### 1.4 — Test matrix from the acceptance criteria
Translate **every** acceptance criterion into concrete planned tests *before implementing*: unit tests for pure
logic, integration tests for the seams, live scenarios for runtime behavior (these become the 5.3 matrix). Write
the matrix into the ledger. Deriving tests from the spec now — rather than from the finished code later — keeps
them asserting *what the spec demands* instead of *what the implementation happens to do*.

### 1.5 — Confirmation gate
- **`autonomous=true` (default):** do NOT pause. Record the plan (you'll include it in the final report) and
  proceed. The spec is the pre-approved contract — a mid-run check-in defeats the autonomous mandate.
- **`autonomous=false`, large/cross-cutting task:** present the plan and wait for confirmation before Phase 2.

---

## Phase 2: Implement

Adopt the implementation persona (same as `execute-ticket` Phase 2):

> You are a Staff Engineer who writes production-quality code — code your most critical colleague would approve
> on first review. Before writing, think about the contract (in/out/failure modes), what adjacent code looks
> like (match its idioms and level of abstraction), the edge cases (empty inputs, missing data, concurrency,
> network failures), and what the reviewer will look for. While writing: follow existing patterns over personal
> preference; prefer simple/obvious over clever; handle errors explicitly; name for the reader; make the minimum
> change that fully addresses the requirement.

Implement the spec in the planned order, **writing each logical group's tests (per the 1.4 matrix) as part of
implementing that group** — not as a Phase-5 afterthought. Keep the build green as you go — after each logical
group, run that subproject's build/test/lint commands (the ones its AGENTS.md / `agent_docs` prescribe) rather than accumulating
a large unverified diff. **Do not commit yet** — verification and review happen before the first commit (the
`execute-ticket` "one clean commit" principle), except that a long autonomous run MAY checkpoint-commit between
logical groups if that de-risks the run; if so, keep messages descriptive and squash-or-keep at your discretion.

Honor the conventions established by the AGENTS.md hierarchy and `agent_docs` you loaded in Phase 0.3, and by the
code adjacent to your change — the language/style rules, build-system constraints, and any "ask-first"
boundaries for the subproject you're in. Match the surrounding code over personal preference; when a convention
is documented (style guide, common-pitfalls doc), follow it exactly.

---

## Phase 3: Self-review (design + mechanical)

**Invoke `.dev/workflows/self-review.md` and follow it completely.** Pass 1 (mechanical: `verify.sh` + the
Scala/frontend checklists) and Pass 2 (Staff-Engineer design critique with full file reads). Fix everything it
surfaces and re-verify. Max 3 verify-fix-review iterations. If *design* concerns persist after 3, record them in
the ledger for the final report and proceed; a *mechanical* failure (red build or failing tests) is different —
it may never be carried forward and blocks the PR gate (6.0).

**Independence matters more than effort here.** A reviewer that just wrote the code is a biased reviewer — it
"knows what it meant." Where the harness supports subagents, run Pass 2 in a **fresh context** given only the
spec, the diff, and the ledger — not your implementation history. Where it doesn't, enforce the discipline
manually: re-read every changed file from disk in full and argue each judgment from what is actually there,
never from memory of writing it.

---

## Phase 4: Gap analysis vs the spec

The core addition of this workflow. Self-review asked *"is this good code?"*; this phase asks *"does it fully
satisfy what the spec demanded?"* — an orthogonal check. A change can be beautiful and still miss half the spec.

### 4.1 — Re-read the spec, then build the gap table
**Start by re-reading the spec file in full and rebuilding the requirements + AC list fresh.** Do not diff the
code against your Phase 0.3 extraction alone: that extraction is itself unverified — a gap analysis against your
own summary inherits its blind spots, and hours of context churn degrade it further. Diff the fresh list against
the ledger's list (catches extraction drift), then against the implementation (catches real gaps).

For **every** requirement and **every** acceptance criterion from the spec, record a row **in the ledger's gap
table**:

| item (spec §) | status: met / partial / missed | evidence (file:line, symbol, test) | if partial/missed: why + the fix |

Rules:
- **Evidence is mandatory for "met."** "I think I did that" is not met — cite the file:line/symbol/test that
  proves it. If you can't cite it, it's `partial` or `missed`.
- Read the actual implemented code to confirm, don't trust memory of what you wrote.
- Include the spec's **out-of-scope** list and confirm you did NOT implement those (scope creep is a gap too).
- Include cross-cutting invariants (e.g. "additive / back-compat when the new table is empty", "no change to the
  external verifier's write scope") — these are the ACs most easily missed.

Like Pass 2, the gap walk benefits from independence: where the harness supports it, have a fresh-context
subagent (spec + diff + ledger only) perform or double-check it.

### 4.2 — Reason about the optimal closure
For each `partial`/`missed`, don't just patch mechanically — reason from first principles about the *best* way
to close it given the codebase patterns and the spec's intent. Prefer the fix that a reviewer familiar with the
spec would consider obviously correct. If a spec requirement turns out to be genuinely infeasible or wrong,
do NOT silently skip it — record the conflict explicitly for the final report and choose the closest faithful
alternative.

### 4.3 — Close the gaps, then re-review
Implement every closure (with tests, per 1.4). After closing, **re-run Phase 3 self-review** on the new changes
(design + mechanical), then re-walk the gap table until **every row is `met` with evidence** (or explicitly,
defensibly deferred with a recorded reason). Keep the ledger's gap table current as rows close. Max 3
close-verify iterations.

---

## Phase 5: Rigorous downstream verification

Prove correctness + completeness at three levels. Do as many as *apply* to the change; skip a level only when
the change genuinely has no surface for it, and say so in the report. Use the build/test tooling the AGENTS.md /
`agent_docs` for this subproject prescribe (build wrappers, test-runner invocation, lint/typecheck commands,
local-dev launcher) — discover them in Phase 0.3 rather than assuming a stack.

### 5.1 — Unit / component
Run the full suites for the affected packages — the tests written in Phase 2 per the 1.4 matrix, plus the spec's
required suites; all green. If gap closure (4.3) introduced logic whose tests don't exist yet, write them now.
Tests must verify **behavior and contracts**, not just exercise code paths for coverage (see the self-review
Pass-2 test criteria). Any pure logic the spec
introduces (algorithms, selectors, scorers, state machines) gets direct, deterministic tests over its real
edge cases.

### 5.2 — Integration
Exercise the wired components end-to-end against the real seams the change touches (public interfaces, storage,
config, cross-module calls) — not just the units in isolation. Assert the spec's integration acceptance criteria
(round-trips, state transitions, inclusion/exclusion behavior, toggles, back-compat when the new surface is
empty). Use whatever driving mechanism fits the seam (in-process test, CLI invocation, HTTP request, etc.).

### 5.3 — Interactive / agentic live verification (the heart of this phase — do this wherever the change has a runtime surface)

Goal: **prove to yourself, empirically, that the change behaves as the spec says** — the way a careful human
would, by running the real thing and inspecting real signals. Not "a test passed" — *"I drove the live system
through representative cases and observed the expected behavior."*

1. **Stand up a safe local environment.** Launch the relevant local services / dev setup for this subproject
   (per its `agent_docs`/local-dev guide). Keep it isolated from other agents on the machine — use this
   worktree's own slot/ports/instances, not shared ones. If the change is compiled, ensure the *running* process
   actually contains your change before trusting anything: assert the live build == your HEAD (a version/gitSha
   endpoint, a process-start-time-after-build check, or the subproject's documented freshness guard). **A
   compiled change that isn't actually running invalidates every interactive result** — this is the single most
   common way live verification lies to you.
2. **Design representative test cases from the spec.** Enumerate the behaviors + acceptance criteria and turn
   each into a concrete scenario, including the *negative/precision* cases (what should NOT happen), boundaries,
   and the empty/back-compat case — not just the happy path. These scenarios are your live test matrix.
3. **Interact agentically to exercise each case.** Do whatever drives the behavior: HTTP requests, one-off
   scripts, CLI commands, seeding a scratch fixture, triggering the real flow. **Never mutate production /
   canonical state and never trigger paid/expensive operations** — use throwaway/tagged test fixtures. "Local"
   services often still hit shared dev datastores: record every fixture/record you create in shared stores in
   the ledger as you create it, and clean up from that list at the end — not from memory.
4. **Verify by inspecting every useful signal.** Confirm the observed result against the expectation using
   whatever data is available: command/script output, HTTP response bodies + status, database/state reads,
   **server logs**, metrics, rendered UI — cross-check more than one signal where you can. Actively look for the
   behavior being *wrong* (the negative cases), not just present.
5. **Iterate until convinced.** If a case doesn't behave as specified, that's a Phase-4 gap — fix it and re-run.
   Continue until every representative case demonstrably matches the spec.

### 5.4 — Evidence capture + synthesis
As you run each level, capture concrete evidence **in the ledger's evidence log** — the command/interaction and
the salient observed output (test summaries, sample responses, log excerpts, state reads, screenshots/render
confirmations). Synthesize the
interactive verification into a short narrative: what you drove, what you observed, and why it proves the
behavior — the same account you'd give a colleague who asked "how do you know this works?" If any check couldn't
be run (missing fixture, environment limitation), say so explicitly — **an unrun check is never reported as
passed.**

---

## Phase 6: Finalize — commit, PR, evidence report

### 6.0 — Green gate
If any code changed since the last clean `verify.sh` pass (Phase 4/5 fixes), re-run it now. **A red build or
failing test may never reach a ready-for-review PR.** If it can't be fixed within the bounded iterations, either
stop and surface it as a hard blocker, or open the PR as `--draft` with the failure stated at the top of the
body. Unresolved *design* notes may ship with the report; a red build may not.

### 6.1 — Commit (intentional staging)
Review `git status` and stage **intentionally** — every staged file should correspond to the change (cross-check
against the gap table's evidence column). Do not blanket `git add -A`: long runs produce stray one-off
scripts/fixtures, and those belong in the canonical scratch dir, not the PR. Exclude agent-harness dirs
(`.windsurf/`, `.claude/`, `.cursor/`, `.dev/`) **unless the spec's scope explicitly includes them**.

```bash
git status --short                       # review everything the run touched
git add <files that belong to the change>
git diff --cached --stat                 # confirm the staged set matches the intended change
git diff --cached --quiet || git commit -m "<descriptive message: what changed + why, ≤72-char summary line>"
```

### 6.2 — Push
```bash
git push -u origin "$branch_name"
```

### 6.3 — Open PR (no merge-main, no CI-poll, no Slack — see "does NOT do")
```bash
gh pr create --base "$BASE_BRANCH" --head "$branch_name" \
  --title "<concise title>" --body "<structured description>"
# or, if it exists: gh pr edit "$branch_name" --title "<title>" --body "<description>"
```
PR body: **Summary** (what + why) · **What changed** (files/areas) · **Design decisions** · **Verification**
(what was built/tested/driven) · a link/reference to the spec it implements · a **condensed acceptance-criteria
→ evidence table** (from the ledger), so the PR is self-reviewing and the proof survives outside the chat
transcript.

### 6.4 — Evidence report (the proof — this is the deliverable)
The ledger is the source of truth — derive the report from it, don't reconstruct from memory. Return to the
operator, in the final message:
1. **PR link** (`gh pr view "$branch_name" --json url --jq '.url'`).
2. **Acceptance-criteria table**: every AC from the spec → met/deferred → the concrete evidence (test output,
   observed live behavior, file:line) that proves it. This is the gap table from Phase 4, now backed by Phase 5
   evidence.
3. **Gap-analysis summary**: gaps found after first implementation + how each was closed (shows the phase did
   real work).
4. **Verification summary**: unit / integration / interactive results, with the commands run and headline
   outcomes; explicitly list anything not run and why.
5. **Deviations/deferrals** (if any): where the implementation intentionally differs from the spec, with the
   rationale.

### 6.5 — Notify
```bash
osascript -e 'display notification "PR is up with a spec-completeness evidence report" with title "execute-task" sound name "Glass"'
```

---

## Autonomy contract

When `autonomous=true` (default): run Phases 0→6 to completion **without stopping for check-ins**. The only
surfaces are (a) a hard blocker you genuinely cannot resolve (missing creds, an ambiguous spec contradiction that
changes the design) — surface it concisely and stop; and (b) the final report. Do not ask "should I proceed?"
between phases — the spec is the approval. Prefer making a defensible decision and recording it in the report
over pausing.

If the run is interrupted (crash, context exhaustion, reboot), a fresh session resumes from the ledger +
`git log`: re-read the spec, the ledger's phase status, and the gap table, then continue from the first
incomplete step. Never restart a partially-complete run from scratch.

---

## What this workflow does NOT do (deliberate omissions)

- **No merge-main.** Only merge base when there's a real conflict/stale CI; invoke `merge-main-fix-conflicts`
  separately if needed. (This is the key difference from the `execute-ticket` *skill* variant.)
- **No CI polling.** The push triggers CI; if it fails, invoke the fix-CI workflow separately.
- **No Slack post.** Separate, human-invoked concern.
- **No retention/cleanup of scratch fixtures beyond the run's own** — but DO clean up any test state you created
  in shared stores (Phase 5.3).

These compose on top when needed; they are not on the default critical path.
