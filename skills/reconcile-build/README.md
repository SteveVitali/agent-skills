# reconcile-build — design rationale

A multi-session build does not end at the last feature ticket. Both production builds ran a closeout phase —
gather the debt, reconcile what shipped against the spec, plan the integration — and both hand-rolled the
procedures. `reconcile-build` packages them as the skill the tail `REC.*` tickets invoke.

## Why a separate skill, not part of orchestrate-build

Two reasons, the same ones that put the Doc Authoring Guidelines in `agent-docs` rather than in every doc skill:

- **The line ceiling.** Folding backlog + spec-reconciliation + integration procedures into `orchestrate-build`
  would push that SKILL well past the ~500-line hub ceiling the repo holds to.
- **Sequencing vs content.** `orchestrate-build` *sequences* units; it should not also *contain* what a closeout
  unit does. The tail tickets `decompose-spec` emits say "invoke `reconcile-build mode=…`", exactly as the docs
  tickets say "invoke `refresh-repo-docs`" — the sequencer stays thin, the content lives here.

## The one idea: every owed thing in exactly one row

The failure mode of build closeout is debt that is "tracked" in the deferrals file *and* an ADR revisit trigger
*and* an OPEN FINDINGS note *and* a risk register — which means it is tracked nowhere, because no one place is
authoritative. `backlog` mode inverts that: it gathers every owed thing from every source into a single
`BACKLOG.csv`, where each source id lands in **exactly one** row's `sources` cell, and `check-backlog.sh` fails
the build if any source appears zero times (dropped) or more than once (double-tracked). The backlog becomes the
single home for "what's left," and `OPERATIONAL_READINESS.md` makes "are we done" answerable with a `proof:` on
every critical-path step instead of a `TBD`.

## Why the merge tool never merges

`integration` must be safe to run at any time, including on a shared machine mid-build, so `merge-dryrun.sh` is
strictly read-only: it computes each merge in memory with `git merge-tree` and greps for conflict markers,
writing nothing and checking out nothing. The plan it feeds is a **copy-pasteable operator procedure** — the
actual merge and release stay the operator's decision, because landing a stack is exactly the irreversible,
outward-facing act that should not be automated behind the operator's back.

## Honest limitations

- **Completeness is checkable only for id-bearing sources.** `check-backlog.sh` verifies deferrals, non-`MET`
  coverage rows, and ADRs — each has a stable id. OPEN FINDINGS and free-text register rows have no ids, so their
  inclusion is a reviewer check, flagged as a reminder rather than enforced.
- **Spec reconciliation proposes; it does not decide.** `spec` mode writes the plan and applies an amendment only
  where the operator ticked it and `apply_amendments=true` — and always through `spec_src` with a manifest line
  and an ADR. It will not silently rewrite a spec to match what got built.
- **The merge dry-run is a `git merge-tree` approximation.** It catches textual conflicts, not semantic ones —
  two branches that merge clean can still be logically incompatible; that is what the capstone's composed
  verification is for.
- **It is not a sequencer or a release tool.** `orchestrate-build` runs the `REC.*` tickets; the operator runs
  the merge from the procedure this skill writes.

## References

- The layout it reads/writes: `skills/build-memory/layout.md` (`DEFERRALS.md`, `docs/adr/`, `COVERAGE_MATRIX.csv`,
  `BUILD_INDEX.md`, `BACKLOG.*`, `*_PLAN.md`, `OPERATIONAL_READINESS.md`, `planning/`).
- The tail tickets that invoke it: `REC.1` / `REC.2` / `REC.3` (from `build-memory`'s `templates/tail/`).
- The sequencing half it plugs into: `orchestrate-build`.
