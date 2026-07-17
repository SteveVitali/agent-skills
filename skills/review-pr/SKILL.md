---
name: review-pr
license: MIT
description: "Review someone else's GitHub PR as a Staff Engineer and post a high-precision review — mechanical grounding (CI, local verification), focused design + security passes, calibrated severity labels, inline comments with suggestion blocks. Use when asked to review a PR, give feedback on a PR, or act as a code reviewer."
compatibility: Requires the GitHub CLI (`gh`) authenticated with access to the PR's repository
inputs:
  - name: pr
    required: false
    description: "PR number, URL, or branch name (default: the open PR for the current branch)"
  - name: post
    required: false
    description: "Default true: submit the review to GitHub. When false, write the full review to a local report instead of posting."
  - name: max_comments
    required: false
    description: "Cap on inline comments, highest severity first (default: 10). Prevents alert fatigue on large PRs."
  - name: comment_prefix
    required: false
    description: "Prefix for every posted comment body, e.g. a bot identity like 'ReviewBot: ' (default: none)"
  - name: run_local_verification
    required: false
    description: "Default 'auto': check out and build/test the PR branch locally only when CI is absent or not green, and only if the working tree is clean. 'never' skips local execution (rely on CI); 'always' forces it. Running PR code executes untrusted code — use 'never' for PRs from untrusted authors unless sandboxed."
---

# Review PR

Review someone else's pull request and deliver the kind of review a rigorous
human Staff Engineer would: grounded in evidence, labeled by severity, and
quiet about everything that doesn't matter.

**The prime directive is precision over recall.** Developer trust in a
reviewer collapses non-linearly with false positives — a handful of wrong or
noisy comments and every future comment gets skimmed. A review that surfaces
three real issues beats one that surfaces three real issues buried in ten
speculative ones. When unsure whether an issue is real: it isn't. Drop it.

The governing standard (Google's, and ours): **favor approval once the PR
definitely improves the overall code health of the system, even if it isn't
perfect.** You are reviewing for "better", not "perfect".

---

## Phase 0 — Gather context

Run the bundled context fetcher from the repo root (read-only):

// turbo
```bash
bash scripts/fetch-pr-context.sh <pr>
```

It resolves the PR (argument, or the current branch's open PR), and writes:

- `/tmp/pr-context.json` — title, body, author, base/head refs, draft state,
  changed files with add/delete counts, CI check rollup
- `/tmp/pr-threads.json` — all existing review threads with resolution state

Then gather what the script can't:

1. **The diff**: `gh pr diff <number>` (or `git diff base...head` if checked
   out). Note which lines belong to diff hunks — GitHub rejects inline
   comments outside them.
2. **Intent**: read the PR title, description, and any linked issue
   (`Fixes #N` / `Closes #N` → `gh issue view N`). If the description is
   empty, reconstruct intent from the commit messages. You cannot judge
   "does this do what it intends, and is that good for this codebase?"
   without knowing the intent. If intent is genuinely unrecoverable, say so
   in the review summary and review what the code *does*.
3. **Repo standards**: read the repo's `AGENTS.md` / `CONTRIBUTING.md` /
   style or architecture docs for the touched areas. Comments grounded in
   the repo's own documented rules ("CONTRIBUTING.md requires X here")
   carry far more weight than generic best practices — prefer them.
4. **Existing feedback** (from `/tmp/pr-threads.json`): what other reviewers
   and bots have already said. Never re-raise a point that has already been
   made, resolved, or explicitly dismissed on this PR.

If the PR is a **draft**, note it: review for direction, don't nitpick
incompleteness the author already knows about.

## Phase 1 — Mechanical grounding

Deterministic signals first — they are ground truth the review anchors on,
and anything a machine already caught is not worth a comment.

1. **CI status**: from `statusCheckRollup` in the context file. Failing
   required checks are the first thing the summary should state — and
   redundant inline comments about what CI already flags are noise.
2. **Local verification** (per the `run_local_verification` input; default
   `auto` = only when CI is absent/inconclusive and the working tree is
   clean): `gh pr checkout <number>`, then resolve and run verification the
   same way the `self-review` skill's Step 1.1 does — explicit command →
   repo-provided entry point → the toolchain-inference helper
   (`../self-review/scripts/verify.sh`) → targeted derivation from repo
   docs. Record what ran and its result; restore the original branch after.
   **Security**: building/testing a PR executes its code. For PRs from
   untrusted authors, skip local execution unless sandboxed (`never`).
3. Note (don't yet judge) mechanical observations while reading: tests
   added/changed or absent, docs touched or not, generated files mixed with
   hand-written changes, diff size vs description scope.

## Phase 2 — Focused review passes

Read **every changed file in full**, not just the diff — a change is only
correct in the context of the code around it. For non-trivial changes, also
read the callers/consumers of changed public symbols (`grep` for them):
signature and behavior changes break code the diff never shows.

Then review in **separate focused passes** — a pass with one named concern
finds more than one diffuse read, and mixing security into a general pass
measurably dilutes both:

1. **Correctness & functionality** — does the code do what the PR says?
   Edge cases, error paths, concurrency, boundary conditions; will the tests
   fail if the behavior breaks?
2. **Design** — apply the Reviewer Standards from the `self-review` skill
   (read `../self-review/SKILL.md`, Pass 2: abstraction quality, naming,
   DRY vs over-abstraction, error handling, change resilience, codebase
   coherence, simplicity, test quality, the gestalt). Independence comes
   free here — you didn't write this code — but the demonstrability bar
   still applies in full.
3. **Security** — a dedicated pass over the diff: injection, authn/authz
   gaps, secrets in code or logs, unsafe deserialization, path traversal,
   SSRF, dependency changes. Scope it to what the change *touches*.
4. **Scope & completeness** — does the changeset tell one coherent story,
   or has unrelated refactoring/reformatting crept in? Is anything the spec
   or issue promised missing? Are docs that document the changed behavior
   updated?

## Phase 3 — Calibrate findings

For each candidate finding, apply these gates **in order** — a finding must
survive all of them:

1. **Demonstrability**: you can state the input/sequence that makes it fail,
   the contract or invariant it violates, or the concrete maintenance cost.
   If you cannot articulate the demonstration, the issue isn't real — drop
   it. (LLM reviewers are known to hallucinate plausible-sounding bugs.)
2. **Confidence**: would you stake your reputation on this comment being
   useful? If unsure whether it's a real problem in *this* codebase's
   context — drop it, or downgrade it to a genuine `question:`.
3. **Novelty**: not already flagged by CI, a linter, another reviewer, or a
   previous (even dismissed) thread on this PR.
4. **Materiality**: style points not in the repo's style guide are personal
   preference — never block on them; at most one `nit:`. Don't demand
   perfection beyond what the repo's own code demonstrates.

Label every surviving finding with severity:

| Label | Meaning |
|---|---|
| `blocking:` | Would make the codebase worse if merged — bug, security issue, broken contract, missing critical test. Must include the demonstration. |
| `important:` | Should be addressed, but reasonable people could sequence it differently (this PR or a fast-follow). |
| `nit:` | Worth doing, author may ignore. Polish only. |
| `question:` | A genuine question that materially affects the review — not a rhetorical device for a suggestion. |
| `praise:` | Something genuinely well done, when true — at most one or two; reviewers who only criticize train authors to dread review. |

Where a fix is small and concrete, embed a GitHub suggestion block so the
author can apply it in one click:

````markdown
```suggestion
<the corrected line(s), exactly as they should appear>
```
````

Sort by severity and enforce `max_comments` (default 10) — if the cap trims
anything above `nit`, say so in the summary ("N additional minor points
omitted").

## Phase 4 — Compose and submit

**Summary body** (the review's top-level comment), in order:

1. One-paragraph restatement of what the PR does — proof you understood it.
2. **Verdict** against the standard: does this improve overall code health?
3. **Evidence line**: what was verified and how (CI state, local build/test
   results, or "not verified — reviewed by reading only").
4. Count of findings by severity.

**Event type**: always `COMMENT`. An agent does not `APPROVE` (that is a
human's accountability) and does not `REQUEST_CHANGES` (a bot blocking merges
breeds resentment) — state the blocking findings in the summary and let
humans decide.

**Submit** (when `post` is true): build the payload and post it —

```bash
gh api repos/<owner>/<repo>/pulls/<number>/reviews --input /tmp/review-payload.json
```

with `/tmp/review-payload.json` shaped as:

```json
{
  "body": "<summary body>",
  "event": "COMMENT",
  "comments": [
    {"path": "src/file.py", "line": 42, "side": "RIGHT", "body": "blocking: <finding>"}
  ]
}
```

Every comment `line` must fall inside a diff hunk (use `start_line` +
`start_side` for multi-line comments). Apply `comment_prefix` to every body
if set. Omit the `comments` field entirely when there are none. If the API
rejects a comment for being outside a hunk, move that finding into the
summary body rather than dropping it.

When `post` is false: write the complete review (summary + findings with
paths/lines) to `/tmp/pr-review-report.md` and print it.

## Completion

Report: PR reviewed, verdict, findings posted by severity, what was verified
and what wasn't, and the review URL. Clean up temp files.

## What this skill does NOT do

- **Approve or block PRs** — it informs; humans gate.
- **Restyle the author's code to your taste** — the repo's conventions are
  the authority; absent a rule, the author's choice stands.
- **Review generated files line-by-line** — verify they're regenerated
  correctly (or flagged as stale), don't critique their contents.
- **Comment on what CI already reports** — machines don't need an echo.
