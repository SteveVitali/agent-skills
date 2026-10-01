<!--
  Template: tail marker GATE-ACCEPT. Filled by: decompose-spec at seed/extend (in every tail,
  minimal included). This is a GATE marker, NOT an implement-spec input — orchestrate-build
  executes it, never guessed past. Placeholders filled on instantiation.
-->
# GATE-ACCEPT — operator signs the accepted-deviations list

> **Milestone gate — NOT an `implement-spec` input.** The chain STOPS here after CAP.3 until
> the operator dispositions the list for signature. Never guessed past. An operator or
> authorized human record supplies the decision; an agent must not sign or assume silence is
> approval.

- **Kind:** gate · **Phase:** capstone
- **Depends on:** CAP.3
- **Blocks:** `projectStatus: DONE` (BM-TAIL-03), the docs row(s), and REC.1–REC.3 (full tail) that assume signed deviations.

## Criterion (verbatim)
The operator has reviewed the list for signature in `docs/build/CAPSTONE_CLOSURE.md` (from
CAP.3) — (a) accepted deviations, (b) scoped-out owed legs, (c) waivers requested — and signed
each row as accepted, or sent a row back to closure. A build of {{ticket_count}} tickets against
`{{spec_path}}` is not DONE while any proposed row is unsigned. A scoped acceptance authorizes
action; it never raises a verdict (`accepted_scope` set ⇒ verdict ≤ MET-ENGINEERED).

## Readout
`docs/build/readouts/GATE-ACCEPT.md`, from `templates/READOUT.md` — append-only: the list
presented (agent-drafted, with its sha256), the two sums and the highest layer reached, the
operator's per-row disposition (ACCEPTED / SEND-BACK + what would accept it) in their own words,
`Status:` PASSED | NOT-PASSABLE | SKIPPED-BY-OPERATOR, and the Signature block appended at
signing. `orchestrate-build` records the operator's words verbatim in `LEDGER.md § GATE
DECISIONS` and commits on the chain tip; it never signs, ticks or attests for the operator.

## Pre-registered thresholds
Every row in the CAP.3 list for signature is signed (accepted) or returned to closure; no
proposed row is left unsigned; every waiver names an ADR quoting the operator.

## Deferrals rule
This gate refuses to pass while any `OPEN` row in `docs/tickets/DEFERRALS.md` scoped to the
capstone phase remains (`DEFERRALS.md` rule 4).

## Disposition
Recorded only from the operator's own words (READOUT shape + GATE DECISIONS `kind: decision`).
- [ ] *(live-read)* The readout cites the live state it describes: the CI read of every open PR
      in the stack (`ci-boundary.sh` output once it ships — BM-CI-01; until then
      `gh pr checks <n>` with its `date -u`); where the build has a production surface, a probe-run record (id,
      `date -u`, result, sha256) no older than 24 h at the commit. A statement about production
      state with no such citation is removed, not written.
