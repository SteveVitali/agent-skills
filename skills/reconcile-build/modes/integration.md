# reconcile-build · mode: integration (BM-RECON-03)

Plan how the stacked-PR chain lands, draft the release notes, and seed the next round. Invoked by the `REC.3`
tail ticket. **Read-only about git** — this skill never merges.

## Write `docs/build/INTEGRATION_PLAN.md`
- **The PR graph** — the chain from `BUILD_INDEX.md` (each PR, its base, its head), so the stack's shape is
  explicit.
- **A merge dry-run** — run `scripts/merge-dryrun.sh` (read-only; it reports per PR/branch whether a clean merge
  is possible and never mutates a branch). Record which pairs merge clean and which conflict.
- **Strategy** — bottom-up vs squash vs rebase, given the dry-run results and the project's `mergePolicy`.
- **A copy-pasteable operator procedure** — the exact commands the operator runs to land the chain (the skill
  does not run them), with the order and the checks between steps.
- **Rollback** — how to back out each PR if a post-merge check fails.
- **Post-merge verification** — the whole-build check to run once the chain is on the main branch.

## Draft the release notes
From `BUILD_INDEX.md` (one landed row = one line), grouped for humans — features, fixes, breaking changes,
known gaps (the `BACKLOG.csv` `accepted` rows). A draft the operator edits, not a published note.

## Seed the next round
Write `docs/build/planning/<date>_decision-memo.md` — the skeleton the next `decompose-spec mode=extend` starts
from: what shipped, what the backlog carries forward, the open operator decisions, and the candidate scope for
round N+1. This is the bridge from closeout back into planning.

## Close
Report the merge-dry-run summary (clean vs conflicting), the release-notes draft location, and the next-round
memo. The `REC.3` ticket stamps its requirement ids and closes its ledger. The actual merge and release are the
operator's, from the procedure above.
