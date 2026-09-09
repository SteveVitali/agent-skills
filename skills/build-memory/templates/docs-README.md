<!--
  Template: docs/README.md — the docs map with a mode column (BM-DOCS-02). Written by
  build-memory init if absent; init ADDS the build-memory rows (build/, tickets/, adr/) when
  a docs/README.md already exists. refresh-repo-docs reads the mode column: generated rows ->
  fix source/regenerate; frozen/historical/append-only -> report-only.
-->
# `docs/` — map of the documentation tree

Each entry has a **mode** that fixes how it may change. Editing a generated or historical file
by hand falsifies the record; only *living* docs are edited in place.

| Mode | Meaning | How it changes |
|---|---|---|
| generated | derived by a script | regenerate; never hand-edit |
| frozen | written once | immutable |
| append-only | rows/entries added | never removed or rewritten |
| historical | a record of what happened | corrected by a new entry, not an edit |
| living | edited in place until frozen | direct edits |

## Top-level entries

| Entry | Mode | What it is / how to change it |
|---|---|---|
| `brief.md` | frozen | the founding brief (optional) |
| `research-ledger.md` | living → frozen | S1–S3 work list + Q register; frozen at ratification |
| `research/` `design/` | frozen | numbered notes; `research/CONVENTIONS.md` is the finding format |
| `<spec>.md` | living → frozen | the canonical spec; amend via the manifest protocol + an ADR |
| `decomposition-prompt.md` | frozen | the committed hand-off to `decompose-spec` |
| `adr/` | append-only | decision records; `adr/README.md` is **generated** (`build-memory adr-index`) |
| `tickets/` | historical | the contracts (what was owed); `DEFERRALS.md` is append-only |
| `build/` | historical | the record of what happened (ledger, run ledgers, PR bodies, index, readouts) |

## Where to start
- Building a ticket? `build/LEDGER.md` → `tickets/00_MANIFEST.md` → `tickets/DEFERRALS.md`.
- Reviewing decisions? `adr/README.md`.
