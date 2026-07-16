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
| [`agent-docs`](skills/agent-docs/agent-docs.md) | Create or converge AGENTS.md-standard agent docs, one workflow with two modes sharing a common validation/commit tail: [`bootstrap`](skills/agent-docs/modes/bootstrap.md) (reconnaissance → gotcha mining → hierarchy design → generation) and [`refresh`](skills/agent-docs/modes/refresh.md) (drift triage → surgical fixes → optional `--deep` semantic verification). Mode auto-detected via a deterministic structural checker ([`check-agent-docs-freshness.sh`](skills/agent-docs/scripts/check-agent-docs-freshness.sh), CI-gateable, with git-history stale-vs-authoring-error classification). Owns the shared [Doc Authoring Guidelines](skills/agent-docs/guidelines.md). |
| [`claude-hibernate`](skills/claude-hibernate/claude-hibernate.md) | OS-hibernation for Claude Code sessions ([`claude-hibernate.sh`](skills/claude-hibernate/scripts/claude-hibernate.sh)), two modes: `hibernate` captures running sessions to a snapshot file before shutdown; `wake` reopens and resumes them (iTerm2 pane grid / Terminal tabs) after reboot. The one harness-specific tool here — Claude Code only, but repo-agnostic. |

## Layout

```
skills/<skill-name>/
├── <skill-name>.md      # the workflow hub (YAML frontmatter + Markdown steps)
├── README.md            # design rationale (where it exists)
├── modes/               # mode-specific step files, loaded on demand (where applicable)
├── scripts/             # supporting shell helpers (bash 3.2+ compatible)
└── checklists/          # supporting checklists / shared reference docs (where applicable)
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
