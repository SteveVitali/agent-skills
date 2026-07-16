# Mode: refresh

Detect documentation drift between `AGENTS.md` / `agent_docs/` files and the
actual codebase, then surgically update stale references, regenerate severely
drifted sections, and produce new docs for uncovered packages.

Invoked from `agent-docs.md` Phase 1 with the drift report from Phase 0
already in hand (`/tmp/agent-docs-freshness.json`). All edits MUST conform to
the [Doc Authoring Guidelines](../guidelines.md). On completion, return to
the shared tail (`agent-docs.md` Phase 2).

Run this mode periodically after major refactors, package restructurings, or
whenever you suspect docs have drifted.

---

## R.1 — Triage the report

Read the summary printed to stdout by the Phase 0 detector run. If 0 issues
found, report "All agent docs are fresh within scope `<scope>`" — then skip
directly to the `--deep` phase if requested, or return to the shared tail.

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

## R.2 — Fix critical issues

For each critical issue in the report:

1. Read the affected doc file at the referenced line
2. Read the actual source file(s) to understand current state
3. Determine what changed (file moved? renamed? deleted? restructured?)
4. Make a **targeted edit** following the Doc Authoring Guidelines
5. If a file was deleted and the reference is no longer relevant, remove
   the reference entirely rather than pointing to nothing

## R.3 — Fix moderate issues

For each moderate issue:

1. Read the affected doc section in context
2. Determine if the drift is meaningful (does it actually mislead an agent?)
3. If yes: fix using the same approach as critical issues
4. If borderline: leave as-is unless the fix is trivial

For **line count drift**: update the documented count using `wc -l` on the
actual file. Follow the rounding rules in the Regeneration Rules.

For **serialization mapping mismatches**: read the actual source annotations
(ORM/BSON/JSON/proto definitions), verify the correct wire name, and update
the table.

## R.4 — Address coverage gaps (minor issues)

For packages with ≥5 source files and no AGENTS.md: this is a scoped
mini-bootstrap. Generate a minimal AGENTS.md per
[bootstrap §B.4.3](bootstrap.md) — source inspection first, minimal template,
and only for packages whose purpose would be non-obvious to an agent reading
the code cold.

## R.5 — Handle severely drifted docs

If any single doc has >40% of its file references broken (as reported in the
freshness check), the doc has crossed the full-rewrite threshold
(Regeneration Rule 2) — regenerate it with bootstrap's machinery instead of
patching:

1. Read ALL source files in the documented package
2. Regenerate the entire doc using the appropriate template from
   [bootstrap §B.4](bootstrap.md) (root, subproject, or minimal) and the
   standard section order from the Doc Authoring Guidelines
3. Preserve any "Architecture" or "Design Decisions" sections that contain
   rationale (these age differently — they explain WHY, not WHAT)
4. Re-verify all paths and counts against the actual filesystem

---

## R.D — Deep Semantic Verification (--deep)

**Only execute this phase if the user passed `--deep`.** Skip entirely otherwise.

This phase verifies that behavioral claims in agent docs still accurately
describe what the code actually does. It catches drift that structural checks
miss — cases where files didn't move but their logic fundamentally changed.

**Cost:** 200-500k tokens, 5-15 min. Use after major behavioral refactors.

### R.D.1 — Extract semantic claims

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

### R.D.2 — Verify each claim against source

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

### R.D.3 — Judgment guidelines

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

### R.D.4 — Fix contradicted claims

For each ❌ claim:

1. Read the full context of the claim in the doc
2. Determine what the code ACTUALLY does now
3. Rewrite the claim to accurately describe current behavior
4. Follow the Doc Authoring Guidelines (concise, structured, no prose)

### R.D.5 — Report

After processing all claims, print a summary:

```
Semantic Verification — <scope>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Claims checked: N
  ✅ Confirmed: X
  ⚠️ Uncertain: Y (skipped)
  ❌ Contradicted: Z (fixed)
```

If Z > 0, the fixes were already applied in R.D.4. The shared tail's
validation step will confirm the rewrites didn't introduce new structural
issues.

---

**Done.** Return to `agent-docs.md` Phase 2 (validate → consistency sweep →
CLAUDE.md bridge → quality checklist → commit).
