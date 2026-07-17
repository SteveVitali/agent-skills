#!/bin/bash
# fetch-unresolved-threads.sh — unresolved review threads on a PR (READ-ONLY)
# ---------------------------------------------------------------------------
# Usage: fetch-unresolved-threads.sh [pr]
#   pr: PR number, URL, or branch name. Default: the open PR for the
#       current branch (per `gh pr view` resolution).
#
# Writes:
#   /tmp/pr-unresolved-threads.json — unresolved review threads only: thread
#       id (for GraphQL resolution), path, line, isOutdated, and the full
#       comment chain (databaseId, author, body, createdAt)
#   /tmp/pr-meta.json — {number, url, baseRefName, headRefName, title,
#       viewerLogin} — viewerLogin is the authenticated user, for
#       partitioning threads into awaiting-you vs awaiting-them
#
# Requires: gh (authenticated), git. Makes no writes to the repo or the PR.
# Exit codes: 0 = ok, 1 = no PR found / gh error.
# Limitations: fetches the first 100 threads x 50 comments; PRs with more
# need manual pagination.
# ---------------------------------------------------------------------------
set -euo pipefail

PR_ARG="${1:-}"

THREADS_OUT="${PR_UNRESOLVED_OUT:-/tmp/pr-unresolved-threads.json}"
META_OUT="${PR_META_OUT:-/tmp/pr-meta.json}"

if ! NUMBER="$(gh pr view ${PR_ARG:+"$PR_ARG"} --json number --jq .number)"; then
  echo "ERROR: could not resolve a PR from '${PR_ARG:-current branch}'" >&2
  exit 1
fi

OWNER="$(gh repo view --json owner --jq .owner.login)"
REPO="$(gh repo view --json name --jq .name)"
VIEWER="$(gh api user --jq .login)"

gh pr view ${PR_ARG:+"$PR_ARG"} --json number,url,baseRefName,headRefName,title \
  --jq ". + {viewerLogin: \"${VIEWER}\"}" > "$META_OUT"

gh api graphql \
  -f query='
    query($owner: String!, $name: String!, $number: Int!) {
      repository(owner: $owner, name: $name) {
        pullRequest(number: $number) {
          reviewThreads(first: 100) {
            nodes {
              id
              isResolved
              isOutdated
              path
              line
              comments(first: 50) {
                nodes {
                  databaseId
                  body
                  author { login }
                  createdAt
                }
              }
            }
          }
        }
      }
    }' \
  -f owner="$OWNER" -f name="$REPO" -F number="$NUMBER" \
  --jq '[.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false) | .comments = .comments.nodes]' \
  > "$THREADS_OUT"

UNRESOLVED="$(grep -o '"isResolved"' "$THREADS_OUT" | wc -l | tr -d ' ')"

echo "PR #${NUMBER} (${OWNER}/${REPO}) — viewer: ${VIEWER}"
echo "  meta:    ${META_OUT}"
echo "  threads: ${THREADS_OUT} (${UNRESOLVED} unresolved)"
