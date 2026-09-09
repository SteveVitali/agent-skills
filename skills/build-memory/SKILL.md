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
    description: "The build-memory root. Default: resolved by scripts/memory-root.sh (committed docs/build when the marker is present, else legacy scratch)."
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
bash scripts/memory-root.sh            # prints: mode=<committed|scratch>  root=<abs path>
```

Committed mode → the root is `<worktree>/docs/build`, resolved from the **current** worktree
(a sibling build worktree reads its own chain tip). Scratch mode → the legacy gitignored
dir. `$BUILD_MEMORY_ROOT` overrides both.

---

## Mode: `check` (default)

Validate the layout. Read-only; exit-code gated; runnable in CI.

// turbo
```bash
bash scripts/check-build-memory.sh .    # exit 0 clean · 1 violations · 2 not a build-memory repo
```

It checks everything the skills derive (layout allowlist + `logs/.gitignore`; ticket filename
grammar + unique sequence; manifest ↔ files both ways; backward `Depends on`; skeletons carry
no run line; markers referenced; DEFERRALS ids unique + valid statuses; no OPEN row past a
PASSED gate; ADR files ↔ generated index; every ADR has `## Revisit trigger`; spec ADR
appendix == file set when present; `LEDGER.md` key set + order and `nextTicket`; PHASE-LOG
"done" ↔ `BUILD_INDEX` row + `runs/<ID>.md`; REQ→ticket coverage when the spec and
`req_id_pattern` resolve; size + secret scans). The human summary lists each violation; the
JSON at `/tmp/build-memory-check.json` mirrors it. **A failure is a real block** — the caller
does not proceed past it.

`decompose-spec` runs `check` after seeding, `implement-spec` before its close commit,
`orchestrate-build` at every boundary.

---

## Mode: `init`

Write the layout into a repo. **Idempotent — never overwrites an existing file.** For each
target, if the file is absent, create it from the matching template in [`templates/`](templates/)
(filling any placeholders); if present, leave it untouched.

1. Resolve the root (above). `init` implies committed mode: the target root is
   `<repo>/docs/build`.
2. Create, if absent:
   - `docs/build/README.md` (from `templates/build-README.md`; **must** contain the marker).
   - `docs/build/LEDGER.md` (from `templates/LEDGER.md`; the state-only shape — seed
     `projectStatus: NOT_STARTED`, `round: 1`).
   - `docs/build/BUILD_INDEX.md` (from `templates/BUILD_INDEX.md`; header row only).
   - `docs/build/logs/.gitignore` containing `*` then `!.gitignore` (the one ignored subtree).
   - `docs/tickets/{00_MANIFEST.md,_TEMPLATE.md,DEFERRALS.md}` (from `templates/MANIFEST.md`,
     `templates/ticket.md`, `templates/DEFERRALS.md`).
   - `docs/adr/{_TEMPLATE.md}` (from `templates/adr-TEMPLATE.md`); then generate
     `docs/adr/README.md` with `adr-index` (below).
   - `AGENTS.md` "Build memory" section (from `templates/AGENTS-build-memory.md`) — appended
     if `AGENTS.md` exists, else the section is offered to `agent-docs`.
   - `docs/README.md` — if it exists, **add** the build-memory rows (build/, tickets/, adr/)
     with their modes; else create it from `templates/docs-README.md`.
3. Do **not** overwrite tickets, ledgers, ADRs, or a spec that already exist.
4. Run `check` — a fresh `init` must be clean.

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
    `GATE.md`, `DEFERRALS.md`, `adr-TEMPLATE.md`.
  - **upstream (synthesize-spec):** `research-ledger.md`, `research-CONVENTIONS.md`,
    `spec-front-matter.md`.
  - **closeout CSVs:** `COVERAGE_MATRIX.csv`, `BACKLOG.csv`.
  - [`templates/tail/`](templates/tail/) — the nine tail tickets `decompose-spec` instantiates:
    `CAP.1`, `CAP.2`, `CAP.3`, `GATE-ACCEPT`, `REC.1`, `REC.2`, `REC.3`, `DOC.1`, `DOC.2`.
- [`tests/`](tests/) holds three fixture repos (`v2-clean`, `v2-violations`, `legacy-scratch`)
  and `run-tests.sh`, which exercises all four scripts and asserts exit codes and expected
  files. Run it from anywhere:

// turbo
```bash
bash tests/run-tests.sh     # one PASS line per fixture; exit 0 iff all pass
```

## Scripts (all bash 3.2+, read-only unless noted)

| Script | Role |
|---|---|
| `scripts/memory-root.sh` | resolve `mode` + `root` for the current worktree |
| `scripts/check-build-memory.sh` | the validator (BM-VALID-01) |
| `scripts/adr-index.sh` | regenerate the ADR index (BM-ADR-02) |
| `scripts/migrate-legacy-scratch.sh` | **mutating** with `--apply`: legacy scratch → `docs/build/` |

## What this skill does NOT do

- **No sequencing, no implementation** — it owns the layer; `orchestrate-build` sequences and
  `implement-spec` implements.
- **No harness-specific config** — the layout is portable prose + POSIX-ish bash.
- **No deletion of history** — migration moves and renames; it never edits moved contents and
  never drops anything but regenerable logs.
