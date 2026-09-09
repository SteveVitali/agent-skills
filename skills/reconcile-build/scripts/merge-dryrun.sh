#!/usr/bin/env bash
# merge-dryrun.sh — report whether each chain branch merges cleanly onto a base. (BM-RECON-03.)
#
# READ-ONLY: it NEVER merges, checks out, or mutates any branch. It uses `git merge-tree` on the merge-base,
# which computes the merge in memory and writes nothing, and greps the result for conflict markers. Use it to
# fill the INTEGRATION_PLAN's merge dry-run section before the operator lands the stack by hand.
#
# Usage:
#   merge-dryrun.sh <base_ref> <branch> [<branch> ...]
#
#   base_ref  — the ref the chain lands onto (e.g. main).
#   branch    — one or more chain branches to test against base_ref.
#
# Output: one line per branch — "clean" or "CONFLICT (<n> path(s))" — to stdout; JSON to /tmp/merge-dryrun.json.
# Exit codes: 0 — all clean · 1 — at least one conflict · 2 — usage / not a git repo / a ref is missing.
# Compatible with bash 3.2+ (macOS default). No associative arrays, no mapfile. Mutates nothing.

set -o pipefail

[ $# -ge 2 ] || { grep -E '^#( |$)' "$0" | sed -E 's/^# ?//'; exit 2; }
git rev-parse --git-dir >/dev/null 2>&1 || { echo "merge-dryrun: not a git repo" >&2; exit 2; }

BASE="$1"; shift
git rev-parse --verify -q "$BASE" >/dev/null || { echo "merge-dryrun: base ref not found: $BASE" >&2; exit 2; }

JSON="/tmp/merge-dryrun.json"
CONFLICTS=0 ; TOTAL=0 ; first=1
: > "$JSON.tmp" 2>/dev/null || true
printf '{"base":"%s","results":[' "$BASE" > "$JSON"

for BR in "$@"; do
  TOTAL=$((TOTAL + 1))
  if ! git rev-parse --verify -q "$BR" >/dev/null; then
    echo "  ? $BR — ref not found (skipped)"
    [ "$first" -eq 1 ] || printf ',' >> "$JSON"; first=0
    printf '{"branch":"%s","status":"missing"}' "$BR" >> "$JSON"
    continue
  fi
  MB="$(git merge-base "$BASE" "$BR" 2>/dev/null)"
  # `git merge-tree <base-commit> <branch1> <branch2>` (trivial form) prints the merged tree and, on conflict,
  # conflict hunks containing markers. Read-only; nothing is written to the repo.
  OUT="$(git merge-tree "$MB" "$BASE" "$BR" 2>/dev/null)"
  NCONF="$(printf '%s\n' "$OUT" | grep -cE '^(<{7}|={7}|>{7})' 2>/dev/null | tr -d ' ')"
  case "$NCONF" in ''|*[!0-9]*) NCONF=0 ;; esac
  [ "$first" -eq 1 ] || printf ',' >> "$JSON"; first=0
  if [ "$NCONF" -gt 0 ]; then
    CONFLICTS=$((CONFLICTS + 1))
    echo "  ✗ $BR — CONFLICT ($NCONF marker hunk(s))"
    printf '{"branch":"%s","status":"conflict","markers":%s}' "$BR" "$NCONF" >> "$JSON"
  else
    echo "  ✓ $BR — clean"
    printf '{"branch":"%s","status":"clean"}' "$BR" >> "$JSON"
  fi
done

printf ']}\n' >> "$JSON"
echo "merge-dryrun: $TOTAL branch(es) onto $BASE — $CONFLICTS conflict(s). JSON: $JSON"
[ "$CONFLICTS" -eq 0 ] || exit 1
exit 0
