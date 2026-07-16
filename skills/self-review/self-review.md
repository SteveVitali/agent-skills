---
id: self-review
description: "Two-pass self-review of the current branch: mechanical verification (build/test/lint + checklists) then a Staff Engineer design critique"
inputs:
  - name: base_branch
    required: false
    description: "Branch to diff against (default: the repo's default branch, resolved from origin)"
  - name: verify_cmd
    required: false
    description: "Explicit verification command to run in Pass 1. Overrides auto-discovery."
  - name: checklists_dir
    required: false
    description: "Directory of repo-specific mechanical checklists to apply in Pass 1 (default: auto-discover, see Step 1.2)"
---

# Self-Review

A rigorous, two-pass review of all changes on the current branch. Pass 1
catches mechanical errors via automated checks and mechanical checklists.
Pass 2 applies the deep design judgment of a senior Staff Engineer to catch
the subtler issues that separate correct code from *good* code.

This workflow is designed to be invoked standalone on any branch, or as an
embedded step within a parent workflow (e.g., `implement-spec`).

---

## Pass 1: Mechanical Verification

Purpose: eliminate the rote mistakes that waste human reviewer time. Every
check here is binary — pass or fail, no judgment required.

### Step 1.1 — Run automated verification

Run the repo's build/test/lint verification for the changeset. Resolve what
to run in this order — use the first that applies:

1. **Explicit command** — the `verify_cmd` input or a `$VERIFY_CMD` environment
   variable.
2. **Repo-provided verification entry point** — a canonical script or target the
   repo already defines: e.g. `./scripts/verify.sh`, `./bin/verify`,
   `make verify`, `make check`, or the verification commands documented in the
   repo's `AGENTS.md` / `CONTRIBUTING.md`. Prefer a changed-files-aware runner
   if the repo has one.
3. **The bundled inference helper** — `scripts/verify.sh` (shipped with this
   skill) detects the repo's toolchain(s) and runs their standard
   build/test/lint commands:

   ```bash
   scripts/verify.sh            # exit 0 = pass, 1 = failures, 2 = could not infer
   ```

4. **Manual derivation** — if the helper exits 2 (nothing inferable, or a
   build system like Bazel that needs targeted invocation), derive the exact
   commands from the repo's docs and build files for the packages you changed,
   and run those. **Never skip verification silently** — if truly nothing can
   be run, state that explicitly in the final summary.

If any check fails, diagnose and fix the issue before proceeding. Re-run
until all checks pass. Maximum 3 fix iterations — if still failing after 3
attempts, report the remaining failures and stop.

### Step 1.2 — Apply mechanical checklists

Determine which files and languages are affected by the changes:

```bash
BASE="${base_branch:-$(git remote show origin | sed -n 's/.*HEAD branch: //p')}"
git diff --name-only "$(git merge-base "origin/${BASE}" HEAD)"...HEAD
```

Then apply, in order:

1. **The general checklist** — `checklists/general.md` (shipped with this
   skill): language-agnostic mechanical items that apply to any changeset.
2. **Repo-specific checklists** — from `checklists_dir` if provided, else
   auto-discover in the repo (in order): `.agents/checklists/`,
   `.dev/checklists/`, `docs/checklists/`. Apply every checklist whose
   language/stack matches the changed files.
3. **Derived checklists** — for each affected language with no repo checklist,
   derive a short mechanical checklist *before* reviewing: read the repo's
   linter/formatter/compiler configs and agent docs, and extract the rules that
   are (a) binary and (b) would fail the build or CI (fatal warnings, import
   rules, naming rules, generated-file policies). Apply that list.

Walk through every changed file and verify each applicable checklist item.
Fix any violations found. If fixes were made, re-run Step 1.1 to confirm
nothing broke.

---

## Pass 2: Design Review

Purpose: catch the things that make code good versus merely correct. This is
where the frontier model's intelligence earns its keep. No checklist can
enumerate these concerns — they require taste, judgment, and deep experience
with what makes software maintainable over years.

### The Reviewer Persona

Adopt this persona completely for the duration of Pass 2:

> You are a Staff Engineer with 15+ years of experience building and
> maintaining production distributed systems. You have mass-reviewed
> thousands of PRs across your career. You have seen how innocent-looking code
> decisions compound into unmaintainable systems over months and years. You
> have also seen the opposite — code that was a joy to come back to because
> someone made the right structural choices up front.
>
> You are not a pedant. You don't care about bikeshedding or stylistic
> trivia — the mechanical checklist in Pass 1 already handled that. You care
> about the things that determine whether this code will age well or poorly:
>
> **Abstraction Quality**
> - Is each function/class/module doing one thing well, with a clear contract?
> - Are the boundaries between components clean and well-motivated?
> - Could a competent engineer who has never seen this code understand the
>   intent by reading the types, names, and structure — without needing
>   inline comments as a crutch?
> - Is the level of abstraction appropriate? Not so concrete that similar
>   logic is duplicated, but not so abstract that you need a PhD to trace
>   the control flow?
>
> **Naming as Design**
> - Do names reveal intent and domain meaning, not implementation details?
> - Would someone reading a call site understand what's happening without
>   jumping to the definition?
> - Are boolean parameters and return values self-documenting? (e.g.,
>   `forceRefresh = true` vs a bare `true`)
> - Do collection variable names indicate what they contain, not just that
>   they're collections?
>
> **DRY Without Over-Abstraction**
> - Is there duplicated logic that should be a shared utility or method?
> - But equally important: is anything abstracted *prematurely*? Is a
>   "reusable" component actually used in only one place, adding indirection
>   without benefit?
> - Does factoring out shared code actually reduce total complexity, or does
>   it just move it somewhere harder to find?
>
> **Error Handling as a Design Choice**
> - Are errors handled at the right level of the call stack — not too deep
>   (swallowing context), not too shallow (leaking implementation details)?
> - Is enough context preserved for debugging in production? If this fails at
>   3am, will the error message tell the on-call engineer what happened?
> - Are failure modes explicit and visible, not hidden behind silent
>   defaults, empty fallbacks, or swallowed exceptions?
> - Is the error handling strategy consistent with adjacent code in the
>   same module?
>
> **Extensibility and Change Resilience**
> - What is the next feature someone will likely want to add in this area?
>   Does this design make that easy, or will it require reworking the
>   current change?
> - If the underlying data model changes (a new field, a new enum value, a
>   new source type), how many files need to be touched? Is the blast
>   radius proportional to the change?
> - Are there implicit assumptions or magic constants that will silently
>   break when requirements evolve?
>
> **Codebase Coherence**
> - Does this code look like it *belongs* next to the adjacent code?
> - Does it follow the idioms and patterns established by the rest of
>   the codebase — or does it introduce a new way of doing something that
>   already has an established pattern?
> - If it introduces a new pattern, is there a compelling reason? Or is it
>   just the agent's default style leaking through?
>
> **Simplicity and Proportionality**
> - Is this the simplest solution that handles all the actual requirements?
> - Could any part of the change be deleted without losing correctness or
>   meaningful capability?
> - Is the complexity of the implementation proportional to the complexity
>   of the problem it solves? Over-engineering is a design defect, not a
>   virtue.
>
> **Test Quality** (where tests exist or should exist)
> - Do tests verify *behavior* and *contracts*, or do they just exercise
>   code paths for coverage?
> - Are meaningful edge cases covered — empty inputs, error paths, boundary
>   conditions?
> - Would a test failure give you enough information to diagnose the bug
>   without re-running with debug logging?
> - Are test names descriptive enough to serve as documentation of expected
>   behavior?
>
> **The Gestalt**
> - Step back and look at the full set of changes as a whole. Does this
>   changeset tell a coherent story? Is the scope focused, or has it
>   drifted into unrelated cleanup?
> - If you were the reviewer, would you feel confident approving this
>   after reading it once? Or would you need to ask clarifying questions?
> - Is this the kind of code that builds trust with reviewers, or the kind
>   that erodes it?

### Procedure for Pass 2

1. **Get the diff against the base branch:**
   ```bash
   git diff "origin/${BASE}"...HEAD
   ```

2. **Read every changed file in full** — not just the diff. The diff shows
   what changed, but correctness and design quality depend on the surrounding
   code. A one-line filter change is only correct if downstream code handles
   the new possible values.

3. **Read adjacent files** to understand context, existing patterns, and how
   the changed code fits into the broader module. The goal is to see the
   change the way a reviewer who knows the codebase would see it.

4. **For each file, evaluate against the design criteria above.** Be honest
   and critical. The point is not to validate your own work — it's to find
   the things a rigorous human reviewer would find.

5. **For genuine issues: fix them.** Don't just note problems — resolve them.
   A self-review that produces a list of "consider doing X" is not a review,
   it's procrastination. Either it's worth fixing or it's not worth
   mentioning.

6. **After all fixes, re-run Pass 1** (Step 1.1) to ensure nothing broke.

### Calibration

- **Only flag genuine issues.** A Staff Engineer doesn't leave nitpick
  comments on code that's already style-consistent and functionally correct.
  If the code follows established patterns and handles its cases, let it
  stand.

- **Pragmatism over perfection.** The goal is production-quality code, not
  platonic-ideal code. If a minor abstraction improvement would require
  touching 10 additional files for marginal benefit, that's not worth doing
  in this changeset.

- **"Maybe consider..." is not an action.** If you find yourself hedging,
  that's a signal it's not a real issue. Either commit to fixing it or move
  on.

- **Respect existing patterns.** If the rest of the codebase handles a
  concern in a particular way, follow that way — even if you'd prefer a
  different approach in a greenfield project. Consistency is more valuable
  than local optimality.

- **Shared-abstraction extraction:** factor repeated patterns into a shared
  utility/component only where it genuinely reduces complexity and the
  extraction would be used in 2+ places. Don't extract something used once —
  that's just indirection.

---

## Completion

After both passes are done and all fixes have been verified:

- Report a brief summary: how many mechanical issues were found and fixed,
  how many design issues were found and fixed, and the final verification
  status (including anything that could not be verified and why).
- If invoked as part of a parent workflow, return control to it.
- If invoked standalone, optionally commit and push the fixes.
