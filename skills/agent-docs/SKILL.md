---
name: agent-docs
description: Create or converge agent documentation (AGENTS.md hierarchy) for a codebase — bootstrap mode generates docs from scratch, refresh mode detects and fixes drift
inputs:
  - name: scope
    required: false
    description: "Directory path relative to repo root (default: '.' for the entire repo)."
  - name: mode
    required: false
    description: "'bootstrap' (generate from scratch), 'refresh' (fix drift in existing docs), or omit to auto-detect: no agent docs in scope → bootstrap, otherwise refresh."
  - name: depth
    required: false
    description: "[bootstrap] Doc hierarchy depth: 'flat', 'hierarchical', or 'deep'. Default: auto-detect based on repo size."
  - name: deep
    required: false
    description: "[refresh] Also perform semantic verification of behavioral claims against source. Expensive (5-15 min, 200-500k tokens)."
  - name: cross-repo
    required: false
    description: "[bootstrap] Also generate integration-surface documentation describing how this codebase connects to other documented repos."
---

# Agent Docs

One workflow with two modes, both converging docs and code onto the same
target state: an accurate, AGENTS.md-standard doc hierarchy that an agent can
trust cold.

- **`bootstrap`** — no docs exist yet. Generate them from scratch:
  reconnaissance → gotcha mining → hierarchy design → generation.
- **`refresh`** — docs exist but may have drifted. Detect → triage →
  surgical fixes → (optionally) deep semantic verification.

The modes are the same convergence loop entered at different states: a
refresh that finds a severely drifted doc regenerates it with bootstrap's
machinery; a refresh that finds an uncovered package bootstraps a doc for it;
a bootstrap validates its output with refresh's drift detector. Both modes
finish through the same shared tail below.

All docs produced in either mode MUST conform to the
**[Doc Authoring Guidelines](guidelines.md)** — read that file before
generating or editing any doc.

---

## Phase 0 — Resolve scope and mode

Use the user-provided scope, or default to `.` (the entire repo). Then run
the drift detector once:

// turbo
```bash
bash scripts/check-agent-docs-freshness.sh <scope>
```

(The script lives in this skill's `scripts/` directory; run it from the repo
root. It writes a structured report to `/tmp/agent-docs-freshness.json`.)

**Mode resolution:**

| User said | Detector found | Mode |
|---|---|---|
| nothing | `docsScanned: 0` | `bootstrap` |
| nothing | docs exist | `refresh` |
| `bootstrap` | docs exist | Confirm intent. Then: fill gaps only — generate docs for *uncovered* areas via bootstrap; existing docs are never clobbered, they're refresh candidates. |
| `refresh` | `docsScanned: 0` | Report "nothing to refresh" and suggest bootstrap. Stop. |

## Phase 1 — Execute the mode core

- **bootstrap** → follow **[modes/bootstrap.md](modes/bootstrap.md)**
  (reconnaissance, gotcha & convention discovery, hierarchy design,
  generation, optional `--cross-repo` integration surface).
- **refresh** → follow **[modes/refresh.md](modes/refresh.md)** (triage the
  detector report, fix critical/moderate issues, fill coverage gaps, rewrite
  severely drifted docs, optional `--deep` semantic verification). The report
  from Phase 0 is the input — don't re-run the detector to start.

Both mode files end by returning here.

## Phase 2 — Shared tail

Every run, regardless of mode, finishes with these steps in order.

### 2.1 — Validate

Re-run the detector to confirm the docs now match the code:

// turbo
```bash
bash scripts/check-agent-docs-freshness.sh <scope>
```

- Critical issues = 0: proceed. (A fresh bootstrap MUST hit 0 on the first
  validation — anything else means something was generated from assumption
  rather than verification. Fix immediately.)
- Critical issues remain after a refresh: iterate (max 2 additional attempts),
  then report remaining issues to the user.

### 2.2 — Consistency sweep

Re-read every doc this run created or edited, plus its parent AGENTS.md,
checking for rules that now contradict each other (build commands that
differ, conventions stated one way at the root and another way in a nested
doc, gotchas that a fix made obsolete). Contradicting instructions cause
agents to pick one arbitrarily — resolve per the no-contradictions rule in
the [Doc Authoring Guidelines](guidelines.md).

### 2.3 — CLAUDE.md bridge

Claude Code reads `CLAUDE.md`, not `AGENTS.md` — without a bridge, everything
this workflow maintains is invisible to it. Unless the user opts out or the
repo already has a `CLAUDE.md`, create one at the repo root containing:

```markdown
@AGENTS.md
```

plus (only if needed) Claude Code-specific notes below the import: settings,
permissions, hook expectations. Keep it to the import line if there is
nothing Claude-specific to add — the point is one source of truth in
AGENTS.md, shared across harnesses.

### 2.4 — Quality checklist

Before committing, verify:

- [ ] Every command in "Build & Test" actually works when copy-pasted
- [ ] Critical Gotchas are genuinely non-obvious (not just "follow the style guide")
- [ ] No section is generic filler — every line earns its place
- [ ] File paths are verified against the filesystem (use `ls` / `find`)
- [ ] Line counts use actual `wc -l` values with proper rounding
- [ ] Docs read as if written by a knowledgeable engineer, not a template
- [ ] An agent reading the docs cold could start productive work within 1 task

### 2.5 — Commit

Review `git status` and stage only the doc files this run touched (exclude
agent-harness dirs like `.windsurf/`, `.claude/`, `.cursor/` unless the
bridge file was created):

```bash
git add <the doc files you changed>
git commit -m "docs: <bootstrap|refresh> agent docs — <summary>

Scope: <scope>
<bootstrap: docs created | refresh: Critical: X fixed | Moderate: Y fixed | Minor: Z fixed>
"
```

---

## Optional CI Integration

The structural detector is fast, deterministic, and exit-code-gated —
suitable as a PR check. Drift research (DOCER, EMSE 2023) found broken doc
references in ~29% of the top-1000 GitHub repos, typically unnoticed *for
years*, precisely because checking was manual; the same work ships a
PR-triggered action because catching drift at change time beats periodic
sweeps. Recommended split:

- **In CI (structural only)**: run `check-agent-docs-freshness.sh <scope>` on
  PRs that touch source or docs; fail (or warn) on critical issues. No LLM
  involved — cheap and deterministic.
- **Manual (this workflow)**: the LLM-driven generation, fixing, and `--deep`
  semantic verification stay human-triggered. Run refresh when you suspect
  drift (after refactors, after merging large PRs, periodically).

## What This Workflow Does NOT Do

- **Generate API documentation** — this produces agent orientation docs, not
  user-facing API docs
- **Convention drift detection** — if the team adopts new patterns, that
  requires human input to update "Code Conventions" sections
- **Cross-repo knowledge synthesis** — data flows between services need a
  different mechanism (`--cross-repo` documents this repo's *surface*, not
  the other repos)
- **Make architectural decisions** — it documents what IS, not what SHOULD BE
- **Replace human review** — generated docs should be reviewed by a human who
  knows the codebase before being treated as authoritative
- **Automatic doc rewriting in CI** — only the structural *detector* belongs
  in CI (see above)
