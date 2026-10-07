# Changelog

All notable changes to agent-skills are recorded here. Versioning is the plugin version in
`.claude-plugin/plugin.json`.

## 0.5.2 — build-memory `reqcov`: ids a spec states without writing them out; an opt-in literal requirement index

A patch release for one defect and one opt-in check, found planning Episteme's Round 2 (OF-21; the proposal and its
scratch-copy tests are Episteme's `docs/build/planning/2026-10-05_reqcov-skill-patch.md`). **Backward-compatible:** a
repository without the new manifest line sees only fewer false warnings; no tree check becomes a failure.

### Fixes
1. **The spec's id set includes the ids a spec states without writing them out** (`spec_req_ids` replaces the literal
   grep in section 8). Three forms are expanded: a range token (`REQ-X-1…20`, `REQ-X-1..20`, `REQ-X-1–20`,
   `REQ-X-1…REQ-X-20`; capped at 500 ids), a continuation on the same line after a literal id
   (`REQ-X-1 (…) · -2 (…) · -3`), and a numbered list under a line that names the family without a number and says
   "requirements". The family pattern is derived from `req_id_pattern` alone; bash 3.2 / BWK-awk compatible. Before,
   a ticket citing such an id drew a false `reqcov` warning (9 on Episteme's tree; 0 after, every other line of the
   report identical).

### New (opt-in)
2. **`req_index_literal_from: <n>` in the manifest** makes every `## Requirement-ID → ticket index` row under
   `### Round <k>` (k ≥ n) a `reqindex` **violation** unless it holds exactly one literal id that the spec states,
   indexed once, to a chain ticket id or `deferred(<phase>)` (decompose-spec's one-owner rule). A Round-k ticket that
   stamps an id not indexed to it is a warning. Rows of earlier rounds are not parsed, so a legacy family/range table
   stays valid history.

### Docs and tests
- The script header and `layout.md` §5 describe both. New fixture `tests/v2-reqcov` (from `v2-clean`: a spec using
  all four forms and a two-round manifest) and a `test_reqcov` case in `run-tests.sh` asserting a clean pass and five
  seeded defects (a range row, an unknown id, an id indexed twice, a non-ticket owner; the unindexed stamp warning).

## 0.5.1 — Fixes found seeding SIG Round 11: report fields, history policy and `Closed:`, hook flags, V2 skip tokens

A patch release: six fixes for upstream defects that SIG's Round-11 seed units recorded in their run ledgers
(SEED-02a, SEED-02b, SEED-02c, SEED-15) while vendoring 0.5.0. **Backward-compatible:** no tree or history check
becomes a failure. The one new non-zero exit is a report path that cannot be written. Each change either removes a
false result or reports something truthfully that 0.5.0 got wrong. The behaviour notes below list every case where
an output can differ.

### Fixes
1. **JSON report fields no longer shift** (SEED-02c, SIG's local patch `L3`). `check-build-memory.sh` read its
   tab-separated diagnostic records with `IFS=<tab>`. Tab is IFS whitespace, so `read` merged adjacent
   separators: any diagnostic with an empty `file`, `obligation` or `evidence` put its message under the wrong
   key and left `message` empty. On SIG, all 45 warnings had an empty `message`. Records are now split on
   `\037`. `check-history.sh`'s `diags()` had the same defect: the usually empty `commit` shifted `rule` and
   `message`. So did `ci-boundary.sh`: an empty check description put the workflow name into the `blockedOn:`
   line (`(web): CI (run 333)` instead of `(web): fail (run 333)`), and an empty link moved `waived` into
   `link`. The human output was always right (awk `-F'\t'` does not merge separators).
2. **An unwritable report path fails** (SIG's local patch `L2`). `check-build-memory.sh --json <unwritable>` now
   exits 2 with `cannot write report to …`. Before, it printed the error and exited with the check's code, so
   a caller saw an exit code with no report behind it. History mode exits 5 (unknown, never green) in the same
   case, including `--replay`. Exit 2 already means "not applicable" there.
3. **History-policy comments keep `#` inside a token** (SEED-02a). `check-history.sh` stripped every ` #…` as a
   comment. That emptied `exempt docs/build/LEDGER.md ### RETURN PASS — current`, so the rule silently exempted
   nothing (SIG had to write the heading without `###`). It also cut `allow … PR #7` down to `PR`, an
   over-broad exemption. The documented rule is now: a comment is a line whose first non-blank character is
   `#`, or a lone `#` after whitespace (followed by whitespace or the end of the line) plus the rest of that
   line. A `#` inside a token is kept: `###`, `#123`, `^#+`. An `exempt` line's fields may also be separated
   by tabs or several spaces.
4. **A run ledger is closed only by a dated `Closed:` stamp in its header** (SEED-02a). The header is the lines
   before its first `##` heading. Before, history mode treated `Closed` anywhere as a close, so the Round-10
   shape `- **Closed:** none.` under `## Deferrals opened / closed` made the ledger append-only. An undated
   placeholder now does not close a ledger either. The tree-mode warning "`PR pending` but runs/<ID>.md is
   Closed:" uses the same `run_closed` rule.
5. **`ci-boundary.sh` forwards the wait and the ledger to a repo hook** (SEED-02b). A hook
   `docs/build/tools/ci_boundary.*` used to get only `--pr <n> --json <path>`. It therefore ignored
   `--no-wait`: `digest.sh` and `merge-dryrun.sh --ci` could block for the hook's own 45-minute wait per PR.
   It also ignored drive-build's `--ledger`, `--interval` and `--max-wait`. Now the caller's `--ledger`,
   `--interval`, and `--max-wait` / `--no-wait` are forwarded when the caller gave them **and** the hook's
   file names that flag (in its usage text or argument parser). `--no-wait` falls back to `--max-wait 0`,
   and the reverse, when the hook names only one of them. A hook that names none still gets exactly
   `--pr <n> --json <path>`. SIG's `ci_boundary.py` names all four. `--stack` is not forwarded: the hook owns
   the stack.
6. **V2 (`nextTicket` = the lowest chain row not landed) skips only on explicit gate-cell tokens** (SEED-15). The
   skip words (superseded, deferred, unused, skipped, withdrawn, dropped) used to match anywhere in a row.
   So a title like "the ADR-033-deferred parser layers" or a slug like `drop-unused-…` took a live row out of
   the order. A row now leaves the order only by a token in its gate cell (the row's last cell, the manifest's
   `gate` column): `superseded-by(<ids>)`, `superseded-by-split` (the skill's own split mark), `deferred(<D-id>)`
   or `unused`. HUMAN rows are also skipped. This matches SIG's `audit_current_state.py`
   (`ledger/next-not-lowest`) plus the split mark. **Legacy:** a bare word in the gate cell still skips, with
   one `manifest` warning naming the rows and the token to write. When a mismatch names a row that has a skip
   word only in its prose, the `nextTicket` warning says so.

### Behaviour notes (what can differ from 0.5.0)
- A chain row whose skip word appears only outside its gate cell is no longer skipped. On such a manifest the
  V2 warning can now name that row (still a warning only).
- In `history.policy`, a `#` glued to text (` #note`) is now kept as text. Inline comments need a lone `#`
  (` # note`). Full-line `#` comments are unchanged.
- A run ledger whose only `Closed:` is in a body section, or undated, is no longer judged append-only.
- `check-build-memory.sh` exits 2 (history mode 5) when its report cannot be written.
- `layout.md` (manifest, BM-CI-01, BM-HIST-01, the validator) and `orchestrate-build` §2.3/§2.4 state these
  rules. The split mark `superseded-by-split` goes in the gate cell. The MANIFEST template carries the token
  grammar as a comment under the chain table.

### Tests
29 new assertions, and every one fails against 0.5.0 (`8aeb6dc`, run from an export of that commit with the
new tests copied in): build-memory tree mode 9, history mode 7, orchestrate-build 5, lint 8. The controls pass
on both versions: a legacy hook keeps the bare contract, explicit tokens skip, a dated header stamp closes,
and a generated region with no `exempt` rule is judged. The two existing 3fd7104 history cases now write
`Closed:` in the run-ledger header, where `implement-spec` writes it, instead of at the end of the file.
- `build-memory/tests/run-tests.sh` `test_051` covers:
  - every report field sits under its own key, and no diagnostic has an empty `message`;
  - `--json /dev/null/nope/r.json` exits 2;
  - a body `Closed: none.` vs a dated header stamp;
  - V2 with skip words in the scope cell, each explicit token, and a legacy bare gate-cell word (skip + warn).
- `build-memory/tests/history/build.sh` covers:
  - a body `Closed: none.` and an undated `Closed:` placeholder (neither closes);
  - `exempt … ### RETURN PASS — current`, with and without a lone ` # ` comment, against the same region
    with no `exempt`;
  - an `allow` text that keeps `#7`;
  - the report's `commit`/`rule`/`message` keys;
  - an unwritable report (exit 5).
- `orchestrate-build/tests/run-tests.sh` covers:
  - a legacy hook still gets `--pr --json`, whatever the caller passed;
  - a hook that names the flags gets `--ledger`/`--no-wait` and `--interval`/`--max-wait`, only when they
    were given;
  - a `--max-wait`-only hook gets `--no-wait` as `--max-wait 0`;
  - an empty check description and an empty link.
- `tests/lint-skills.sh`: the gate-cell token grammar, the split mark in the gate cell, the header `Closed:`
  stamp, the policy comment rule, hook flag forwarding (layout and §2.3) and the unwritable-report exit are
  present. "`superseded-by-split` in the chain table" stays retired.

**SIG, read-only.** `check-build-memory.sh` on `/Users/stevenvitali/Eleutheria` at `a7951049` (clean, the same
`input_digest` both times):
- before: 2026-10-01T19:18:25Z (`date -u`), 0 violations, 45 warnings;
- after: 2026-10-01T19:51:05Z, 0 violations, 45 warnings, with the human diagnostic lines byte-identical;
- JSON diagnostics with an empty `message`: 45 → 0.

History mode `--range HEAD~5..HEAD --no-hook` gives 0 / 0 on both versions.

### Not in this release
- SIG's local patch `L1` (the report's `dirty` flag also covers the canonical spec the input digest reads) was
  not requested and is not ported.
- SIG's own `memory_guard.py` and `history.policy` header still describe the old comment rule. They are
  SIG-side and authoritative there, and their parsing is unaffected because SIG writes no inline comments.
- The 0.5.0 deferrals (the cross-harness eval, CI for this repo on Linux) stand.

## 0.5.0 — History mode, a truthful validator, harness identity and the operator digest (SK-04, SK-05, SK-07, SK-08, SK-11, SK-12, SK-15, SK-16, SK-21, SK-23, SK-24, SK-25)

The third and last staged part of the SK-01…SK-25 proposals (Round-11 planning, B6). With 0.3.0 (Tier A) and
0.4.0 (Tier B-must) it **completes B6's planned set**: every proposal is applied, and no *(forward: SK-nn)*
reference remains (`tests/lint-skills.sh` now fails if one reappears). A minor bump, because several behaviours
change (below). **Backward-compatible:** scratch mode is unchanged; a committed repo without the guards marker sees
new **warnings** only — the one new failure, exit 3, fires only for a PHASE LOG whose done entries mostly cannot be
parsed. History mode judges only what a change adds or removes, so it never fails a legacy record for what it
already holds.

### Behaviour changes
- **Validator exit 3 (vacuous).** When a ledger's PHASE LOG has `done` entries but fewer than half parse to a
  ticket id, the validator exits 3 instead of passing the done ↔ BUILD_INDEX check vacuously (SK-15 item 1).
- **The PHASE LOG parser strips `*`/`_`/backtick markup**, so legacy bolded entries are now evaluated: one that
  only parses after stripping is judged *guarded* in the current region and as a warning in older regions; a
  canonical entry fails as before.
- **CURRENT STATE vocabularies are checked** (`projectStatus`, `pauseRequested`, `mergePolicy`, `autonomy`,
  integer `round`, ISO `updatedAt`) — *guarded*. B6 proposed failing at once; it is guarded here so legacy trees
  (e.g. an `IN-PROGRESS` ledger) stay at 0 violations until they opt in with the guards marker.
- **The JSON report moved** from the shared `/tmp/build-memory-check.json` to `--json PATH` or a unique `mktemp`
  file named on the last stdout line, with schema `build-memory-check/2`: input identity `{repo, commit, dirty,
  input_digest}`, `summary.exit`, `counts {check: {candidates, evaluated}}`, diagnostics `{check, severity, file,
  obligation, evidence, message}` — the reviewed `contract/patch/3` shape of SIG's vendored fork (SK-15 item 10).
  `check-backlog.sh` (`backlog-check/2`) and `merge-dryrun.sh` (`merge-dryrun/2`) also write unique temp files.
- **`adr-index.sh` output changes where a cell read `—`**: it now parses `# ADR-NNN —` titles, `Phase` /
  `Phase / ticket` fields, plain (unbolded) header bullets and an appended `Superseded by` line, and escapes `|`.
  An index the 0.4.0 generator wrote is recognised (`--legacy`) and only warns; regenerate it (SK-21).
- **`check-backlog.sh` is verdict-aware** (SK-23): `MET-DIFFERENTLY` rows are no longer demanded as sources
  (back to the documented contract — a backlog that homed them still passes); `MET-ENGINEERED(D-…)` is covered by
  its owed-leg D-rows; `WAIVED(ADR-nnn)` by its ADR. New issue kinds: `stale-met-engineered`, `met-with-owed-leg`,
  `waiver-adr`, `home-closed`, `two-sums`, `readiness` (TBD). The matrix and backlog are read with a quote-aware
  CSV reader, so a quoted comma no longer shifts the verdict cell.
- **`drive-build.sh`'s prompt** names the ledger's recorded `harness:` and says that a different harness or model
  is a switch (stop and ask unless the operator's words are recorded), and when to write the operator digest; the
  log header prints the ledger's harness (SK-04, SK-08).
- **The validator's secret scan skips `docs/build/logs/` while reading** (same findings — they were filtered out
  afterwards); on SIG the tree check fell from 32 s / 100 s to 20 s / 21 s.

### Added / changed, by proposal
- **SK-04 — harness identity.** `layout.md` BM-HARNESS-01 full text (CURRENT STATE `harness:`, run-ledger
  `Harness:`, PHASE LOG `harness:` field, BUILD_INDEX `harness` cell, commit trailer; a switch only at a boundary,
  as a `harness-switch` entry quoting the operator; an unrequested switch pauses). `orchestrate-build` §0 records it;
  `implement-spec` §6.5 never overwrites a different `harness:` at close. Validator: a run ledger created after the
  guards marker without `Harness:` fails (older: one aggregated warning).
- **SK-05 — close, repair and planning discipline.** "Reconcile it yourself" is retired: a missing close is a PHASE
  LOG `repair — close: <gap>` entry, never a back-filled `done`; a second close repair in a round sets `blockedOn:
  worker close protocol broken`. Inserts are a scoped `decompose-spec mode=extend` (contract + fresh-context
  review); out-of-loop work gets a `retroactive` row first. Validator: two close repairs with `blockedOn` empty warn;
  chain rows outside a numbered `### Round <n>` banner warn (V13), and history mode fails a new one.
- **SK-07 — orient within a byte budget.** BM-ORIENT-01 full text (O1–O6, ≤ 48 KiB) in `layout.md` and
  `orchestrate-build` §0. Validator: stale orient paths (resolved against the repo or `docs/build/`) and tokens
  (`.agents/scratch`, `gitignored`, `Do not resume until`, + `record_policy/stale_tokens.txt`, where `!token`
  retires a default) and CURRENT STATE over 3 KiB are guarded; the orient probe (V11) warns over 48 KiB.
- **SK-08 — layered progress, operator digest, stop-and-ask.** BM-DIGEST-01 full text. New
  `orchestrate-build/scripts/digest.sh` appends a digest to `docs/build/reports/digests/<date -u +%F>.md`
  (append-only) from what it can read — harness, ledger state, validator, the CI of every open chain PR, merges by
  anyone since the previous digest (from GitHub), the default branch and whether the chain descends from it, owed
  human work with owner and trigger — plus the session's production, **spend** and **agent-usage** lines (never an
  invented figure); it refuses to write a token-shaped string and exits 3 on `--exposed yes`. `orchestrate-build` §4:
  the layered boundary line, the digest at every pause, session end, usage-limit event and the OPERATING MODE
  cadence (e.g. once per wave), and the stop-and-ask list (incl. a usage-limit event). `decompose-spec mode=extend`
  reads the latest digest (its forward reference is resolved).
- **SK-11 — layered status in the worker's evidence.** The gap table gains `required layer` / `achieved layer` and
  `met-engineered(D-id)`; fixture-only never reads `met` for a `live-executed` AC; stand-ins carry no retrieval
  dates; no agent label counts as human. BUILD_INDEX `live verification` vocabulary `live-executed | staging |
  fixture-only | engineered | n-a | gate-pending` (legacy `run`); off-vocabulary values warn.
- **SK-12 — tests assert invariants.** BM-TEST-01 full text; `implement-spec` §1.4/§5.1. Validator heuristic
  `living-pin?` warns on a tracked test that names a living record file and a living key (on SIG it flags
  `tests/unit/test_agent_docs_current_state.py:85`, as B6's replay predicted, and three more).
- **SK-15 — tree-mode truth checks** (items 1–10): bold-aware parser with `candidates`/`evaluated` and exit 3;
  vocabularies; budgets (incl. CURRENT STATE ≤ 3 KiB); stale paths/tokens; `nextTicket` = the lowest chain row not
  landed (warn; deferred/superseded/unused and HUMAN rows skipped); BUILD_INDEX column count (a header carried across
  headings), unique seq, `PR pending` once Closed:; record dates later than the clock (warn; `future-ok` exempts);
  the readout guard sentence (fails for readouts created after the guards marker — decided by commit ancestry, not
  timestamps); the orient probe; the JSON identity. `--now` sets the clock for tests.
- **SK-16 — history mode.** New `build-memory/scripts/check-history.sh` (bash 3.2 + git), reached as
  `check-build-memory.sh --range BASE..HEAD | --staged | --first-parent SHA`, plus `--replay FROM..TO` (a
  read-only backtest). BM-HIST-01 in `layout.md`: append-only + append position for the LEDGER's protected regions;
  living-archived head (byte-for-byte archive + pointer); DEFERRALS row-annotate (every cell's text survives; a new
  leading status carries a new date); readouts change only `Status:`; a run ledger already `Closed:` only gains lines; BUILD_INDEX added rows (column count, seq,
  real PR); manifest append-only sections, id registry, V13; frozen executed contracts (`> Amended` only) and landed
  ADRs (`Superseded by ADR-NNN` only); `*.jsonl` byte prefix; digests append-only; record-date rules R1, R2, R3, R5,
  R6 on added lines with each line's own committer time; repo policy `docs/build/tools/record_policy/history.policy`
  (`append-only`, `date`, `allow … expires`, `exempt`, `archive`); repo hook `docs/build/tools/memory_guard.*`
  delegated with `all <mode args>`; exits 0/1/2/5 (shallow clone → 5, "set fetch-depth: 0"). Wired into
  `implement-spec` §6.5 (`--staged`) and `orchestrate-build` §2.3 (`--range <chainTip before>..<after>`); DEFERRALS
  rule 5 for rows *added* under the guards marker now fails there.
- **SK-21 — `adr-index.sh` parses the header forms in use** (above); the validator warns on every `—` cell and
  fails one for an ADR added after the guards marker.
- **SK-23 — verdict-aware backlog, two sums, REC sweeps.** `check-backlog.sh` (above) prints and compares the two
  sums with `CAPSTONE_CLOSURE.md`; `modes/backlog.md` adds home liveness, readiness with probe/`ci-boundary`
  citations ≤ 24 h, and the REC sweeps (a dated revisit-trigger sweep, a risk-register `## Round <n> review`, the
  two sums); `tail/REC.1` carries them as ACs.
- **SK-24 — the integration plan reads CI and outside merges.** `merge-dryrun.sh --ci` reads each branch's open PR
  once through `ci-boundary.sh --no-wait` (pass / FAIL with the check and first failing line / pending / unknown /
  none, with the `date -u` of the read; without `gh`, `unknown`); `modes/integration.md` adds the external state and
  "a step that merges a red PR says so"; the non-goal is "no CI *fixing*"; `tail/REC.3`'s AC names the check state.
- **SK-25 — planning-ledger clock, freshness and verbatim decisions.** `check-build-memory.sh --planning <ledger>`
  (V14: `updatedAt` ≥ the newest change-log stamp, `lastCompleted` the newest done row the change log names,
  `nextUnit` not done; no build-memory marker needed); history mode judges planning change-log stamps (R1).
  `synthesize-spec` run/plan/ratify: stamps from `date -u` at writing (never `HH:2x`), one writer for CURRENT
  STATE, answers verbatim with the receipt time, agent-drafted answers `pending confirmation` until the operator
  confirms the exact text, hedged words → yes/no. The research-ledger template follows.
- **Layout and templates.** `layout.md` gives the full text of BM-HARNESS-01, BM-ORIENT-01, BM-TEST-01,
  BM-DIGEST-01 and BM-HIST-01 (the "cited before their full text lands" table is gone), the PHASE LOG `repair` /
  `harness-switch` / `retroactive` forms, the DEFERRALS flip form (`DONE <date> (evidence) — was: OPEN …`), and the
  validator's three modes. The LEDGER template's OPERATING MODE gains Records / Harness / Digest lines; the manifest's
  `## Operating rules` gains Records and Reporting; BUILD_INDEX, REC.1, REC.3, research-ledger and the AGENTS section
  follow.

### Tests
Every new assertion fails against 0.4.0 (run against a 0.4.0 worktree: build-memory 87, orchestrate-build 19,
reconcile-build 19, lint 33 failing assertions), and every earlier test still passes.
- `build-memory/tests`: `v2-violations` gains the bolded done entry, `IN-PROGRESS`, a `PR pending` row of a Closed:
  run ledger, a readout without the guard sentence and a future date; new `v2-vacuous` (exit 3); `v2-guards-violations`
  gains stale orient text and the Harness rule; `truth-checks` (vocabularies, nextTicket, close repairs, BUILD_INDEX
  shape, the clock with `--now` and `future-ok`, V13, the orient probe, `living-pin?`, unique JSON paths and the
  report identity), `new-files` (the guards marker by commit ancestry), `planning-v14`, the SK-21 adr-index cases.
- `build-memory/tests/history/build.sh` (new): throw-away repos committed with `GIT_COMMITTER_DATE` in the shapes of
  real SIG commits — `c2055d96` (rows deleted), `307161ee` (top insertion), `305f94d5` (+1 day), `95c8a73f`
  (signing: guard line deleted + `Date: 2026-10-19`), `0a715fcc` (in-place tick), `7a2ff9fa` (jsonl rewrite) —
  plus a correction line, living-archived exact vs one byte off, R2/`retro:`, `future-ok`, a sqitch line planned
  ahead, an expired vs live allow entry, R6, DEFERRALS flips, rule 5 with and without the marker, BUILD_INDEX rows,
  V13 and the id registry, frozen contracts and ADRs, `--staged`, `--first-parent` on a merge, scratch (2), shallow
  (5), an unresolvable range (5), the repo hook, `--replay`.
- `orchestrate-build/tests`: `digest.sh` (red and green PRs, an outside merge, owed P rows, spend/usage lines,
  append-only, merges since the last digest, a token-shaped string refused, `--exposed yes`, gh absent) and the
  harness lines of the prompt. The stub `gh` answers `pr list --state <s>`.
- `reconcile-build/tests/run-tests.sh` (new): a matrix with all eight verdicts × OPEN/PARTIAL/DONE D-rows (clean,
  every issue kind, dropped and double-tracked sources, the two sums) and `merge-dryrun.sh --ci` with the stub `gh`.
- `tests/lint-skills.sh`: "reconcile it yourself", "bump `updatedAt`" (synthesize-spec), "no CI" (reconcile-build)
  and any `forward: SK-` stay retired; the SK-04/05/07/08/11/12/16/23/24/25 rules stay present; BM-HARNESS-01,
  BM-ORIENT-01, BM-TEST-01, BM-DIGEST-01, BM-HIST-01 resolve in `layout.md`; cited ids are checked across every
  build skill.

**Replay over SIG** (read-only, `--replay` over the 479 first-parent commits to `b051732c`): every named B4 oracle
commit is flagged with the expected rule — G1 from `305f94d5`; G2 position `307161ee`, `ddf3ad29`, `a33cd6ec`,
`95c8a73f`, `4127dbf3`, `32bea406`, `b1250f62`; G4 `0a715fcc`, `95c8a73f`, `4127dbf3`, `3259ca81`; `c2055d96` at its
first-parent merge `e2175c93` (56 lines). Of B2's 25 loss commits, 21 are flagged; the 4 others follow B6's
narrower definitions (a run ledger rewritten before run ledgers carried `Closed:`; two contracts rewritten before
their BUILD_INDEX row existed; one dated status flip that kept its text). The skill's defaults are stricter than
B2's benign classes (placeholder fills, header status edits in landed ADRs, rewritten status cells), so 69 commits
B2 judged benign are flagged; a repo whose own guard implements B2's modes (`docs/build/tools/memory_guard.*`) is
delegated to and stays authoritative. Record-date positions are the build-memory ones by default (50 R1 commits;
code, fixture, spec and sqitch positions come from repo policy).

### Not in this release (recorded, not done)
- The cross-harness behavioural eval (B6 §6.6, trap scenarios T1–T5, N ≥ 3 per harness) — an agentic eval with
  real harness runs; the harnesses are the operator's choice (Q-B6-5).
- A CI workflow for this repo on macOS and Linux (B6 §6) — the suites ran on macOS bash 3.2 only; awk programs avoid
  interval expressions for mawk, but Linux is unverified.
- Mechanical checks for the REC.1 revisit-trigger sweep section and for production claims without a probe citation
  — prose and REC.1 acceptance criteria only; `check-backlog.sh` checks the sums and TBD.

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
