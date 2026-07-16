# agent-skills

Reusable, research-grounded **skills** for AI coding agents.

Agent context files (`AGENTS.md`, `CLAUDE.md`) give an agent *knowledge*: what
a codebase is, its conventions, its gotchas. Skills give it *process*: how to
execute multi-step engineering work — implement a spec end to end, review its
own code with independent judgment, keep docs converged with reality — with
discipline that survives long horizons, context compaction, and model
self-bias.

Every skill here is:

- **Codebase-agnostic** — no company, repo, or language assumptions. Build and
  test commands are discovered from the repo or injected as inputs, never
  hardcoded.
- **Harness-agnostic** — plain Markdown plus portable shell (bash 3.2+). Works
  from Claude Code, Cursor, Windsurf/Cascade, Codex-style agents, or a human
  following the steps. (One deliberate exception: `claude-hibernate` is Claude
  Code-specific by nature.)
- **Research-grounded** — the design decisions (durable ledgers, fresh-context
  review, verification-first reporting) trace to the agent-engineering
  literature; see the [implement-spec design rationale](skills/implement-spec/README.md)
  for the synthesis and citations.

## The skills

| Skill | Harness | Purpose |
|---|---|---|
| [`implement-spec`](skills/implement-spec/implement-spec.md) | Any | The full SDLC on a spec: branch → plan + test matrix → implement → self-review → spec gap analysis → live verification → PR + evidence report |
| [`self-review`](skills/self-review/self-review.md) | Any | Two-pass review of the current branch: mechanical verification, then an independence-preserving design critique |
| [`agent-docs`](skills/agent-docs/agent-docs.md) | Any | Create (`bootstrap`) or converge (`refresh`) an AGENTS.md-standard doc hierarchy |
| [`claude-hibernate`](skills/claude-hibernate/claude-hibernate.md) | Claude Code | `hibernate` running sessions to disk before shutdown; `wake` them after reboot |

### implement-spec

Takes an agent-ready spec and runs the entire development lifecycle
autonomously, surfacing only at the end with a PR link and an
acceptance-criteria evidence report. Every rigor phase (gap analysis,
self-review, tests, live verification, run ledger) is individually opt-out via
inputs, so process weight scales with task weight. Its
[README](skills/implement-spec/README.md) documents the research behind each
phase.

### self-review

Pass 1 is mechanical: auto-discovered build/test/lint (via
[`verify.sh`](skills/self-review/scripts/verify.sh), which infers the
toolchain when the repo doesn't declare one) plus binary
[checklists](skills/self-review/checklists/general.md). Pass 2 is design
critique under independence rules — fresh context where the harness supports
subagents, evidence-from-disk discipline where it doesn't — with a
demonstrability bar for every flag raised. Used standalone or as
implement-spec's review phase.

### agent-docs

One workflow, two modes converging on the same target state — docs an agent
can trust cold. `bootstrap` generates a hierarchy from scratch (reconnaissance
→ gotcha mining → generation); `refresh` detects and fixes drift. The mode is
auto-selected by a deterministic, CI-gateable
[drift detector](skills/agent-docs/scripts/check-agent-docs-freshness.sh)
that classifies broken references as *went stale* vs *authoring error* using
git history. Both modes share the
[Doc Authoring Guidelines](skills/agent-docs/guidelines.md).

### claude-hibernate

OS-hibernation for Claude Code sessions: `hibernate` captures the
currently-running session set to a snapshot file, `wake` reopens each one
(iTerm2 pane grid, Terminal.app tabs, or printed commands) after reboot.
Claude Code-specific, repo-agnostic; wake automation is macOS-only.

## Quick start

Skills are Markdown programs for a capable agent: get the files, point your
harness at them, and state the inputs conversationally.

```bash
git clone https://github.com/<you>/agent-skills.git ~/agent-skills
# or vendor it: git submodule add <url> vendor/agent-skills
```

Then wire up a thin wrapper per harness — wrappers point, they don't copy:

**Claude Code** (slash command, `.claude/commands/implement-spec.md`):

```markdown
Read and follow ~/agent-skills/skills/implement-spec/implement-spec.md.
Inputs: $ARGUMENTS
```

**Claude Code** (skill, `~/.claude/skills/implement-spec/SKILL.md`):

```markdown
---
name: implement-spec
description: Spec-driven end-to-end implementation with rigorous verification
---
Read and follow ~/agent-skills/skills/implement-spec/implement-spec.md.
```

**Windsurf/Cascade** (workflow, `.windsurf/workflows/implement-spec.md`):

```markdown
---
description: Spec-driven end-to-end implementation with rigorous verification
---
Read and follow <path-to>/agent-skills/skills/implement-spec/implement-spec.md.
```

**Any other agent, or none:** paste
`Read ~/agent-skills/skills/self-review/self-review.md and execute it against
this branch` into the chat — or follow the steps yourself.

Inputs are declared in each skill's YAML frontmatter; pass them in natural
language ("implement docs/spec.md, skip the ledger, base off main").

## Repo layout

```
skills/<skill-name>/
├── <skill-name>.md      # the workflow hub (YAML frontmatter + Markdown steps)
├── README.md            # design rationale (where it exists)
├── modes/               # mode-specific step files, loaded on demand (where applicable)
├── scripts/             # supporting shell helpers (bash 3.2+ compatible)
└── checklists/          # supporting checklists / shared reference docs (where applicable)
```

## Design principles

- **Durable state over context** — anything that must survive compaction or a
  crash goes to disk (run ledgers, snapshots, reports), never only in context.
- **External verification over self-assessment** — compilers, tests, and live
  systems are the arbiters; an agent's claim of "done" without evidence is
  treated as not done.
- **Judgment independence** — review happens in a fresh context where
  possible, and always argues from what is on disk rather than memory of
  writing it.
- **Deterministic before LLM** — cheap, exit-code-gated scripts handle
  everything mechanical (drift detection, toolchain checks) so model judgment
  is spent only where judgment is required.
- **Progressive disclosure** — hub files stay small; mode files, guidelines,
  and checklists load only when needed.
- **Proportional rigor** — every heavyweight phase is opt-out, so a one-line
  fix doesn't pay a ten-phase tax.

## Authoring a new skill

1. Create `skills/<name>/<name>.md` with frontmatter: `id`, `description`,
   and `inputs` (each with `name`, `required`, `description`). Keep it
   harness-neutral — no tool-specific directives in the leaf files.
2. Write instructions that are **concrete enough to verify** ("run X, expect
   exit 0"), and calibrated to a frontier model: specify *what* and *why*,
   not keystroke-level *how*.
3. If the skill exceeds ~400 lines or has distinct modes, split into a hub +
   `modes/` files (see `agent-docs`).
4. Shell helpers go in `scripts/`: bash 3.2-compatible, self-contained,
   read-only by default — anything mutating must say so in its header, and
   known limitations belong in the header too.
5. No company, repo, or language assumptions anywhere: discover from the repo
   or take it as an input.

## Requirements

- `git`, `bash` 3.2+ (macOS system bash works), standard Unix tools
- `python3` for `claude-hibernate` and JSON handling in some helpers
- macOS for `claude-hibernate`'s wake automation (iTerm2/Terminal via
  `osascript`); everything else is OS-portable

## License

[MIT](LICENSE)
