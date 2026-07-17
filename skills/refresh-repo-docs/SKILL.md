---
name: refresh-repo-docs
license: MIT
description: "Audit and sync a repo's human-facing documentation (README, docs/, CHANGELOG, CONTRIBUTING, examples) against the actual code — detect drift deterministically, fix stale claims, remove cruft, fill gaps, and verify every claim written. Use when docs are outdated, after major feature work, or on a periodic docs-hygiene pass."
inputs:
  - name: scope
    required: false
    description: "Directory path relative to repo root (default: '.' for the entire repo)."
  - name: audit
    required: false
    description: "'incremental' (default): only docs the detector flags plus docs affected by code changed since the baseline. 'full': every doc in scope gets a claim-by-claim audit."
  - name: since
    required: false
    description: "[incremental] Baseline git ref or date for 'what changed' (default: each doc's own last-modified commit — per-doc baselines beat one global ref)."
  - name: apply
    required: false
    description: "Default true: fix the docs. When false, produce the findings report only."
---

# Refresh Repo Docs

Converge a repo's **human-facing documentation** onto the code it describes.
Wrong docs are worse than no docs — a reader who follows a stale setup guide
or copies a dead example loses both their time and their trust in every
other doc in the repo.

Scope boundary: this skill owns README(s), `docs/`, CHANGELOG, CONTRIBUTING,
guides, examples, ADRs. It does **not** touch agent-facing docs (`AGENTS.md`,
`CLAUDE.md`, `agent_docs/`) — those have different consumers, quality bars,
and their own skill: `agent-docs`. If you find agent-doc drift here, note it
in the report and recommend an `agent-docs` refresh run.

Two rules the whole workflow hangs on:

- **Scope by evidence, not by reading everything.** The unit of work is a
  *flagged doc*, not the codebase. Deterministic signals (broken references,
  docs older than the code they describe) pick the worklist; reading every
  source file to "build a mental model" burns the context window before the
  first fix. Code gets read doc-first: for each claim, read exactly the code
  that can prove or refute it.
- **Never write a claim you didn't verify.** Every command, path, flag,
  default, and code example you write or keep must be checked against the
  current code — run it if read-only, read the source if not. The failure
  mode of doc syncing is replacing old guesses with new ones.

---

## Phase 0 — Detect

Run the drift detector from the repo root (read-only):

// turbo
```bash
bash scripts/check-repo-docs-freshness.sh <scope>
```

It writes `/tmp/repo-docs-freshness.json`:

- the doc corpus discovered in scope (agent docs excluded)
- **broken references** per doc — links and file paths that no longer exist
  (critical, deterministic)
- **stale suspects** — docs whose referenced code files have commits newer
  than the doc's own last commit, with the recency gap (suspicion, not
  proof: code can change without invalidating prose)

Build the worklist:

- `audit: incremental` (default) → every doc with broken references or a
  stale-suspect flag; plus, if `since` was given, every doc that references
  files changed in `git diff --name-only <since>..HEAD`.
- `audit: full` → every doc in the corpus. (Expensive; use for a first run
  on a neglected repo or a periodic deep pass.)

If the worklist is empty: report "docs current", stop.

Record the worklist as a **findings ledger** — a working file at
`/tmp/repo-docs-findings.md` with one section per doc. All findings from
Phase 1 go in it before any edits happen (audit fully, then fix — editing
while auditing loses the cross-doc picture, and the ledger survives context
compaction).

## Phase 1 — Audit the worklist

For each doc in the worklist:

1. **Classify its Diátaxis mode** — tutorial (learning), how-to (task),
   reference (facts), or explanation (understanding). The mode sets the
   quality bar for fixes (Phase 2) and is itself checkable: a reference page
   that has accreted tutorial prose, or a how-to bloated with theory, is a
   finding (`mode-drift`).
2. **Extract its checkable claims**: commands, file paths, API/CLI surfaces,
   config knobs and defaults, version numbers, code examples, architecture
   statements, feature descriptions.
3. **Verify each claim against the code** — read the specific source that
   proves or refutes it; run read-only commands (`--help`, `ls`, builds of
   examples) where cheap and safe. For claims the detector already flagged
   (broken refs), find where the target moved (`git log --follow`,
   `git log --diff-filter=R`) — a rename wants a path fix, a deletion wants
   the section removed.
4. **File each finding** in the ledger under one of:
   - **stale** — documented, but the code moved (wrong path, changed
     default, renamed flag, outdated example, superseded architecture)
   - **cruft** — documented, but the thing no longer exists (remove; for
     ADRs/design docs, mark superseded instead of deleting — they are
     records of decisions, not living docs)
   - **gap** — exists in code, matters to the doc's audience, undocumented.
     In incremental mode, check the *changed* surfaces (new commands, knobs,
     endpoints since the baseline) against the docs that should mention them.
   - **mode-drift** — content in the wrong document type (see 1)
5. **Severity**: `critical` (a reader following this doc gets a wrong
   result: broken command, dead example, false setup step) > `moderate`
   (misleading but survivable: outdated description, stale diagram) >
   `minor` (cosmetic: dead badge, old version string in prose).

Calibration: a finding must be *demonstrable* — name the code that
contradicts the doc. "This section could be expanded" is not drift; padding
docs with speculative content is how cruft gets created. When code and doc
disagree, the code is what's true *now* — but check `git log` intent before
"fixing" docs to match a bug (the doc may describe intended behavior; if so,
flag the code instead of rewriting truth to match an accident).

If `apply` is false: format the ledger (findings by doc, by severity, with
evidence), report, and stop.

## Phase 2 — Fix

Work through the ledger **one doc at a time, foundational docs first**
(architecture/reference before the READMEs and guides that cite them), so
downstream fixes can rely on upstream ones.

- **stale** → correct in place, re-verifying the replacement claim against
  code (not from memory of Phase 1). Update examples by running or
  type-checking them where feasible.
- **cruft** → delete the content (ADRs: annotate "Superseded by …" and
  leave). Removing a stale promise is a fix, not a loss.
- **gap** → write the missing content in the host doc's mode and voice, at
  proportional depth — a new config knob wants a row in the reference
  table, not an essay.
- **mode-drift** → relocate content to the right doc (or right section) and
  cross-link; don't delete substance to enforce purity.

Editing standards (kept intact from hard experience):

- **Minimal diffs** — don't reflow, reformat, or re-voice text whose content
  isn't changing; review noise buries the real fixes.
- **Match each doc's existing voice and conventions** — a refresh should be
  invisible except where it's a correction.
- **No placeholders** — never commit "TODO"/"TBD"; document fully or record
  it as a remaining gap in the report.
- **Never hand-edit generated docs** — fix the source/generator config and
  regenerate; note the generator in the report.
- **No fabricated changelog entries** — a changelog records what happened;
  backfill only from `git log` evidence, in the file's existing format.

## Phase 3 — Validate and sweep

1. **Re-run the detector** — broken references introduced or left = fix and
   re-run (max 2 iterations, then report what remains):

// turbo
```bash
bash scripts/check-repo-docs-freshness.sh <scope>
```

2. **Cross-doc consistency sweep** — re-read every doc this run touched,
   checking the *set*: the same feature named the same way everywhere;
   example config files agree with the config reference; README feature
   claims agree with the deeper docs behind them; no doc still cites content
   this run moved or removed.

## Phase 4 — Report and commit

Summarize from the ledger: per doc — stale fixed / cruft removed / gaps
filled / mode fixes, each one line; then **remaining gaps** (found but not
fixable without human input) and **code suspects** (places where the doc
described intent and the code looks wrong).

Stage only the doc files this run touched:

```bash
git add <docs touched>
git commit -m "docs: refresh repo docs — <summary>

Scope: <scope> (<audit mode>)
Stale: X fixed | Cruft: Y removed | Gaps: Z filled | Remaining: N (see PR/report)
"
```

## Optional CI integration

The detector is deterministic, fast, and exit-code-gated: run
`check-repo-docs-freshness.sh` on PRs that touch docs or heavily-referenced
source and fail (or warn) on broken references. Catching drift at change
time beats periodic sweeps; this skill remains the periodic *repair* tool.

## What this skill does NOT do

- **Agent docs** (`AGENTS.md` / `CLAUDE.md` / `agent_docs/`) — that's the
  `agent-docs` skill; same convergence philosophy, different consumers and
  quality bars.
- **Generate API reference sites** — it fixes prose and examples; generated
  references are the generator's job.
- **Restructure the doc tree wholesale** — file moves and information
  re-architecture need human buy-in; propose in the report instead.
- **Write marketing copy** — feature descriptions state what code does, not
  how exciting it is.
- **Decide what the code should do** — where docs and code disagree and the
  code looks wrong, it flags; it doesn't silently rewrite the docs to
  canonize a bug.
