# Changelog

All notable changes to agent-skills are recorded here. Versioning is the plugin version in
`.claude-plugin/plugin.json`.

## 0.4.0 — CI at every boundary, gate records, production rule, clock (Tier B-must: SK-01, SK-02, SK-03, SK-06, SK-09, SK-10)

The second staged part of the SK-01…SK-25 proposals (Round-11 planning, B6): the skill text that, followed
literally, reproduced an observed failure on every harness — "no CI polling", `auto` answering every gate item
with "skip", the "(gitignored) ledger" with no production rule, and dates with no named source. A minor bump,
not a patch, because three behaviours change. Scratch mode is unchanged; a committed repo without the guards
marker sees no new failure (the one new validator check is guarded). Still pending, cited as *(forward: SK-nn)*:
SK-04/05/07/08/11/12/15 (next), SK-16/21/23/24/25 (Round 11).

### Behaviour changes
- **`auto` no longer skips every gate item** (SK-03). In `auto`, a gate item is answered without a pause only
  when a live `pre-authorization` row names its id (acting on that row's words); otherwise the loop pauses as in
  `checkpoint`. Human, rights, counsel, publication and acceptance items always pause. An `auto` build that relied
  on "skip all" now stops at those items.
- **`drive-build.sh` reads CI before every dispatch** (SK-01, SK-02). With `--skill orchestrate-build` (the
  default) it runs `ci-boundary.sh --stack` on the last landed ticket's PR before dispatching the next unit and
  before reporting DONE or a pause; fail, pending after the bounded wait, or unreadable → exit 2 and nothing is
  dispatched. A restart re-reads the same PR. `--no-ci-gate` opts out (printed in the log header); a repo with no
  CI declared reads `none-declared` and passes; other `--skill` ledgers default to off.
- **`drive-build.sh` enforces the `projectStatus` enum** (SK-02): a value outside NOT_STARTED | IN_PROGRESS |
  BLOCKED | PAUSED | DONE (e.g. `IN-PROGRESS`) stops the loop with exit 2 before any dispatch. The first token of
  the value is compared, so a trailing comment still works.
- **`implement-spec` reads CI after its push** (SK-10) and records a `ci:` field; a red it caused is fixed in the
  ticket, a red inherited from the base is reported **blocked** (PHASE LOG `blocked` entry + `blockedOn`, no
  advance). "No CI polling" is gone from both skills; "no CI *fixing* outside the ticket" replaces it.

### Added / changed, by proposal
- **SK-01 — CI truth at every boundary.** New `orchestrate-build/scripts/ci-boundary.sh` (bash 3.2 + `gh`,
  read-only): reads a PR's checks at its head and, with `--stack`, every still-open ancestor PR; bounded poll
  (`--interval 60 --max-wait 2700`, `--no-wait`); resolves the PR from `--pr`, or from `--ledger`/`--ticket`
  (BUILD_INDEX PR cell → PHASE LOG `done` entry → for `lastCompleted` only, the open PR at `chainTip`); required set from
  `docs/build/tools/record_policy/ci_required.txt` when present; honours GATE DECISIONS `waiver` rows naming
  `#<n>` and the check (per PR); delegates to a repo hook `docs/build/tools/ci_boundary.{py,sh}` with
  `--pr <n> --json <path>` and passes its exit code through; exits 0 pass / none-declared · 3 fail ·
  4 pending · 5 unknown; writes a `ci-boundary/1` JSON record and prints the `ci:` or `blockedOn:` line to
  record. `orchestrate-build` §2.1 re-reads the previous PR before dispatch, §2.3 gains step 4 (CI truth) and
  step 5 (external state), §0 clears `blockedOn: CI …` only on a pass read (a `repair` entry), §2.5 continues
  only on pass/none-declared. `layout.md` gains the full BM-CI-01 text. The tail templates and
  `decompose-spec mode=extend` now cite the script instead of "once it ships".
- **SK-02 — `drive-build.sh`.** Status-enum guard; the CI gate above (`--ci-gate`/`--no-ci-gate`,
  `--ci-interval`, `--ci-max-wait`); the prompt gains "Every date you write comes from `date -u` at that moment"
  and "Record your harness and model id as `Harness: <harness>/<model-id>/<tier>` in the run-ledger header".
  New `--print-prompt` (not in B6; added for harnesses with no headless CLI, e.g. a desktop agent driven by
  hand): runs the same checks, then prints the fresh-session prompt for the next unit and exits without
  dispatching, so the `manual` tier gets the mechanical CI gate too.
- **SK-03 — gate-record hardening.** `orchestrate-build` §2.1 carries the five gate-record rules and the new
  `auto` clause; GATE-G markers drafted by the orchestrator go in a labelled `agent-drafted` block; two new
  guardrails. `layout.md` BM-GATE-01 is corrected and BM-GATE-05…09 get their full text (verbatim, tentative ≠
  decision, no proxy signatures, agent-drafted text labelled and hash-confirmed, scoped pre-authorization).
  Validator (guarded): in a 7-column GATE DECISIONS table, `kind` must be decision | pre-authorization |
  confirmation | waiver | correction, and a `pre-authorization` row must carry `expires:` and `voided-by:`.
  Legacy 6-column tables and bullet-style records are not judged.
- **SK-06 — no out-of-ticket production changes.** `orchestrate-build` guardrail BM-PROD-01 (an in-chat "yes"
  authorizes inserting a ticket, never a command); the non-goal now says it edits only "the build memory
  (committed or scratch)". `implement-spec` §5.3 runs a production mutation only when the ticket's
  `Production mutations:` header names it, through the named scripted path, after recording pre-state and
  rollback. `layout.md` gains the full BM-PROD-01 text.
- **SK-09 — the clock rule for the worker.** `implement-spec` §0.5; "bump `updatedAt`" → "set `updatedAt` from
  `date -u`"; DEFERRALS flips carry the `date -u` date.
- **SK-10 — one honest closeout.** `implement-spec` §6.5 step 0 reads CI; the BUILD_INDEX `PR` cell is the real
  `#<n>`, never `PR pending`; the PHASE LOG `done` entry goes at the end of the file, ≤ 2 KiB, with `ci:`,
  `layer:` and `harness:` fields; protected records only gain lines; the closeout commit also stages
  `runs/<ID>.md`; §6.4 reports a `CI:` line. The run-ledger header carries `Harness:`, `Skills:`, `Started:` and
  `Closed:` (BM-INDEX-02). *(forward: SK-16 — `--staged` history check.)*
- **Tests.** New `orchestrate-build/tests/run-tests.sh` with a stub `gh` and a stub agent CLI: ci-boundary pass /
  fail / cancel / pending-then-pass / pending-forever / no checks / unreadable / gh absent / none-declared /
  required set (missing, skipped, non-required red) / stack inherited red / per-PR waiver / ledger resolution /
  repo hook, plus a replay of B4's four recorded red heads (#141, #165, #179, #185 → 4 stops); drive-build green
  to DONE, red stops after one dispatch, restart on red, pending past the wait, off-enum status, no CI declared,
  gate pending, `--no-ci-gate`, `--print-prompt` (green and red), the prompt sentences, and a non-build skill.
  build-memory gains the gate-record cases (guards fixture + ledger variants). New root `tests/lint-skills.sh`:
  the retired phrases stay retired, the new rules are present, and every BM id the build skills cite resolves.
  Every new assertion fails against 0.3.0.

### Not in this release
SK-04 (CURRENT STATE `harness:` + `harness-switch` entries; the run-ledger `Harness:` line is in), SK-05
("reconcile it yourself" → `repair` entries), SK-07 (orient budget), SK-08 (layered progress line, operator
digest), SK-11 (layered gap table), SK-12 (living-record pins), SK-15 (enum/exit 3/JSON identity in the
validator), SK-16 (history mode), SK-21, SK-23, SK-24, SK-25.

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
