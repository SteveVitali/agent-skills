# build-memory — design rationale

`build-memory` exists because two production builds independently hand-rolled the same
missing structure, and both reversed the same default. This skill turns that lesson into one
committed, validated layout every build skill shares.

## Why committed, not scratch

The multi-session build skills originally kept all durable state in a **gitignored** scratch
dir and "promoted" selected artifacts into the tree at the end. Two builds showed why that
loses:

- **Eleutheria** (65 tickets) reconstructed its build memory *after the fact* — a full ticket
  of work that still lost fidelity, because the promotion step is a second, error-prone pass
  over state that should have been committed as it was produced. It recorded the decision in
  **ADR-058** ("tickets and build memory are committed; agent scratch is unified").
- **Rhēma** (22 ticket runs) hit the **sibling-worktree defect**: a build worktree resolves
  its scratch dir from `git-common-dir`, which points at the *main* worktree — so the ledger
  a sibling build worktree reads and the branch it is actually on disagree. A committed root
  resolved from the current worktree (BM-ROOT-02) fixes this by construction.

Both builds also accumulated large regenerable logs (Eleutheria: 4.5 MB) and both reversed
the gitignore rule by hand. So the design inverts the default: **commit by audit value,
ignore only regenerable bulk.** `docs/build/logs/` is the one gitignored subtree; fixtures
are size-capped by the validator; secrets never enter any file (the validator greps token
shapes); the ledger records `provided: yes/no` for credentials, never values.

The operator's amendment was to keep the old subdirectory *roles* (`runs/`, `pr/`, `tools/`,
`fixtures/`, `logs/`, `planning/`) but drop the name "scratch" — a committed directory of run
ledgers is not scratch, and the name invited the "delete freely" behaviour that lost
Eleutheria's logs. The root is `docs/build/`, opted in by a marker so a repo that already has
an unrelated `docs/build/` is not captured by accident, and a repo that never opts in sees
**zero** behaviour change.

## Why one owner skill

`agent-docs` owns the shared Doc Authoring Guidelines other skills cite; the layout deserves
the same single home. Before, each build skill restated the tree, and the copies drifted
(Eleutheria's PHASE PLAN listed a phase twice; Rhēma's gate marker named the wrong closers).
Now the layout lives once in [`layout.md`](layout.md); everything derived from it — the ADR
index, the BUILD_INDEX, the ticket sequence, DEFERRALS ids, REQ coverage — is **checked by a
script, never maintained by hand** ([`scripts/check-build-memory.sh`](scripts/check-build-memory.sh)),
exit-code-gated and runnable in CI.

## What the modes are for

- **`init`** adopts the layout in a repo, idempotently (never clobbers existing files).
- **`check`** is the validator every other skill runs at its boundaries.
- **`migrate`** moves a legacy gitignored scratch dir into the committed tree — move/rename
  only, contents byte-identical, dry-run by default — so an in-flight build (Eleutheria,
  Rhēma) can adopt v2 without rewriting history or renaming a single contract.
- **`adr-index`** regenerates the ADR index the validator diffs.

## Honest limitations

- **The REQ-coverage and spec-ADR-appendix checks are best-effort.** They run only when the
  ledger's `canonicalSpec` resolves to a real file and (for coverage) the manifest declares a
  `req_id_pattern:`. Without those, the validator skips them rather than guessing — a green
  run does not by itself prove full requirement coverage in a repo that omits them.
- **The migration id-resolver is heuristic.** It resolves ticket ids from filename styles seen
  in the two reference builds and from a run ledger's H1; a name it cannot resolve keeps its
  basename (safe, but you get `runs/<basename>` rather than `runs/<ID>.md`). Review the printed
  dry-run plan before `--apply`.
- **The validator reads structure, not meaning.** It confirms a ticket cites a requirement id
  that exists; it cannot confirm the ticket actually *satisfies* it — that is the worker's
  gap analysis and the capstone's job.
- **The "no OPEN row past a PASSED gate" check keys on the gate id appearing in the row.** A
  deferral scoped to a phase but not naming its gate id will not be caught; scope deferrals by
  citing the gate.
- **Not a scheduler or a merge tool.** Sequencing, merging, and CI are deliberately elsewhere
  (`orchestrate-build`, `reconcile-build integration`, the operator).

## References

- The originating analysis (`long-horizon-memory-structures.md`, §4 gaps G1-G18, §6 proposal) and the
  v2 specification derived from it are internal design documents held outside this repository; every
  requirement they fix is restated normatively in [`layout.md`](layout.md).
- ADR-058 (Eleutheria): tickets and build memory are committed; agent scratch is unified.
- The layout contract and every `BM-*` requirement it encodes: [`layout.md`](layout.md).
- The skills that consume it: `decompose-spec`, `orchestrate-build`, `implement-spec`,
  `synthesize-spec`, `reconcile-build`.
