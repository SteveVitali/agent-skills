---
id: refresh-agent-docs
description: Detect stale agent docs and regenerate them to match current code
inputs:
  - name: scope
    required: false
    description: "Directory path relative to repo root (default: '.' for the entire repo)."
  - name: deep
    required: false
    description: "When set, also perform semantic verification of behavioral claims against actual source code. Expensive (5-15 min, 200-500k tokens)."
---

# Refresh Agent Docs

Detect documentation drift between `AGENTS.md` / `agent_docs/` files and the
actual codebase, then surgically update stale references, regenerate severely
drifted sections, and produce new docs for uncovered packages.

This workflow is **manually triggered** — run it periodically after major
refactors, package restructurings, or whenever you suspect docs have drifted.

---

## Doc Authoring Guidelines

These guidelines govern ALL documentation produced by this workflow. Follow
them exactly when editing or generating any agent documentation. (The
`bootstrap-agent-docs` sibling skill references these same guidelines.)

### Standard Alignment

Generated docs conform to the **AGENTS.md open standard** (agents.md, stewarded
by the Agentic AI Foundation): plain Markdown, nested files per subproject,
**nearest-file-wins precedence** (agents read the closest AGENTS.md in the
directory tree). The length budgets below are not taste — they are mechanical:
Claude Code's guidance is that files beyond ~200 lines "consume more context
and reduce adherence", and OpenAI Codex concatenates the AGENTS.md chain
root-down with a **32 KiB default cap**, silently truncating anything beyond
it. Over-budget docs literally stop being read.

### Structural Rules

1. **AGENTS.md length** — a leaf/package AGENTS.md stays ~150 lines. A **monorepo
   root** AGENTS.md that must orient across several services may run up to ~250
   lines. Concise, scannable, structured either way.
2. **Standard section order:**
   - `# AGENTS.md — <Package Name>`
   - `## Purpose` (1-3 sentences)
   - `## Architecture` (if multi-component)
   - `## Key Files` (table: File | Lines | Purpose)
   - `## Build & Test` (exact commands)
   - `## Code Conventions` (stack-specific rules)
   - `## Critical Gotchas` (numbered, most dangerous first)
   - `## Terminology` (domain terms agents won't know)
   - `## Do` / `## Don't` (one line each, actionable)
3. **No prose paragraphs** — use tables, bullet lists, code blocks. Agents parse
   structure, not essays.
4. **Key Files tables** — columns: `File | Lines (approx) | Purpose (one sentence)`.
   Lines are approximate (`~2.4k`). Update when drift exceeds 30%.
5. **Source Layout trees** — ASCII `├──` format with brief annotations. Include
   file counts per directory in parentheses.
6. **Code Conventions** — concrete rules with CORRECT ✓ and WRONG ✗ examples.
7. **Test commands** — exact copy-pasteable invocations for the repo's build
   system (e.g. `make test`, `npm run test`, `bazel test //pkg:target`,
   `pytest tests/x`). Never "run the tests" without specifying how.

### Content Rules

1. **Reference actual paths** — always backtick-quote. Use paths relative to
   repo root.
2. **Build-target awareness** — document which build/test targets or commands
   apply to which packages, especially non-obvious or manually-managed ones.
3. **Critical gotchas first** — lead with the mistakes agents WILL make without
   guidance. These are the highest-ROI content.
4. **Serialization mappings in tables** — when the repo maps in-code names to
   wire/storage names (ORM column names, protobuf field numbers, DB short
   names, JSON keys), format as a table: `| code field | wire name | type |
   notes |`, and verify against the source annotations before documenting.
5. **No comments about being auto-generated** — docs should read as natural,
   authoritative references written by a knowledgeable engineer.
6. **Terminology section** — define domain-specific terms, abbreviations, and
   acronyms that agents won't know from general training.
7. **Concrete enough to verify** — every instruction must be checkable:
   "run `npm test` before committing" not "test your changes"; "handlers live
   in `src/api/handlers/`" not "keep files organized". If you can't state how
   an agent would verify compliance, rewrite the instruction until you can.
8. **No contradictions across the hierarchy** — when two rules conflict
   (root vs nested AGENTS.md, or two sections of one doc), agents pick one
   arbitrarily. Every edit must leave the hierarchy consistent; resolve
   conflicts in favor of the more specific (nearest) doc and delete or scope
   the loser.

### Stack-Specific Rules

Do not apply a fixed per-language rulebook — derive one from the repo itself.
For each language/framework in scope, extract and document the rules that
would silently break an agent's work:

- **Compiler/linter strictness** — flags that turn warnings into errors
  (unused imports, non-exhaustive matches, implicit any), import-ordering
  rules, naming rules enforced by tooling.
- **Generated-file policies** — build files, lockfiles, codegen output: what
  must never be hand-edited, and what command regenerates it.
- **Framework conventions** — where each kind of file lives, the established
  data-flow/state patterns, routing/registration steps that are easy to miss.
- **Serialization/persistence mappings** — verify against source annotations;
  include a "last verified" date at the top of any mapping table.
- **Shell/config** — expected environment variables, version compatibility
  floors (e.g. bash 3.2 on macOS), usage examples with actual invocations.

Derive these from linter/formatter/compiler configs, CI config, and existing
docs — never from assumption.

### Regeneration Rules

1. **Surgical edits** — don't rewrite an entire doc for one stale reference.
   Fix the specific issue and preserve surrounding context.
2. **Full rewrite threshold** — if >40% of a doc's file references are broken,
   regenerate the doc from scratch by reading actual source files.
3. **New package docs** — generate minimal AGENTS.md (Purpose, Key Files, Test
   Command) from source inspection. Don't over-document on first pass.
4. **Preserve human voice** — if a doc has clearly human-authored explanations
   (architecture rationale, historical context, design decisions), preserve
   those sections. Only update factual references (paths, counts, names).
5. **Line count updates** — when updating, use `wc -l` to get actual counts.
   Round to nearest 50 for files <1000 lines, nearest 100 for larger files.
   Use `~` prefix (e.g., `~2.4k lines`).

---

## Steps

### 1 — Determine scope

Use the user-provided scope, or default to `.` (the entire repo).
Valid scopes: any directory path relative to repo root.

### 2 — Run staleness detection

// turbo
```bash
bash scripts/check-agent-docs-freshness.sh <scope>
```

(The script lives in this skill's `scripts/` directory; run it from the repo
root, or pass the repo root as its working directory.)

### 3 — Review the report

Read the summary printed to stdout. If 0 issues found, report
"All agent docs are fresh within scope `<scope>`" and stop.

If issues exist, read `/tmp/agent-docs-freshness.json` for the full structured
list. Categorize the work needed:
- **Critical issues** — fix immediately (broken references mislead agents)
- **Moderate issues** — fix if clearly stale; use judgment on borderline cases
- **Minor issues** — address coverage gaps only for packages with ≥5 source files

Missing references carry a git-history classification tag:
- **`[went stale: …]`** — the file existed when the doc was last edited and
  has since moved/been renamed/deleted. Trace where it went (`git log --follow`,
  search for the basename) and update the reference to the successor.
- **`[authoring error: …]`** — the reference never matched a real file even
  when written. Don't hunt for a successor; verify what the doc *meant* against
  the actual source and rewrite or remove the claim.

### 4 — Fix critical issues

For each critical issue in the report:

1. Read the affected doc file at the referenced line
2. Read the actual source file(s) to understand current state
3. Determine what changed (file moved? renamed? deleted? restructured?)
4. Make a **targeted edit** following the Doc Authoring Guidelines above
5. If a file was deleted and the reference is no longer relevant, remove
   the reference entirely rather than pointing to nothing

### 5 — Fix moderate issues

For each moderate issue:

1. Read the affected doc section in context
2. Determine if the drift is meaningful (does it actually mislead an agent?)
3. If yes: fix using the same approach as critical issues
4. If borderline: leave as-is unless the fix is trivial

For **line count drift**: update the documented count using `wc -l` on the
actual file. Follow the rounding rules in the Regeneration Rules above.

For **serialization mapping mismatches**: read the actual source annotations
(ORM/BSON/JSON/proto definitions), verify the correct wire name, and update
the table.

### 6 — Address coverage gaps (minor issues)

For packages with ≥5 source files and no AGENTS.md:

1. List all source files in the package
2. Read the first 30-50 lines of each (module declaration, imports, type
   definitions, doc comments)
3. Generate a minimal AGENTS.md following this template:

```markdown
# AGENTS.md — <Package Name>

## Purpose

<1-2 sentences describing what this package does>

## Key Files

| File | Lines | Purpose |
|---|---|---|
| `FileName.ext` | ~N lines | One-sentence description |

## Test Command

\`\`\`bash
<exact copy-pasteable test invocation for this package>
\`\`\`
```

Only generate docs for packages where the purpose would be non-obvious to an
agent reading the code cold.

### 7 — Handle severely drifted docs

If any single doc has >40% of its file references broken (as reported in the
freshness check), perform a **full rewrite**:

1. Read ALL source files in the documented package
2. Regenerate the entire doc following the standard section order from the
   Doc Authoring Guidelines
3. Preserve any "Architecture" or "Design Decisions" sections that contain
   rationale (these age differently — they explain WHY, not WHAT)
4. Re-verify all paths and counts against the actual filesystem

### 8 — Validate

Re-run the detection script to confirm fixes resolved the issues:

// turbo
```bash
bash scripts/check-agent-docs-freshness.sh <scope>
```

- If critical issues = 0: proceed to the consistency sweep
- If critical issues remain: iterate (max 2 additional attempts)
- If still failing after 3 total attempts: report remaining issues to the user

**Consistency sweep** (touched docs only): re-read every doc this run edited
plus its parent AGENTS.md, checking for rules that now contradict each other
(build commands that differ, conventions stated one way at the root and
another way in a nested doc, gotchas that a fix made obsolete). Contradicting
instructions cause agents to pick one arbitrarily — resolve per the
no-contradictions rule in the Doc Authoring Guidelines.

### 9 — Commit

Review `git status` and stage only the doc files this run touched (exclude
agent-harness dirs like `.windsurf/`, `.claude/`, `.cursor/`):

```bash
git add <the doc files you changed>
git commit -m "docs: refresh agent docs — N issues fixed

Scope: <scope>
Critical: X fixed | Moderate: Y fixed | Minor: Z fixed
"
```

---

## Deep Semantic Verification (--deep)

**Only execute this phase if the user passed `--deep`.** Skip entirely otherwise.

This phase verifies that behavioral claims in agent docs still accurately
describe what the code actually does. It catches drift that structural checks
miss — cases where files didn't move but their logic fundamentally changed.

**Cost:** 200-500k tokens, 5-15 min. Use after major behavioral refactors.

### D.1 — Extract semantic claims

For each agent doc in scope, identify all **behavioral claims** — sentences
that assert something about what code does, how components interact, or what
patterns are used. Ignore purely structural facts (file paths, line counts)
which are already covered by the structural checks.

Claim categories:
- **Behavioral**: "X does Y", "X handles Y", "X publishes to Y"
- **Dependency**: "A depends on B", "A calls B", "A extends B"
- **Flow**: "Pipeline flows from A → B → C", "Data goes through X then Y"
- **Pattern**: "Uses token bucket", "Follows interface+implementation pattern"
- **Constraint**: "Must be called before X", "Only works when Y"

For each claim, record:
- The doc file and line number
- The claim text (verbatim or paraphrased)
- The referenced source file(s) that should contain the evidence

### D.2 — Verify each claim against source

For each extracted claim:

1. **Locate the relevant source file(s)** — use the file references in the
   claim or the surrounding doc context to identify which source to read.

2. **Read the source** — read the relevant file(s), focusing on:
   - Type/class/module definitions
   - Function signatures and their implementations
   - Import statements (reveal actual dependencies)
   - Constructor/initializer parameters (reveal actual wiring)
   - For flow claims: trace the call chain across 2-3 hops max

3. **Rate the claim:**
   - ✅ **Confirmed** — source clearly supports this claim. The described
     behavior, dependency, or pattern is evident in the code.
   - ⚠️ **Uncertain** — can't confirm or deny without deeper analysis
     (e.g., behavior depends on runtime config, or the relevant code is
     in a different repo). Do NOT flag these as issues.
   - ❌ **Contradicted** — source clearly does something DIFFERENT than
     described. The claim is actively misleading.

4. **For ❌ contradicted claims only**, determine what the code actually does
   and prepare a corrective edit.

### D.3 — Judgment guidelines

Be CONSERVATIVE with ❌ ratings. Only flag a claim as contradicted when you
have clear evidence. Common scenarios:

**Flag as ❌ (contradicted):**
- Doc says "X publishes to the message queue" but X no longer imports or calls it
- Doc says "uses polling" but the code now uses event-driven callbacks
- Doc says "A calls B" but A no longer imports or references B
- Doc says "handles authentication" but the auth logic was moved elsewhere

**Do NOT flag (leave as ✅ or ⚠️):**
- Doc says "~2.4k lines" and file is now 2.8k (that's structural, not semantic)
- Doc uses slightly imprecise language but the gist is correct
- Doc describes a pattern that's still present but has been extended
- You can't find the relevant code (might be in a dep you didn't read)

### D.4 — Fix contradicted claims

For each ❌ claim:

1. Read the full context of the claim in the doc
2. Determine what the code ACTUALLY does now
3. Rewrite the claim to accurately describe current behavior
4. Follow the Doc Authoring Guidelines (concise, structured, no prose)

### D.5 — Report

After processing all claims, print a summary:

```
Semantic Verification — <scope>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Claims checked: N
  ✅ Confirmed: X
  ⚠️ Uncertain: Y (skipped)
  ❌ Contradicted: Z (fixed)
```

If Z > 0, the fixes were already applied in step D.4. Proceed to the
validation step (re-run the structural check to ensure the rewrites didn't
introduce new structural issues).

---

## Optional CI Integration

The structural detector is fast, deterministic, and exit-code-gated — suitable
as a PR check. Drift research (DOCER, EMSE 2023) found broken doc references in
~29% of the top-1000 GitHub repos, typically unnoticed *for years*, precisely
because checking was manual; the same work ships a PR-triggered action because
catching drift at change time beats periodic sweeps. Recommended split:

- **In CI (structural only)**: run `check-agent-docs-freshness.sh <scope>` on
  PRs that touch source or docs; fail (or warn) on critical issues. No LLM
  involved — cheap and deterministic.
- **Manual (this workflow)**: the LLM-driven fixing, regeneration, and `--deep`
  semantic verification stay human-triggered.

## What This Workflow Does NOT Do
- **Convention drift detection** — if the team adopts new patterns, that requires
  human input to update "Code Conventions" sections.
- **Cross-repo knowledge** — data flows between services need a different
  mechanism (a cross-repo synthesis workflow, if you maintain one).
- **Automatic doc rewriting in CI** — only the structural *detector* belongs in
  CI (see above). The LLM refresh is manually triggered: run it when you suspect
  drift (after refactors, after merging large PRs, periodically).
