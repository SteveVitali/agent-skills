# agent-skills

Rigorous engineering process for AI coding agents, packaged as portable
[Agent Skills](https://agentskills.io): implement a spec end to end to a
verified PR, review code with independent judgment — your own branch, or
anyone's PR — work through review feedback like a professional author, and
keep documentation (agent-facing and human-facing) converged with the code
it describes.

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

Five more skills back `implement-spec` and stand alone:

| Skill | Purpose |
|---|---|
| [`self-review`](skills/self-review/SKILL.md) | Two-pass review of your own branch, pre-PR: mechanical verification, then independence-preserving design critique |
| [`review-pr`](skills/review-pr/SKILL.md) | Review someone else's PR: CI/verification grounding, focused design + security passes, calibrated severities, high-precision inline comments |
| [`address-pr-comments`](skills/address-pr-comments/SKILL.md) | Work through review feedback on your PR: triage every thread, fix or push back with evidence, reply with commit links |
| [`agent-docs`](skills/agent-docs/SKILL.md) | Bootstrap or refresh the AGENTS.md hierarchy — the agent-facing knowledge layer |
| [`refresh-repo-docs`](skills/refresh-repo-docs/SKILL.md) | Audit and sync human-facing docs (README, docs/, examples) against the code |

### The review suite

Three seats at the same table, sharing one epistemology — **every flag must
be demonstrable, and precision beats recall** (false positives are how
reviewers lose the room):

- [`self-review`](skills/self-review/SKILL.md) is the author pre-PR: Pass 1
  runs auto-discovered build/test/lint (via
  [`verify.sh`](skills/self-review/scripts/verify.sh), which infers the
  toolchain when the repo doesn't declare one) plus binary
  [checklists](skills/self-review/checklists/general.md); Pass 2 is design
  critique under independence rules — fresh context where the harness
  supports subagents, evidence-from-disk discipline where it doesn't. Also
  `implement-spec`'s review phase.
- [`review-pr`](skills/review-pr/SKILL.md) is the reviewer's seat: grounded
  in CI and (optionally) local verification, then separate focused passes
  for correctness, design, security, and scope; findings gated by
  demonstrability → confidence → novelty → materiality, labeled
  `blocking`/`important`/`nit`/`question`, capped to prevent alert fatigue,
  posted with suggestion blocks. It informs — approval stays human.
- [`address-pr-comments`](skills/address-pr-comments/SKILL.md) is the author
  answering: every unresolved thread gets a fix, a commit link, a reasoned
  push-back, an answer, or a scoped follow-up — never silence, never
  sycophancy, never a mid-review force-push.

### The docs pair

Same convergence philosophy, two corpora with different consumers and
quality bars — each with a deterministic, CI-gateable drift detector in
front of the LLM work:

- [`agent-docs`](skills/agent-docs/SKILL.md) owns the agent-facing knowledge
  layer (AGENTS.md hierarchy) the other skills run on. Two modes —
  `bootstrap` (reconnaissance → gotcha mining → generation) and `refresh`
  (drift triage → surgical fixes) — auto-selected by a
  [detector](skills/agent-docs/scripts/check-agent-docs-freshness.sh) that
  classifies broken references as *went stale* vs *authoring error* using
  git history. Owns the shared
  [Doc Authoring Guidelines](skills/agent-docs/guidelines.md).
- [`refresh-repo-docs`](skills/refresh-repo-docs/SKILL.md) owns what humans
  read: README, `docs/`, CHANGELOG, guides, examples. Its
  [detector](skills/refresh-repo-docs/scripts/check-repo-docs-freshness.sh)
  flags broken references and docs older than the code they cite; the audit
  is scoped by evidence (flagged docs, not "read the whole repo"), findings
  are classed stale/cruft/gap/mode-drift with Diátaxis as the per-doc
  quality lens, and no claim is written unverified.

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
System requirements: `git`, `bash` 3.2+, and standard Unix tools; the PR
skills (`review-pr`, `address-pr-comments`) additionally need an
authenticated [GitHub CLI](https://cli.github.com) (`gh`).

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
