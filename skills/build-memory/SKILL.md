---
name: build-memory
license: MIT
description: "Owns the build-memory contract that the multi-session build skills share: the committed layout under docs/build/, docs/tickets/ and docs/adr/, the templates, the validator, and legacy-scratch migration. Use it to initialise the layout in a repo (init), validate it (check), migrate a legacy gitignored scratch dir into the committed tree (migrate), or regenerate the ADR index (adr-index). Other skills cite skills/build-memory/layout.md rather than restating the layout."
inputs:
  - name: mode
    required: false
    description: "'init' (write the layout into a repo), 'check' (validate — default), 'migrate' (move a legacy scratch dir into docs/build/), or 'adr-index' (regenerate docs/adr/README.md)."
  - name: memory_root
    required: false
    description: "The build-memory root. Default: resolved by scripts/memory-root.sh ($BUILD_MEMORY_ROOT — e.g. a monorepo subproject's packages/app/docs/build — else committed docs/build when the marker is present, else legacy scratch)."
  - name: from
    required: false
    description: "[migrate] The legacy scratch path to migrate (e.g. .agents/scratch or $AGENT_SCRATCH_DIR)."
  - name: apply
    required: false
    description: "[migrate] Default false = print the dry-run plan only. true = perform the move/rename."
---

# Build Memory

The **owner of the build-memory layer** that `decompose-spec`, `orchestrate-build`,
`implement-spec`, `synthesize-spec` and `reconcile-build` all read and write. It owns one
contract file, one set of templates, one validator and one migration tool, so build memory
is defined in exactly one place.

> **Precedent.** `agent-docs` owns the shared Doc Authoring Guidelines other skills cite;
> `build-memory` owns the layout the same way. **The contract is
> [`layout.md`](layout.md)** — the tree, the modes, the machine-state ledger, the manifest /
> ticket / marker / tail shapes, the deferrals / ADR / index / gate rules, who writes what,
> the validator, and the compatibility policy. Read it before any mode below; every other
> skill cites it and does not restate the tree.

Build memory is **committed** (the record of a multi-session build is audit-valuable and git
is the artifact store); only regenerable bulk (`logs/`) is gitignored. A repo opts in with
the marker `<!-- build-memory: v2 -->` in `docs/build/README.md`. A repo without it runs in
**legacy scratch mode** — byte-for-byte the pre-0.2.0 behaviour (see `layout.md` §
Compatibility and [`README.md`](README.md)).

## Resolve the root first (every mode)

// turbo
```bash
bash scripts/memory-root.sh --paths    # prints: mode=<committed|scratch>  root=<abs path>  (+ project= docs= tickets= adr=)
```

Committed mode → the root is `<worktree>/docs/build`, resolved from the **current** worktree
(a sibling build worktree reads its own chain tip). Scratch mode → the legacy gitignored
dir (stated on stderr). `$BUILD_MEMORY_ROOT` overrides both: a relative value resolves against the
worktree toplevel, and a missing dir is an error, never a fallback.

**Monorepo subproject (BM-ROOT-03).** When the build memory lives under a subproject, set
`BUILD_MEMORY_ROOT=<sub>/docs/build` (relative) in the harness's persistent env. Then
`<memory root>` is that dir, tickets and ADRs are its siblings `<sub>/docs/tickets` and
`<sub>/docs/adr` (`BUILD_MEMORY_TICKETS` / `BUILD_MEMORY_ADR` override), and every `docs/…` path in
this skill and in [`layout.md`](layout.md) means the same path under `<sub>/` — with the variable
unset they are the literal paths, as before. Without the variable, `memory-root.sh` exits 3 naming
the subproject root rather than silently picking scratch; the validator run from the toplevel
exits 2 with the same hint.

---

## Mode: `check` (default)

Validate the layout. Read-only; exit-code gated; runnable in CI.

// turbo
```bash
bash scripts/check-build-memory.sh .                      # tree mode: 0 clean · 1 violations · 2 not a build-memory repo · 3 vacuous
bash scripts/check-build-memory.sh . --range BASE..HEAD   # history mode (also --staged, --first-parent SHA); 5 = unknown
bash scripts/check-build-memory.sh . --planning docs/research-ledger.md   # planning-ledger freshness (V14)
# monorepo subproject: the same commands with BUILD_MEMORY_ROOT=<sub>/docs/build exported (or --memory-root
# <sub>/docs/build, or the project dir as repo_root: check-build-memory.sh <sub>); docs/… paths then resolve under <sub>/
```

It checks everything the skills derive (layout allowlist + `logs/.gitignore`; ticket filename
grammar + unique sequence; manifest ↔ files both ways; backward `Depends on`; skeletons carry
no run line; markers referenced; DEFERRALS ids unique + valid statuses; no OPEN row past a
PASSED gate; ADR files ↔ generated index; every ADR has `## Revisit trigger`; spec ADR
appendix == file set when present; `LEDGER.md` key set + order and `nextTicket`; PHASE-LOG
"done" ↔ `BUILD_INDEX` row + `runs/<ID>.md`; REQ→ticket coverage when the spec and
`req_id_pattern` resolve; size + secret scans; the ledger budget and shape, BM-LEDGER-08; the
`kind` of 7-column GATE DECISIONS rows and scoped pre-authorizations, BM-GATE-05/-09; the
CURRENT STATE vocabularies; stale orient text; record dates later than the clock; BUILD_INDEX
row shape; readout guard sentences; run-ledger `Harness:` lines; `living-pin?` tests). The PHASE
LOG parser reports what it evaluated, and exits 3 rather than pass vacuously. The human summary
lists each violation and warning; the JSON report (`build-memory-check/2`: input identity, counts,
diagnostics) goes to `--json PATH` or a unique temp file named on the last line. **A failure is
a real block** — the caller does not proceed past it. *Guarded* rules warn unless
`docs/build/README.md` also carries `<!-- build-memory-guards: 1 -->` (BM-COMPAT-06), so legacy
content never fails on them.

**History mode** (`--range`, `--staged`, `--first-parent`; `scripts/check-history.sh`, BM-HIST-01)
judges only the lines a change adds or removes — append-only regions and their append position,
row-annotated DEFERRALS, frozen contracts and ADRs, `*.jsonl` prefixes, the living-archived
ledger head, and the record dates on added lines (R1–R6) — so legacy content never fails it. A
repo guard `docs/build/tools/memory_guard.*` takes over when present; repo policy lives in
`docs/build/tools/record_policy/history.policy`.

`decompose-spec` runs `check` after seeding, `implement-spec` before its close commit (tree,
then `--staged`), `orchestrate-build` at every boundary (tree, then `--range`).

---

## Mode: `init`

Write the layout into a repo. **Idempotent — never overwrites an existing file.** For each
target, if the file is absent, create it from the matching template in [`templates/`](templates/)
(filling any placeholders); if present, leave it untouched.

1. Resolve the root (above; `memory-root.sh --paths --allow-missing` before the root exists).
   `init` implies committed mode: the target root is `<repo>/docs/build`, or `$BUILD_MEMORY_ROOT`
   in a monorepo subproject — then every `docs/…` target below is under the subproject
   (`<sub>/docs/build/README.md`, `<sub>/docs/tickets/…`, `<sub>/docs/adr/…`, `<sub>/docs/README.md`),
   and the `AGENTS.md` section goes into the subproject's `AGENTS.md` when it has one.
2. Create, if absent:
   - `docs/build/README.md` (from `templates/build-README.md`; **must** contain the marker).
   - `docs/build/LEDGER.md` (from `templates/LEDGER.md`; the state-only shape — seed
     `projectStatus: NOT_STARTED`, `round: 1`).
   - `docs/build/BUILD_INDEX.md` (from `templates/BUILD_INDEX.md`; header row only).
   - `docs/build/logs/.gitignore` containing `*` then `!.gitignore` (the one ignored subtree).
   - `docs/tickets/{00_MANIFEST.md,_TEMPLATE.md,DEFERRALS.md}` (from `templates/MANIFEST.md`,
     `templates/ticket.md`, `templates/DEFERRALS.md`).
   - `docs/build/readouts/_TEMPLATE.md` (from `templates/READOUT.md`).
   - `docs/adr/{_TEMPLATE.md}` (from `templates/adr-TEMPLATE.md`); then generate
     `docs/adr/README.md` with `adr-index` (below).
   - `AGENTS.md` "Build memory" section (from `templates/AGENTS-build-memory.md`) — appended
     if `AGENTS.md` exists, else the section is offered to `agent-docs`.
   - `docs/README.md` — if it exists, **add** the build-memory rows (build/, tickets/, adr/)
     with their modes; else create it from `templates/docs-README.md`.
3. Do **not** overwrite tickets, ledgers, ADRs, or a spec that already exist.
4. Run `check` (with `BUILD_MEMORY_ROOT` set in a subproject) — a fresh `init` must be clean.

`decompose-spec` calls `init` during seeding; the operator may call it directly to adopt the
layout in an existing repo.

---

## Mode: `adr-index`

Regenerate `docs/adr/README.md` from the ADR files (numeric order; columns ADR · Title ·
Ticket · Status; carries the generated marker). Never hand-edit the index.

```bash
bash scripts/adr-index.sh docs/adr          # writes docs/adr/README.md
bash scripts/adr-index.sh --check docs/adr  # print to stdout only (what the validator diffs)
```

---

## Mode: `migrate`

Move a legacy gitignored scratch dir into the committed `docs/build/` tree. **Mutating** with
`apply=true`; a dry-run plan otherwise. Move/rename only — the contents of every moved run
ledger / PR body / tool / fixture stay byte-identical; the machine ledger is the one file
edited, and only by appending `manifest:` / `memoryRoot:` / `round:` to CURRENT STATE.

```bash
bash scripts/migrate-legacy-scratch.sh --from .agents/scratch          # dry-run plan
bash scripts/migrate-legacy-scratch.sh --from .agents/scratch --apply  # perform it
```

Mapping (see the script header for the full list): `implement-spec_*.md` → `runs/<ID>.md`
(id from the filename, else the file's H1; unresolvable names keep their basename);
`pr/*`, `tools/*`, `fixtures/*`, `planning/*` → the same-named dirs; `*build-ledger.md` →
`LEDGER.md` (converted); `*.log` → dropped; the rename mapping is appended to
`docs/build/README.md`. After migrating, run `check` and review the diff before committing;
then remove the now-empty legacy dir and add `docs/build/logs/` to `.gitignore` (leave the old
`.agents/` line — it is harmless).

---

## Templates and tests

- [`templates/`](templates/) holds one self-describing template per artifact (each with a
  header comment naming who fills it and when):
  - **memory root & docs map:** `build-README.md`, `docs-README.md`, `AGENTS-build-memory.md`.
  - **machine state & index:** `LEDGER.md`, `BUILD_INDEX.md`.
  - **contracts & markers:** `MANIFEST.md`, `ticket.md`, `ticket-skeleton.md`, `HUMAN.md`,
    `GATE.md`, `READOUT.md`, `DEFERRALS.md`, `adr-TEMPLATE.md`.
  - **upstream (synthesize-spec):** `research-ledger.md`, `research-CONVENTIONS.md`,
    `spec-front-matter.md`.
  - **closeout CSVs:** `COVERAGE_MATRIX.csv`, `BACKLOG.csv`.
  - [`templates/tail/`](templates/tail/) — the tail tickets `decompose-spec` instantiates:
    `CAP.1`, `CAP.2`, `CAP.3`, `GATE-ACCEPT`, `REC.1`, `REC.2`, `REC.3`, `DOC.1`, `DOC.2`
    (`tail=full`), and `DOC` (the default `tail=minimal`'s single docs row).
- [`tests/`](tests/) holds fixture repos (`v2-clean`, `v2-violations`, `legacy-scratch`,
  `v2-legacy-ledger`, `v2-guards-violations`, `v2-reqcov`, `v2-vacuous`, `v2-positional-status`, and
  `v2-monorepo` — build memory under `sub/proj/`, selected by `BUILD_MEMORY_ROOT`), `history/build.sh` (throw-away git repos committed
  with `GIT_COMMITTER_DATE` in the shapes of real violations) and `run-tests.sh`, which exercises
  all five scripts, asserts exit codes and expected files, and golden-checks the templates. Run it
  from anywhere:

// turbo
```bash
bash tests/run-tests.sh     # one PASS line per fixture; exit 0 iff all pass
```

## Scripts (all bash 3.2+, read-only unless noted)

| Script | Role |
|---|---|
| `scripts/memory-root.sh` | resolve `mode` + `root` (+ `--paths`) for the current worktree |
| `scripts/bm-paths.sh` | sourced, not run: derives docs/tickets/adr from one memory root (BM-ROOT-03) |
| `scripts/check-build-memory.sh` | the validator (BM-VALID-01): tree, history and planning modes |
| `scripts/check-history.sh` | history mode (BM-HIST-01) — what a change adds or removes |
| `scripts/adr-index.sh` | regenerate the ADR index (BM-ADR-02) |
| `scripts/migrate-legacy-scratch.sh` | **mutating** with `--apply`: legacy scratch → `docs/build/` |

## What this skill does NOT do

- **No sequencing, no implementation** — it owns the layer; `orchestrate-build` sequences and
  `implement-spec` implements.
- **No harness-specific config** — the layout is portable prose + POSIX-ish bash.
- **No deletion of history** — migration moves and renames; it never edits moved contents and
  never drops anything but regenerable logs.
