# Legacy one-context CAPSTONE (retained for `legacy_capstone=true`)

In build-memory v2 the capstone is **tickets** — `CAP.1` (gap analysis), `CAP.2` (composed verification),
`CAP.3` (closure), each an ordinary `implement-spec` unit in the chain (see the main skill §3 and BM-TAIL-01).
There is no special CAPSTONE unit any more.

This file preserves the pre-0.2.0 **one-context** capstone procedure verbatim, for two cases (BM-COMPAT-03):

- a **legacy ledger** (PHASE PLAN present, `manifest:` absent) reaches `nextTicket: CAPSTONE` and the operator
  sets `legacy_capstone=true` (rather than running `decompose-spec mode=extend tail=full` to convert to v2 and
  continue with tail tickets); or
- an operator explicitly prefers the single-context closeout for a small build.

---

## 3. CAPSTONE — whole-build closeout *(when `nextTicket: CAPSTONE`, after the last ticket)*

The last ticket is done; run the ledger's **CAPSTONE checklist**. This is the same gap-analysis → close → verify
rigor as a ticket, but scoped to the **entire composed build at once** — the one place the build is judged as a
whole, because each additive ticket only ever exercised its own slice and the fully-composed path may never have
run green:

1. **Fresh whole-chain gap analysis (read-only).** Diff the cumulative composed final state
   (`git diff <pinnedBaseSha>...<chainTip>` + reading the real final files) against the **spec as a whole** —
   every §, every cross-cutting invariant, the out-of-scope list, the contracts. Classify each requirement
   **MET / MET-DIFFERENTLY (sound deviation vs gap-in-disguise) / PARTIAL / MISSING / AT-RISK-INTEGRATION**.
   Explicitly hunt what a per-ticket lens cannot see: cross-cutting requirements "subsumed by" something else,
   inter-ticket seams, dual-owned fields, and any composed path never run green end-to-end. **Run this in an
   independent fresh context (default on)** — it is *the* anti-bias mechanism; skip only on the operator's
   explicit, recorded say-so.
2. **Close the real gaps** on a capstone branch (`<user>/<build_name>-capstone`, forked from `chainTip`), each a
   small scoped change; **consciously accept** sound deviations (record the reasoning). CODE gaps get fixed +
   tested; VERIFICATION gaps get run.
3. **Composed end-to-end verification** — the whole build exercised as one unit: a composed-final-state
   unit/integration test (the fully-wired path the additive tickets never covered) and, if applicable, the
   fully-composed agentic run on the benchmark set (repeat-scored, running-binary==HEAD, whole-chain acceptance).
   If the composed run is environment-blocked (creds/quota/infra), that is itself a capstone finding — record the
   exact blocker + what would close it and route the verdict to the operator; **never fabricate a green.**
4. When gaps are closed-or-consciously-accepted and the composed E2E is green (or its blocker is recorded +
   routed): set `projectStatus=DONE`, append a "CAPSTONE done" PHASE LOG entry (gap-closure summary +
   composed-E2E evidence), and print the completion summary. **Await operator go-ahead before mutating anything.**
   A real unclosed gap or a regressing composed result sets `blockedOn` and does NOT advance to `DONE`.
