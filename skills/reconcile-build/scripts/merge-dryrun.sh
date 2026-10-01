#!/usr/bin/env bash
# merge-dryrun.sh — report whether each chain branch merges cleanly onto a base, and (with --ci) its PR's
# current check state. (BM-RECON-03.)
#
# READ-ONLY: it NEVER merges, checks out, or mutates any branch. It uses `git merge-tree` on the merge-base,
# which computes the merge in memory and writes nothing, and greps the result for conflict markers. With
# --ci it reads each branch's open PR checks through orchestrate-build's ci-boundary.sh (`--no-wait`, one
# read) — CI is read and reported, never fixed. Use it to fill the INTEGRATION_PLAN's PR graph and merge
# dry-run before the operator lands the stack by hand.
#
# Usage:
#   merge-dryrun.sh [--ci] [--json PATH] <base_ref> <branch> [<branch> ...]
#
#   --ci      also read each branch's open PR checks (gh + ci-boundary.sh): pass / FAIL (check + first
#             failing line) / pending / unknown / no open PR, with the `date -u` of the read. Without gh the
#             state is `unknown` and the dry-run still completes.
#   --json    the report (default: a unique mktemp file; the path is printed).
#   base_ref  — the ref the chain lands onto (e.g. main).
#   branch    — one or more chain branches to test against base_ref.
#
# Output: one line per branch — "clean" or "CONFLICT (<n> marker hunk(s))", plus "· CI: <state>" with --ci.
# Exit codes: 0 — all clean · 1 — at least one conflict · 2 — usage / not a git repo / a ref is missing.
#   (A red PR does not change the exit code: the plan reports it; the operator decides.)
# Compatible with bash 3.2+ (macOS default). No associative arrays, no mapfile. Mutates nothing.

set -o pipefail

CI=0; JSON=""
while [ $# -gt 0 ]; do
  case "$1" in
    --ci) CI=1; shift ;;
    --json) JSON="${2:-}"; shift 2 ;;
    *) break ;;
  esac
done
[ $# -ge 2 ] || { awk 'NR > 1 && !/^#/ {exit} NR > 1 {sub(/^# ?/, ""); print}' "$0"; exit 2; }
git rev-parse --git-dir >/dev/null 2>&1 || { echo "merge-dryrun: not a git repo" >&2; exit 2; }

BASE="$1"; shift
git rev-parse --verify -q "$BASE" >/dev/null || { echo "merge-dryrun: base ref not found: $BASE" >&2; exit 2; }
[ -n "$JSON" ] || JSON="$(mktemp "${TMPDIR:-/tmp}/merge-dryrun.XXXXXXXX")" || exit 2
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CIB="$SCRIPT_DIR/../../orchestrate-build/scripts/ci-boundary.sh"
TOP="$(git rev-parse --show-toplevel)"

# ci_state <branch> → prints "<state>\t<detail>" (state: pass | fail | pending | unknown | none)
ci_state() {
  local pr out rc last
  command -v gh >/dev/null 2>&1 || { printf 'unknown\tgh absent'; return; }
  [ -f "$CIB" ] || { printf 'unknown\tci-boundary.sh not found'; return; }
  pr="$(gh pr list --head "$1" --state open --json number --jq '.[0].number' 2>/dev/null | head -1)"
  [ -n "$pr" ] || { printf 'none\tno open PR for %s' "$1"; return; }
  out="$(bash "$CIB" --pr "$pr" --worktree "$TOP" --no-wait 2>/dev/null)"; rc=$?
  last="$(printf '%s\n' "$out" | tail -1)"
  case "$rc" in
    0) printf 'pass\t%s' "$last" ;;
    3) printf 'fail\t%s' "$last" ;;
    4) printf 'pending\t%s' "$last" ;;
    *) printf 'unknown\t%s' "${last:-CI state unreadable for #$pr}" ;;
  esac
}

CONFLICTS=0 ; TOTAL=0 ; first=1 ; RED=0
READ_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '{"schema":"merge-dryrun/2","base":"%s","ci_read_at":%s,"results":[' "$BASE" "$([ "$CI" -eq 1 ] && printf '"%s"' "$READ_AT" || printf null)" > "$JSON"
[ "$CI" -eq 1 ] && echo "merge-dryrun: CI read at $READ_AT (date -u; one read per PR, --no-wait)"

for BR in "$@"; do
  TOTAL=$((TOTAL + 1))
  cij=""; cis=""
  if [ "$CI" -eq 1 ]; then
    st="$(ci_state "$BR")"; s="$(printf '%s' "$st" | cut -f1)"; d="$(printf '%s' "$st" | cut -f2-)"
    case "$s" in pass) cis=" · CI: pass — $d" ;; fail) cis=" · CI: FAIL — $d"; RED=$((RED + 1)) ;; pending) cis=" · CI: pending — $d" ;;
                 none) cis=" · CI: none ($d)" ;; *) cis=" · CI: unknown — $d" ;; esac
    cij="$(printf ',"ci":{"state":"%s","detail":"%s"}' "$s" "$(printf '%s' "$d" | sed 's/\\/\\\\/g; s/"/\\"/g')")"
  fi
  if ! git rev-parse --verify -q "$BR" >/dev/null; then
    echo "  ? $BR — ref not found (skipped)$cis"
    [ "$first" -eq 1 ] || printf ',' >> "$JSON"; first=0
    printf '{"branch":"%s","status":"missing"%s}' "$BR" "$cij" >> "$JSON"
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
    echo "  ✗ $BR — CONFLICT ($NCONF marker hunk(s))$cis"
    printf '{"branch":"%s","status":"conflict","markers":%s%s}' "$BR" "$NCONF" "$cij" >> "$JSON"
  else
    echo "  ✓ $BR — clean$cis"
    printf '{"branch":"%s","status":"clean"%s}' "$BR" "$cij" >> "$JSON"
  fi
done

printf ']}\n' >> "$JSON"
echo "merge-dryrun: $TOTAL branch(es) onto $BASE — $CONFLICTS conflict(s)$([ "$CI" -eq 1 ] && echo ", $RED red PR(s)"). JSON: $JSON"
[ "$CONFLICTS" -eq 0 ] || exit 1
exit 0
