#!/bin/bash
# fetch-pr-context.sh — gather GitHub PR context for review (READ-ONLY)
# ---------------------------------------------------------------------------
# Usage: fetch-pr-context.sh [pr]
#   pr: PR number, URL, or branch name. Default: the open PR for the
#       current branch (per `gh pr view` resolution).
#
# Writes:
#   /tmp/pr-context.json  — PR metadata: title, body, author, refs, draft
#                           state, changed files, CI check rollup
#   /tmp/pr-threads.json  — all review threads with resolution state
#                           (resolution is only available via GraphQL)
#
# Requires: gh (authenticated), git. Makes no writes to the repo or the PR.
# Exit codes: 0 = ok, 1 = no PR found / gh error.
# Limitations: fetches the first 100 threads x 50 comments; PRs with more
# need manual pagination.
# ---------------------------------------------------------------------------
set -euo pipefail

PR_ARG="${1:-}"

CONTEXT_OUT="${PR_CONTEXT_OUT:-/tmp/pr-context.json}"
THREADS_OUT="${PR_THREADS_OUT:-/tmp/pr-threads.json}"

# --- PR metadata (gh resolves number, URL, branch, or current branch) ------
if ! gh pr view ${PR_ARG:+"$PR_ARG"} \
  --json number,title,body,author,baseRefName,headRefName,isDraft,state,url,additions,deletions,changedFiles,files,statusCheckRollup,commits \
  > "$CONTEXT_OUT"; then
  echo "ERROR: could not resolve a PR from '${PR_ARG:-current branch}'" >&2
  exit 1
fi

NUMBER="$(gh pr view ${PR_ARG:+"$PR_ARG"} --json number --jq .number)"
OWNER="$(gh repo view --json owner --jq .owner.login)"
REPO="$(gh repo view --json name --jq .name)"

# --- Review threads with resolution state (GraphQL only) -------------------
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
  --jq '[.data.repository.pullRequest.reviewThreads.nodes[] | .comments = .comments.nodes]' \
  > "$THREADS_OUT"

THREAD_COUNT="$(gh api graphql -f query='query($owner:String!,$name:String!,$number:Int!){repository(owner:$owner,name:$name){pullRequest(number:$number){reviewThreads(first:100){totalCount}}}}' -f owner="$OWNER" -f name="$REPO" -F number="$NUMBER" --jq '.data.repository.pullRequest.reviewThreads.totalCount')"

echo "PR #${NUMBER} (${OWNER}/${REPO})"
echo "  context: ${CONTEXT_OUT}"
echo "  threads: ${THREADS_OUT} (${THREAD_COUNT} total)"
