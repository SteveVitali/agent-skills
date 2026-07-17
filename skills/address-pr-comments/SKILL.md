---
name: address-pr-comments
license: MIT
description: "Work through unresolved review comments on your PR as the author: triage every thread, implement fixes where the reviewer is right, push back with rationale where they aren't, answer questions, commit + push, and reply to every thread with what happened. Use when asked to address, respond to, or resolve PR review feedback."
compatibility: Requires the GitHub CLI (`gh`) authenticated with access to the PR's repository
inputs:
  - name: pr
    required: false
    description: "PR number, URL, or branch name (default: the open PR for the current branch)"
  - name: reply_only
    required: false
    description: "Default false. When true, make NO code changes — only triage and post replies (answers, rationale, status)."
  - name: push
    required: false
    description: "Default true: push fix commits and post replies. When false, commit locally and print the planned replies without posting."
  - name: resolve_threads
    required: false
    description: "Default false. When true, also mark threads you fixed as resolved. Leave false unless the repo's convention is author-resolves — many teams reserve resolution for the reviewer."
  - name: comment_prefix
    required: false
    description: "Prefix for every posted reply, e.g. a bot identity like 'ReviewBot: ' (default: none)"
---

# Address PR Comments

Take the author's seat on your own PR: every unresolved review thread gets
exactly one of five outcomes — a fix, a link to the commit that already fixed
it, a reasoned push-back, an answer, or a scoped follow-up. **A review
comment ends one of two ways: you applied it, or you explained why not.** A
thread left hanging tells the reviewer their time was wasted.

Two calibration rules frame everything below:

- **Reviewer comments are input, not commands.** Evaluate each on its merits
  with the same demonstrability bar you'd apply to your own findings. The
  failure mode of an agent in this seat is sycophancy — "fixing" things that
  aren't broken because someone asked. If the reviewer is wrong, a
  respectful, evidence-based reply *is* addressing the comment.
- **A misunderstanding is information about the code.** If a competent
  reviewer misread something, future readers will too. Prefer clarifying the
  code (rename, restructure, add a code comment) over explaining in the
  thread — the thread persuades one person once; the code persuades everyone
  forever.

---

## Phase 0 — Gather the threads

From the PR's branch (check it out if needed), sync first — replies will
reference commits, so the local branch must match the remote:

```bash
git pull --ff-only
```

Then run the bundled fetcher from the repo root (read-only):

// turbo
```bash
bash scripts/fetch-unresolved-threads.sh <pr>
```

It writes `/tmp/pr-unresolved-threads.json` — every **unresolved** thread
(path, line, full comment chain with authors and `databaseId`s) — plus
`/tmp/pr-meta.json` with the PR metadata, base branch, and your login.

Partition the unresolved threads:

- **Awaiting you**: last comment is not yours → these are the work queue.
- **Awaiting them**: last comment is yours → skip (re-running this skill
  must not double-reply; idempotency comes from this filter).

Include bot/agent threads (e.g. automated reviewers) — they're often the
easiest wins and ignoring them leaves visible dangling threads.

Also fetch the commit log for the branch (you'll need it in triage):

```bash
git log origin/<base>..HEAD --pretty=format:"COMMIT %H %s" --name-only
```

## Phase 1 — Triage every thread

Read each thread completely, then read the file it anchors to (the current
version — the comment may reference code that has since moved), plus the
diff for that file. Classify into exactly one:

| Class | Test | Outcome |
|---|---|---|
| **fix** | The reviewer is right, or it's a small matter of taste (cost of applying < cost of arguing) | Implement in Phase 2 |
| **already-addressed** | A commit since the comment demonstrably fixed it — confirm by reading `git show <sha> -- <path>`, not by commit message | Reply with the commit link |
| **push-back** | You can demonstrate the comment is mistaken, or the "improvement" would make the code worse (over-engineering, breaking a repo convention, solving a problem that doesn't exist) | Reply with rationale |
| **answer** | A genuine question | Reply with the answer; if the question reveals unclear code, *also* clarify the code (that part becomes a **fix**) |
| **out-of-scope** | Real, but belongs in a different change (unrelated refactor, pre-existing issue, scope creep) | Reply acknowledging it + file or propose a follow-up issue; never silently ignore |

Triage discipline:

- For **fix**: restate to yourself what the reviewer actually wants before
  editing — misreading the ask and "fixing" the wrong thing is worse than
  asking. If a comment is genuinely ambiguous, classify it **answer** and
  ask for clarification instead of guessing.
- For **push-back**: the bar is the same demonstrability bar as reviewing —
  cite the input/behavior, the repo convention, or the concrete cost that
  makes your way right. Then invite discussion ("happy to change if you
  disagree") — the goal is consensus on technical facts, not winning.
- If `reply_only` is set, **fix** items become replies stating what you
  *would* change and your agreement — no edits.

## Phase 2 — Implement the fixes

Skip when `reply_only`. For the **fix** queue:

1. Group related comments into logical units — one commit per concern, not
   one mega-commit. Write meaningful messages describing the change itself
   (`fix: guard null user in session refresh`), **never** "address review
   comments" — reviewers re-review by reading commits since their last pass.
2. Extend or add tests when the fix changes behavior the tests should have
   caught — the reviewer finding it means the tests didn't.
3. **Never rebase, amend, or force-push mid-review.** New commits only.
   History rewriting orphans every existing comment anchor and destroys the
   reviewer's ability to see what changed since their review. (Squash at
   merge time if that's the repo's convention.)
4. Verify before pushing: run the repo's build/test/lint for the changed
   files, resolved the same way as the `self-review` skill's Step 1.1
   (explicit command → repo entry point → toolchain inference → derivation
   from repo docs). A "fix" that breaks the build converts a helpful
   reviewer into a hostile one.

Push when `push` is true:

```bash
git push
```

## Phase 3 — Reply to every thread

For each thread in the work queue, post exactly one reply. Formats by class
(apply `comment_prefix` if set):

- **fix** → `Fixed in <short-sha> (<link>) — <one line: what changed>.`
- **already-addressed** → `Addressed in <short-sha> (<link>) — <how>.`
- **push-back** → the rationale, evidence first, ending with openness:
  `...— happy to change it if you see a case this misses.`
- **answer** → the answer; reference specific code/lines.
- **out-of-scope** → `Agreed this is real; it's out of scope here — filed <issue link / proposed follow-up>.`

Commit links: `<pr-url>/commits/<full-sha>` (short SHA as the link text).
Post each reply as a threaded response to the thread's **first** comment
(the REST replies endpoint keys on the root comment's `databaseId`):

```bash
gh api repos/<owner>/<repo>/pulls/<number>/comments/<root-databaseId>/replies -f body="<reply>"
```

One API call per reply — no batching. When `push` is false, print the
planned replies instead of posting.

If `resolve_threads` is true, resolve only the **fix** and
**already-addressed** threads (GraphQL `resolveReviewThread` mutation with
the thread `id` from the fetcher output). Never resolve **push-back**,
**answer**, or **out-of-scope** threads — those await the reviewer's
response by definition.

## Completion

Report a table: thread (path:line, one-line gist) → class → action (commit
sha / reply posted / issue filed). Plus: verification status of the pushed
fixes, and any thread deliberately left for human judgment. Clean up temp
files.

## What this skill does NOT do

- **Blindly apply every suggestion** — that's sycophancy, not collaboration.
- **Rewrite branch history** — comment anchors and review continuity outrank
  a tidy log.
- **Resolve the reviewer's threads for them** (unless `resolve_threads` and
  the repo's convention says authors resolve).
- **Argue taste** — if it's arguable and cheap, apply it; disagreement is
  reserved for demonstrable technical points.
- **Reply to threads already awaiting the reviewer** — one reply per turn;
  re-runs must be idempotent.
