# agent-skills

Reusable, research-grounded skills for AI coding agents. Every skill here is
**codebase-agnostic** (no company/repo/language assumptions) and
**harness-agnostic** (plain Markdown workflows + POSIX-ish shell helpers,
usable from Claude Code, Cascade/Windsurf, Cursor, Codex-style agents, or by a
human following the steps).

## Skills

| Skill | What it does |
|---|---|
| [`implement-spec`](skills/implement-spec/implement-spec.md) | The full SDLC in one autonomous run: spec in → branch, plan, implement, test, two-pass review, spec gap analysis, live verification → PR + acceptance-criteria evidence report out. Configurable opt-outs per rigor phase. See its [README](skills/implement-spec/README.md) for the design rationale and literature. |
| [`self-review`](skills/self-review/self-review.md) | Two-pass review of the current branch: mechanical verification (auto-discovered build/test/lint + checklists) then an independence-preserving design critique. Ships a toolchain-inference [`verify.sh`](skills/self-review/scripts/verify.sh) and a language-agnostic [checklist](skills/self-review/checklists/general.md). |
| [`bootstrap-agent-docs`](skills/bootstrap-agent-docs/bootstrap-agent-docs.md) | Generate AGENTS.md-standard agent docs from scratch for an undocumented codebase: reconnaissance → gotcha mining → hierarchy design → generation → validation. |
| [`refresh-agent-docs`](skills/refresh-agent-docs/refresh-agent-docs.md) | Detect and fix agent-doc drift: a deterministic structural checker ([`check-agent-docs-freshness.sh`](skills/refresh-agent-docs/scripts/check-agent-docs-freshness.sh), CI-gateable, with git-history stale-vs-authoring-error classification) plus LLM-driven surgical fixes and optional `--deep` semantic verification. Also owns the shared **Doc Authoring Guidelines**. |
| [`claude-sessions`](skills/claude-sessions/claude-sessions.md) | Snapshot running Claude Code sessions before shutdown; restore them (iTerm2 pane grid / Terminal tabs) after reboot. The one harness-specific tool here — Claude Code only, but repo-agnostic. |

## Layout

```
skills/<skill-name>/
├── <skill-name>.md      # the workflow (YAML frontmatter + Markdown steps)
├── README.md            # design rationale (where it exists)
├── scripts/             # supporting shell helpers (bash 3.2+ compatible)
└── checklists/          # supporting checklists (where applicable)
```

## Conventions

- **Frontmatter**: `id`, `description`, and optional `inputs` — deliberately
  harness-neutral. Adapt to your harness's skill/workflow discovery as needed
  (e.g., symlink or import from `CLAUDE.md` / `.windsurf/workflows/`).
- **Scripts** are self-contained, macOS system-bash compatible, and safe to
  run read-only by default; anything mutating says so.
- **Repo bindings** are the adapter layer: each skill documents what to
  re-point when dropping it into a new repo (verification entry points,
  scratch locations, doc hierarchies).
