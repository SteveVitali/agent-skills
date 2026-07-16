---
id: bootstrap-agent-docs
description: Generate agent documentation from scratch for an undocumented codebase or subproject
inputs:
  - name: scope
    required: true
    description: "Directory path (absolute or relative to repo root) to bootstrap. Can target any repo."
  - name: depth
    required: false
    description: "Doc hierarchy depth: 'flat' (single AGENTS.md), 'hierarchical' (root + subproject AGENTS.md files), or 'deep' (hierarchical + agent_docs/ reference library). Default: auto-detect based on repo size."
  - name: cross-repo
    required: false
    description: "When set, also generate integration surface documentation describing how this codebase connects to other documented repos."
---

# Bootstrap Agent Docs

Generate agent documentation from scratch for a codebase or subproject that has
no existing agent docs. This workflow produces publication-quality docs — the
kind an experienced engineer who knows the codebase would trust and maintain.

**When to use this vs. `refresh-agent-docs`:**
- **Bootstrap** = no docs exist yet (cold start)
- **Refresh** = docs exist but may have drifted from code

This workflow references the **Doc Authoring Guidelines** from the sibling
skill `refresh-agent-docs` (`skills/refresh-agent-docs/refresh-agent-docs.md`)
— all generated docs MUST conform to those guidelines, including the
**Standard Alignment** section (docs follow the AGENTS.md open standard:
nested files, nearest-file-wins precedence, and length budgets that exist
because agents mechanically truncate or under-weight over-budget docs). Read
the guidelines before proceeding.

---

## Steps

### 1 — Repo Reconnaissance

Systematically characterize the codebase before writing anything. Gather facts,
don't interpret yet.

#### 1.1 — Build System Detection

Identify the primary build system and its implications:

| Indicator | Build System | Key Implications |
|---|---|---|
| `BUILD`, `WORKSPACE`, `MODULE.bazel` | Bazel | BUILD files may be auto-generated (e.g. Gazelle); check before editing manually |
| `package.json` (root) | npm/yarn/pnpm | Check for workspaces (monorepo) |
| `turbo.json` | Turborepo | Monorepo with task pipelines |
| `lerna.json` | Lerna | Multi-package monorepo |
| `Gemfile` | Bundler (Ruby) | Check for Rails (`bin/rails`) |
| `pom.xml` / `build.gradle` | Maven/Gradle | Java/Kotlin ecosystem |
| `Cargo.toml` | Cargo (Rust) | Check for workspace members |
| `go.mod` | Go modules | Check for multi-module layout |
| `Makefile` | Make | Read targets for build/test commands |
| `Dockerfile` / `docker-compose.yml` | Docker | Containerized services |

Record:
- Build command(s) for the main artifact
- Test command(s) — both "all tests" and "single file/package"
- Lint/format commands
- Any code generation steps (proto compilation, BUILD-file generation, codegen scripts)

#### 1.2 — Language & Framework Identification

For each language present, note:
- Version constraints (e.g., a pinned language version in the manifest, `"target": "es2022"` in tsconfig)
- Framework and version (e.g. Rails 7, React 18, Spring Boot 3)
- Package manager and lockfile format

#### 1.3 — Entry Point Mapping

Find the main entry points — these orient agents to "where does execution start":
- Server entry points (`main`, `App.*`, `app.*`, `index.*`)
- Route/controller definitions (API surface)
- Configuration loading (how config flows in)
- CLI commands or scripts

#### 1.4 — Module/Package Enumeration

List top-level modules or packages. For each, note:
- Name and approximate size (file count)
- Primary responsibility (1 sentence)
- Whether it's actively developed or legacy/stable

#### 1.5 — Test Infrastructure

Identify:
- Test framework(s): e.g. JUnit, RSpec, Jest, Vitest, pytest, go test
- Test location convention: co-located (`__tests__/`), mirrored (`src/test/`), or mixed
- How to run a single test file
- Any test helpers, factories, or fixtures agents need to know about
- CI test commands (may differ from local)

---

### 2 — Gotcha & Convention Discovery Protocol

This is the highest-ROI step. The goal is to identify everything that will
**silently break an agent's work** or cause wasted iterations. Mine these
sources systematically:

#### 2.1 — Linter & Formatter Configs

Read ALL of these if they exist:
- `.eslintrc*`, `eslint.config.*` — JS/TS rules
- `.rubocop.yml` — Ruby style enforcement
- `tsconfig.json` — strict mode, path aliases, target
- `.prettierrc*` — formatting rules
- `.editorconfig` — indentation, line endings
- Language formatter configs (`.scalafmt.conf`, `rustfmt.toml`, `.clang-format`, etc.)
- Compiler flags in build config (e.g., fatal-warnings flags, `strict: true`)

**What to extract:** Rules that are non-obvious and would trip up an agent.
Skip obvious ones (semicolons, quotes). Focus on:
- Fatal warnings / errors-as-warnings
- Import ordering requirements
- Naming conventions enforced by linting
- File/directory naming patterns
- Max line length or complexity rules that affect code structure

#### 2.2 — CI Pipeline Analysis

Read CI configuration files:
- `Jenkinsfile` / `.github/workflows/*.yml` / `.circleci/config.yml` / `.gitlab-ci.yml`
- Pre-commit hooks (`.pre-commit-config.yaml`, `.husky/`)
- Git hooks in `.git/hooks/` or configured via the package manager

**What to extract:**
- Mandatory checks that MUST pass (what gates a merge?)
- Auto-formatting or auto-fixup steps (code that changes after commit)
- Build matrix (what environments/versions are tested?)
- Deployment triggers (what branches auto-deploy?)

#### 2.3 — Generated/Protected Files

Identify files agents must NEVER edit directly:
- Auto-generated files (generated build files, lockfiles, codegen output)
- Files with "DO NOT EDIT" headers
- Files regenerated by CI/CD
- Binary/compiled artifacts checked into the repo

Look for patterns:
- `.gitignore` entries that hint at generated directories
- Scripts named `generate-*`, `codegen-*`, `sync-*`
- Makefile targets named `generate`, `codegen`, `proto`

#### 2.4 — Dependency Constraints

Check for:
- Version pinning that would break if agents add deps at wrong versions
- Workspace protocols (npm workspaces, Bazel `deps`, Bundler groups, Cargo workspaces)
- Resolution overrides or patches
- Internal package references (monorepo cross-deps)
- Peer dependency requirements

#### 2.5 — Error Archaeology

Mine git history for recurring failure patterns:

```bash
# Recent fix commits (look for patterns in what keeps breaking)
git log --oneline --since="3 months ago" --grep="fix" -- <scope> | head -30

# CI fix commits specifically
git log --oneline --since="3 months ago" --grep="ci\|lint\|build\|type" -- <scope> | head -20

# Files that change most often (hotspots = complexity = gotchas)
git log --since="3 months ago" --name-only --pretty=format: -- <scope> | sort | uniq -c | sort -rn | head -20
```

**What to extract:** Patterns of breakage. If you see repeated fixes for the
same category (import ordering, type errors, build failures), that's a gotcha
worth documenting.

#### 2.6 — Implicit Conventions

Look for conventions not enforced by tooling but present in the code:
- File naming patterns (PascalCase components? kebab-case routes?)
- Directory organization (feature-based? layer-based?)
- Naming conventions (suffix patterns: `*Service`, `*Repository`, `*Controller`)
- Comment/TODO conventions
- Error handling patterns (do they throw? return Result types? use Either?)
- Logging patterns (structured? levels? what logger?)

Read 5-10 representative files across different areas to spot these.

#### 2.7 — Architectural Boundaries

Identify what an agent should NOT cross:
- Service boundaries (don't modify another service's internals)
- Shared code ownership (files that affect multiple consumers)
- Database migration safety (schema changes need special care)
- API contracts (breaking changes to public APIs)

---

### 3 — Hierarchy Design

Based on reconnaissance results, decide on documentation depth.

**Decision tree:**

```
Is it a monorepo with >3 distinct packages/services?
├── YES → "hierarchical" or "deep"
│   └── Does any single package have >20 source files with complex conventions?
│       ├── YES → "deep" (root AGENTS.md + subproject AGENTS.md + agent_docs/)
│       └── NO  → "hierarchical" (root AGENTS.md + subproject AGENTS.md files)
└── NO → "flat" (single AGENTS.md at root)
    └── Is it a library with >30 source files?
        ├── YES → Consider "hierarchical" anyway
        └── NO  → "flat" is fine
```

**If user specified `depth`, use that. Otherwise, treat the tree as guidance, not
a hard gate.** A single, well-structured root AGENTS.md is an acceptable **first
bootstrap pass** even for a repo the tree would classify as `hierarchical`/`deep`,
provided it stays within the root-doc length allowance (~250 lines) and uses the
Module Layout + Source Layout sections to cover each service. Splitting into
per-service sub-AGENTS.md (and, for the most complex module, `agent_docs/`) is
then a follow-up once the root doc outgrows that budget. Prefer shipping one
accurate root doc over blocking on a full hierarchy.

File placement:
- **flat**: `<scope>/AGENTS.md`
- **hierarchical**: `<scope>/AGENTS.md` + `<scope>/<subproject>/AGENTS.md` per major module
- **deep**: hierarchical + `<scope>/<primary-module>/agent_docs/*.md` for the most complex module

---

### 4 — Generate Documentation

Using facts gathered in Steps 1-2, generate docs following the **Doc Authoring
Guidelines** section of `refresh-agent-docs`. All structural rules, content
rules, stack-specific rules, and regeneration rules from that section apply
here.

#### 4.1 — Root AGENTS.md

Generate a root AGENTS.md with these sections (skip sections that don't apply):

```markdown
# AGENTS.md — <Repo/Project Name>

## Purpose

<1-3 sentences: what this codebase does and who uses it>

## Architecture

<Only if multi-component. Brief topology: services, how they connect>

## Module Layout

<Table or bullet list of top-level modules with one-line descriptions>

## Key Files

<Table: File | Lines (approx) | Purpose (one sentence). The handful of entry
points / high-traffic files an agent should read first. Required by the Doc
Authoring Guidelines' Structural Rules.>

## Build & Test

<Exact copy-pasteable commands. Include: build, test (all + single), lint, format>

## Code Conventions

<Rules extracted from Step 2.1 and 2.6. Use CORRECT/WRONG examples.>

## Critical Gotchas

<Numbered, most dangerous first. These come from Steps 2.2-2.5.
Format: bold one-line summary + brief explanation of WHY it's dangerous.>

## Terminology

<Domain terms agents won't know from general training>

## Do

<One-line actionable items>

## Don't

<One-line prohibitions — especially the non-obvious ones from gotcha discovery>

## Boundaries

<What's safe, what needs permission, what's forbidden>
```

Target length (see the shared length rule in the **Doc Authoring Guidelines**):
a leaf/package AGENTS.md stays ~150 lines; a **monorepo root** AGENTS.md that
must cover several services may run up to ~250 lines. Keep it concise and
scannable regardless.

#### 4.2 — Subproject AGENTS.md (hierarchical/deep only)

For each significant subproject, generate a focused AGENTS.md with:
- Purpose (1-2 sentences, in context of the parent)
- Key Files table
- Build & Test (specific targets for this subproject)
- Code Conventions (only those specific to this subproject, not covered by root)
- Critical Gotchas (subproject-specific)
- Source Layout (ASCII tree)

Target: ~80-150 lines each.

#### 4.3 — Deep Reference Docs (deep only)

For the primary development area, generate `agent_docs/` with files like:
- `architecture_overview.md` — service topology, data flow
- `build_and_test.md` — all targets, CI details
- `common_pitfalls.md` — expanded gotchas with full context and examples
- Additional files as needed per domain (models, API patterns, etc.)

Target: each file 50-150 lines, focused on ONE topic.

**Claude Code alternative:** when the repo's primary agent harness is Claude
Code, topic docs can instead go in `.claude/rules/*.md` with `paths:` glob
frontmatter — each rule file then loads into context *only* when the agent
touches matching files, instead of costing tokens every session. Use
`agent_docs/` for harness-agnostic reference material and `.claude/rules/`
for path-scoped rules; don't duplicate content across both.

#### 4.4 — CLAUDE.md bridge (default)

Claude Code reads `CLAUDE.md`, not `AGENTS.md` — without a bridge, everything
generated above is invisible to it. Unless the user opts out or the repo
already has a `CLAUDE.md`, generate one at the repo root containing:

```markdown
@AGENTS.md
```

plus (only if needed) Claude Code-specific notes below the import: settings,
permissions, hook expectations. Keep it to the import line if there is nothing
Claude-specific to add — the point is one source of truth in AGENTS.md, shared
across harnesses.

---

### 5 — Validate

After generating all docs, run the freshness evaluator (shipped with the
sibling `refresh-agent-docs` skill) to confirm zero issues:

```bash
bash <skills>/refresh-agent-docs/scripts/check-agent-docs-freshness.sh <scope>
```

If the evaluator reports issues (which would indicate the bootstrap generated
broken references), fix them immediately. This should produce 0 critical issues
on a fresh bootstrap — if it doesn't, something was generated from assumption
rather than verification.

Additionally, manually verify:
- Every build/test command is copy-pasteable and valid
- Every file path in backticks actually exists
- Every line count uses `wc -l` and follows rounding rules from the refresh workflow
- No "prose paragraphs" — only tables, bullets, code blocks

---

### 6 — Cross-Repo Integration Surface (--cross-repo)

**Only execute if user passed `--cross-repo`.** Skip entirely otherwise.

When a bootstrapped codebase interacts with other repos that already have agent
docs, document the integration boundaries:

#### 6.1 — Identify touchpoints

For each documented external repo:
- API calls made TO that repo (endpoints, contracts)
- API calls received FROM that repo
- Shared data formats (protobuf schemas, JSON contracts, DB tables)
- Shared packages/libraries consumed
- Deployment dependencies (must deploy X before Y)

#### 6.2 — Generate integration section

Add a `## Integration Surface` section to the root AGENTS.md:

```markdown
## Integration Surface

| External Repo | Relationship | Key Contract | Notes |
|---|---|---|---|
| `repo-name` | Consumes API | `POST /v1/endpoint` | Auth via OAuth token |
| `other-repo` | Provides package | `@org/package-name@^1.x` | Pin to major version |
```

#### 6.3 — Cross-reference

If the external repo's AGENTS.md doesn't mention this codebase, note that as a
follow-up action (but don't modify the external repo in this workflow run).

---

## What This Workflow Does NOT Do

- **Refresh existing docs** — use `refresh-agent-docs` for that
- **Generate API documentation** — this produces agent orientation docs, not
  user-facing API docs
- **Set up CI integration** — docs are manually triggered for now
- **Make architectural decisions** — it documents what IS, not what SHOULD BE
- **Replace human review** — generated docs should be reviewed by a human who
  knows the codebase before being treated as authoritative

---

## Quality Checklist

Before committing bootstrapped docs, verify:

- [ ] Every command in "Build & Test" actually works when copy-pasted
- [ ] Critical Gotchas are genuinely non-obvious (not just "follow the style guide")
- [ ] No section is generic filler — every line earns its place
- [ ] File paths are verified against the filesystem (use `ls` / `find`)
- [ ] Line counts use actual `wc -l` values with proper rounding
- [ ] The doc reads as if written by a knowledgeable engineer, not a template
- [ ] An agent reading this doc cold could start productive work within 1 task
