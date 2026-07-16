# agent-skills

Rigorous engineering process for AI coding agents, packaged as portable
[Agent Skills](https://agentskills.io): implement a spec end to end to a
verified PR, review a branch with independent judgment, and keep AGENTS.md
docs converged with the code they describe.

- **Harness-agnostic** — standard `SKILL.md` directories. Claude Code, Codex,
  Cursor, Gemini CLI, GitHub Copilot, and a growing list of clients load them
  natively; anywhere else (Windsurf, Goose, a human with a terminal), a
  one-line pointer to the skill file works.
- **Codebase-agnostic** — no assumptions about your repo, language, or
  toolchain. Build/test/lint commands are discovered from the repo or passed
  as inputs, never hardcoded.
- **Research-grounded** — durable ledgers, fresh-context review,
  evidence-first reporting: the design decisions trace to the
  agent-engineering literature
  ([rationale](skills/implement-spec/README.md)).

## The flagship: `implement-spec`

Most agents can write plausible code from a spec. What they don't do reliably
is everything around that — hold the plan across a long horizon, test what
they wrote, catch where the implementation quietly diverges from the spec,
and prove the result rather than assert it. `implement-spec` packages that
discipline: hand it an agent-ready spec, and it runs the lifecycle
autonomously, surfacing only at the end.

```
spec ─▶ branch ─▶ plan + test matrix ─▶ implement (tests alongside)
     ─▶ two-pass self-review ─▶ gap analysis vs the spec ─▶ close gaps
     ─▶ live verification ─▶ PR + acceptance-criteria evidence report
```

- **Evidence over claims** — "done" means every acceptance criterion in the
  final report maps to a verifiable artifact (a test, a command's output, a
  live check) — not that the model says so.
- **Survives long horizons** — a durable run ledger on disk makes the run
  resumable across crashes and context compaction.
- **Proportional rigor** — every heavyweight phase (ledger, self-review, gap
  analysis, tests, live verification) is individually opt-out, so a one-line
  fix doesn't pay a ten-phase tax.

The full design rationale, with the literature behind each phase, is in
[skills/implement-spec/README.md](skills/implement-spec/README.md).

## The skills around it

Two more skills back `implement-spec` and stand alone:

### [`self-review`](skills/self-review/SKILL.md)

Two-pass review of the current branch — and `implement-spec`'s review phase.
Pass 1 is mechanical: auto-discovered build/test/lint (via
[`verify.sh`](skills/self-review/scripts/verify.sh), which infers the
toolchain when the repo doesn't declare one) plus binary
[checklists](skills/self-review/checklists/general.md). Pass 2 is design
critique under independence rules — fresh context where the harness supports
subagents, evidence-from-disk discipline where it doesn't — with a
demonstrability bar for every flag raised.

### [`agent-docs`](skills/agent-docs/SKILL.md)

Creates and maintains the knowledge layer the other skills run on: an
AGENTS.md-standard doc hierarchy an agent can trust cold. One workflow, two
modes — `bootstrap` generates docs from scratch (reconnaissance → gotcha
mining → generation), `refresh` detects and fixes drift. The mode is
auto-selected by a deterministic, CI-gateable
[drift detector](skills/agent-docs/scripts/check-agent-docs-freshness.sh)
that classifies broken references as *went stale* vs *authoring error* using
git history. Both modes share the
[Doc Authoring Guidelines](skills/agent-docs/guidelines.md).

## Install

**As a Claude Code plugin:**

```
/plugin marketplace add SteveVitali/agent-skills
/plugin install agent-skills@agent-skills
```

**Or by symlink**, for any client that discovers skills on disk
(`~/.claude/skills/`, a project's `.agents/skills/`, etc.):

```bash
git clone https://github.com/SteveVitali/agent-skills.git ~/agent-skills
ln -s ~/agent-skills/skills/* ~/.claude/skills/
```

**Clients without native skill support** (e.g. Windsurf): a one-line
workflow or rule pointing at the skill file is enough — *"Read and follow
`<path>/skills/implement-spec/SKILL.md`"*.

Each skill declares its inputs in `SKILL.md` frontmatter; state them in
natural language ("implement docs/spec.md, skip the ledger, base off main").
The only system requirements are `git`, `bash` 3.2+, and standard Unix tools.

## Repo layout

```
.claude-plugin/              # plugin + marketplace manifests (Claude Code)
skills/<skill-name>/
├── SKILL.md             # entry point (Agent Skills format: frontmatter + steps)
├── README.md            # design rationale (where it exists)
├── modes/               # mode-specific step files, loaded on demand (where applicable)
├── scripts/             # supporting shell helpers (bash 3.2+ compatible)
└── checklists/          # supporting checklists / shared reference docs (where applicable)
```

One predictable entry filename means an agent (or tool) pointed at `skills/`
knows where every skill starts; everything else in a skill directory is
progressive-disclosure material referenced from its `SKILL.md`.

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

1. Create `skills/<name>/SKILL.md` with frontmatter: `name`, `description`
   (what it does *and* when to use it), and `inputs` (each with `name`,
   `required`, `description`). Keep the body harness-neutral — no
   tool-specific directives in skill files.
2. Write instructions that are **concrete enough to verify** ("run X, expect
   exit 0"), and calibrated to a frontier model: specify *what* and *why*,
   not keystroke-level *how*.
3. If the skill nears the spec's ~500-line ceiling for `SKILL.md` or has
   distinct modes, split into a hub + `modes/` files (see `agent-docs`).
4. Shell helpers go in `scripts/`: bash 3.2-compatible, self-contained,
   read-only by default — anything mutating must say so in its header, and
   known limitations belong in the header too.
5. No assumptions about repo, language, or toolchain anywhere: discover from
   the repo or take it as an input.

## Related

- **[Agent Skills](https://agentskills.io/specification)** — the open format
  these skills conform to.
- **[anthropics/skills](https://github.com/anthropics/skills)** — Anthropic's
  reference collection; mostly *capability* skills (documents, design,
  testing tools).
- **[obra/superpowers](https://github.com/obra/superpowers)** — a full
  interactive development methodology (brainstorm → plan → subagent-driven
  TDD). Kindred spirit, different center of gravity: superpowers optimizes
  the human-in-the-loop workflow; agent-skills optimizes the autonomous run
  and its evidence trail.
- **[claude-hibernate](https://github.com/SteveVitali/claude-hibernate)** —
  hibernate running Claude Code sessions across reboots. Began in this repo;
  Claude Code-specific by nature, so it lives on its own.

## License

[MIT](LICENSE)
