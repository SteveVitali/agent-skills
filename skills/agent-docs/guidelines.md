# Doc Authoring Guidelines

These guidelines govern ALL documentation produced by the `agent-docs`
workflow, in both bootstrap and refresh modes. Follow them exactly when
editing or generating any agent documentation.

## Standard Alignment

Generated docs conform to the **AGENTS.md open standard** (agents.md, stewarded
by the Agentic AI Foundation): plain Markdown, nested files per subproject,
**nearest-file-wins precedence** (agents read the closest AGENTS.md in the
directory tree). The length budgets below are not taste — they are mechanical:
Claude Code's guidance is that files beyond ~200 lines "consume more context
and reduce adherence", and OpenAI Codex concatenates the AGENTS.md chain
root-down with a **32 KiB default cap**, silently truncating anything beyond
it. Over-budget docs literally stop being read.

## Structural Rules

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

## Content Rules

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

## Stack-Specific Rules

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

## Regeneration Rules

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
