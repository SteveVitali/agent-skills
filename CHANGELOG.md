# Changelog

All notable changes to agent-skills are recorded here. Versioning is the plugin version in
`.claude-plugin/plugin.json`.

## 0.3.0 — Build memory guards, Tier A (SK-13, SK-14, SK-17, SK-18, SK-19, SK-20, SK-22)

The first staged part of the SK-01…SK-25 skill-change proposals (Round-11 planning, B6): the layout contract
and the templates a decomposition instantiates. The later tiers (SK-01/02/03/06/09/10 before the first dispatch;
SK-04/05/07/08/11/12/15/16/21/23/24/25 after) ship in later releases; where this release cites one of them it says
*(forward: SK-nn)*, and `layout.md` § "Rule ids cited before their full text lands" lists the rule ids involved.
**Backward-compatible:** scratch mode is unchanged; a committed repo without the new guards marker sees new
**warnings** only — no existing tree gains a failure.

### Behaviour changes
- **`decompose-spec` `tail` defaults to `minimal`**, and the minimal tail now keeps `GATE-ACCEPT`: `CAP.1`, `CAP.3`,
  `GATE-ACCEPT`, `DOC` (one docs row: `refresh-repo-docs` then `agent-docs`). Before, minimal had no
  `GATE-ACCEPT`, so BM-TAIL-03's `DONE` rule could never be met honestly. `tail=full` is unchanged, but the
  manifest's `## Decomposition decisions` must now say which REC rows read live state and why (SK-20, SK-22).
- **Validator:** a readout with a `Status:` line (the new READOUT shape) is judged PASSED by that line alone, with
  comments stripped; older readouts keep the whole-file match (SK-17).
- **`migrate-legacy-scratch.sh`** records the UTC date (`date -u`), not the host's local date (SK-13).

### Added / changed, by proposal
- **SK-13 — clock rule.** `layout.md` § Clock rule (BM-CLOCK-01). Every template date is
  `<date -u +%FT%TZ, at writing>` or `<date -u +%F>`; no bare `<date>` remains.
- **SK-14 — ledger contract.** BM-LEDGER-08 (guarded):
  - the orient region is ≤ 12 KiB (warning above 8 KiB);
  - CURRENT STATE holds values only: lines ≤ 256 B, no `| PRIOR`;
  - `returnPass` is an id list, and no stray CURRENT STATE key lines appear elsewhere;
  - the PHASE LOG is the last region, and its entries are ≤ 2 KiB.

  Also: the `living-archived` mode (archive under `reports/ledger-archive/`) and one append target
  (`## PHASE LOG — Round <n>`). The PHASE LOG kinds grow (`correction`, `restored`, `repair`, `harness-switch`,
  `retroactive`), and a PHASE LOG entry may carry optional `ci:`/`layer:`/`harness:` fields. GATE DECISIONS gets a
  7th `kind` column for new tables, and CURRENT STATE an optional `harness` key, accepted only between `round` and
  `updatedAt`. The LEDGER template gets the pointer-comment slot and orient/clock/CI lines in its OPERATING MODE;
  BUILD_INDEX gets a trailing `harness` column for new tables. There is no round-archive key.
- **Guards marker (BM-COMPAT-06).** Adding `<!-- build-memory-guards: 1 -->` on its own line in
  `docs/build/README.md` turns the guarded checks into failures. Entries in older PHASE LOG regions stay
  warnings. The JSON report gains `"guards"`.
- **SK-17 — readouts and markers.**
  - New `templates/READOUT.md`, which `init` copies to `docs/build/readouts/_TEMPLATE.md`. It has a single
    mutable `Status:` line, the guard sentence, an agent-drafted block with its sha256, and a Signature block
    that is appended at signing.
  - GATE, HUMAN and GATE-ACCEPT carry the guard sentence and point their disposition at the readout.
  - HUMAN gains Owner, Scheduled, "Withheld until done" and "Deferrals so far". It is never skipped by default.
- **SK-18 — contracts.**
  - The ticket header gains `Production mutations:` and `Size budget:`. ACs carry `layer:` tags, and the
    template adds a `## Operating clauses` section; the universal phase-gate AC gains the operating clauses.
  - The manifest gains `## Operating rules (binding on every ticket)`.
  - DEFERRALS gains rule 5 (human work is scheduled). The validator warns on an OPEN/PARTIAL `P` row that has
    no `owner:`/`trigger:`.
- **SK-19 — status layers and verdicts.**
  - BM-STATUS-01 layers. BM-VERDICT-01 adds `MET-ENGINEERED(D-id;…)`, `WAIVED(ADR-nnn)` and `N/A-RATIONALE`.
  - `COVERAGE_MATRIX.csv` appends `required_domain, achieved_domain, owed_legs, accepted_scope`.
  - CAP.1 gets verdict ACs. CAP.3 gets the two sums and the three-part signature list. GATE-ACCEPT: a scoped
    acceptance never raises a verdict.
- **SK-20 — tail right-sizing.** Every tail template has a `*(live-read)*` AC (BM-TAIL-04). New
  `tail/DOC__docs-refresh.md`. The validator warns when `projectStatus: DONE` has no signed
  `readouts/GATE-ACCEPT.md`.
- **SK-22 — decomposition.** `decompose-spec` gets:
  - never pre-answer a gate (only `pre-authorization` rows with item ids, `expires:` and `voided-by:`);
  - HUMAN rows scheduled like tickets;
  - numbered `### Round <n>` banners in the chain table;
  - Phase 0 extend reads CI and the operator digest *(forward: SK-01, SK-08)*.

  The validator warns "pre-answered gate?" on a seed ledger whose GATE DECISIONS holds a non-pre-authorization
  row.
- **Tests:**
  - new fixtures `v2-legacy-ledger` (exit 0 with warnings) and `v2-guards-violations` (exit 1);
  - LEDGER variants (the `harness` slot, seed and DONE warnings, Status-line readouts);
  - template golden checks;
  - a migrate clock test under `TZ=Pacific/Kiritimati` and `TZ=Pacific/Pago_Pago`.

### Not in this release
Announced by the proposals for the full set, and still pending:
- `auto` gates pause instead of skip-all (SK-03);
- the `projectStatus` enum enforced, and validator exit 3 for vacuous checks (SK-15);
- history mode (SK-16).

For the same reason, rule-5 failures on rows *added* under the guards marker and the readout guard-sentence check
wait for SK-16/SK-15.

## 0.2.0 — Build memory v2

Build memory becomes a **committed, validated layout** every build skill reads and writes the same way, and the
lifecycle is covered end to end (brief → research → spec → decomposition → build → capstone → reconciliation →
docs → next round). **Opt-in and backward-compatible:** a repo activates the new layout only by a
`docs/build/README.md` marker (`<!-- build-memory: v2 -->`); a repo without it behaves exactly as 0.1.0
(gitignored scratch mode), and every existing input keeps its name and default.

### Added
- **`build-memory`** — owns the layout contract (`layout.md`), the templates, the validator, and migration.
  Modes: `init`, `check`, `migrate`, `adr-index`. Scripts: `memory-root.sh` (resolve committed vs scratch root
  from the current worktree), `check-build-memory.sh` (validate the layout; exit 0/1/2), `adr-index.sh`
  (regenerate the ADR index), `migrate-legacy-scratch.sh` (move a legacy scratch dir into `docs/build/`;
  dry-run by default, contents byte-identical). Self-test fixtures under `tests/`.
- **`synthesize-spec`** — the upstream half: a `docs/research-ledger.md` whose rows are executed in fresh
  contexts, then synthesis, fresh-context adversarial review, and operator ratification, handing off to
  `decompose-spec` via `docs/decomposition-prompt.md`. Modes: `plan`, `run`, `synthesize`, `review`, `ratify`.
- **`reconcile-build`** — the closeout procedures the tail `REC.*` tickets invoke. Modes: `backlog` (a single
  complete, non-duplicating backlog + operational readiness), `spec` (ticket-vs-spec + reconciliation plan),
  `integration` (a read-only merge dry-run, integration plan, release notes, next-round memo). Scripts:
  `check-backlog.sh`, `merge-dryrun.sh` (never merges).

### Changed
- **`decompose-spec`** — new inputs `mode` (seed | extend), `tail` (full | minimal), `sequence_prefix`; Phase 5
  now calls `build-memory init`, writes the state-only ledger and the v2 manifest, appends the standard tail
  rows, and runs the validator; the spec-amendment protocol is spelled out; committed mode defaults
  `tickets_dir` to `docs/tickets`.
- **`orchestrate-build`** — resolves the memory root and routes legacy ledgers; the ticket/marker **gate
  protocol** (a gate is a pause, not a block); the worker now closes its own ledger and the orchestrator only
  *confirms* the advance; the capstone is **the standard tail of tickets** (`CAP.*`/`GATE-ACCEPT`/`REC.*`/`DOC.*`),
  with the one-context procedure retained in `modes/legacy-capstone.md`. `drive-build.sh` gains `--skill`,
  parses `returnPass`/`manifest`, exits 0 on gate-pending, and logs under the gitignored `logs/` in committed mode.
- **`implement-spec`** — resolves the memory root; reads `DEFERRALS.md` and the ticket header (refusing
  skeletons); writes the committed `runs/<ID>.md` run ledger, ADRs, and `pr/<ID>.md`; a gate-pending live check
  is a deferral, never a fabricated pass; a new Phase 6.5 **closes the ticket** (BUILD_INDEX row + LEDGER advance
  + validator + `docs(build): close <ID>`). Scratch-mode behaviour is unchanged.
- **`agent-docs`** — the Doc Authoring Guidelines gain an optional **Build memory** section, generated for
  marked repos; the freshness detector reports a missing root-AGENTS.md "Build memory" section as a coverage gap.
- **`refresh-repo-docs`** — Phase 0 reads a `docs/README.md` mode table: generated → regenerate; frozen /
  historical / append-only → report-only (`docs/tickets/` and `docs/build/` default to historical).

### Compatibility
- No existing input renamed; no default changed outside committed mode; legacy ledgers still drive (on
  `nextTicket: CAPSTONE` a legacy ledger converts via `decompose-spec mode=extend`, or runs the retained
  one-context capstone under `legacy_capstone=true`).
- `build-memory migrate` adopts the layout for an in-flight build without renaming history or editing moved
  contents.

## 0.1.0 — Initial release

`implement-spec`, `decompose-spec`, `orchestrate-build`, `self-review`, `review-pr`, `address-pr-comments`,
`agent-docs`, `refresh-repo-docs`.
