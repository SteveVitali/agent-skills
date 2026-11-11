#!/usr/bin/env bash
# memory-root.sh — resolve the build-memory root for the current worktree.
#
# Every build skill (decompose-spec, orchestrate-build, implement-spec) obtains its
# memory root from this one script, so committed mode and legacy scratch mode are
# decided in exactly one place. (BM-ROOT-01, BM-ROOT-02, BM-ROOT-03.)
#
# Usage:
#   memory-root.sh [--paths] [--allow-missing] [worktree]
#
# Arguments:
#   worktree — directory to resolve from (default: the current git worktree toplevel).
#              Resolution always uses THIS worktree, so a sibling build worktree reads
#              the ledger on its own chain tip, never the main worktree's copy.
#   --paths  — also print project=, docs=, tickets= and adr= lines (committed mode; see bm-paths.sh).
#   --allow-missing — accept a $BUILD_MEMORY_ROOT that does not exist yet (build-memory init and
#              synthesize-spec planning, before the root is created); a note goes to stderr.
#
# Resolution order:
#   1. $BUILD_MEMORY_ROOT, if set          -> mode=committed, root=that path. A relative value
#      resolves against the worktree's toplevel (never the cwd). A root that does not exist is an
#      error (exit 2) unless --allow-missing — never a silent fallback.
#   2. <worktree>/docs/build, if its README.md contains the marker
#      line `<!-- build-memory: v2 -->`    -> mode=committed, root=<worktree>/docs/build
#   3. otherwise (legacy scratch mode, byte-for-byte today's rule):
#        root=${AGENT_SCRATCH_DIR:-<parent of git-common-dir>/.agents/scratch}
#                                          -> mode=scratch
#      Unless $AGENT_SCRATCH_DIR is set (scratch chosen explicitly), a tracked
#      <sub>/docs/build/README.md carrying the marker (a monorepo subproject's build memory) makes
#      this an error (exit 3) that names it: set BUILD_MEMORY_ROOT=<sub>/docs/build. The resolved
#      scratch mode is also stated on stderr.
#
# Output (stdout; the two lines below always, in this order, both consumed by callers):
#   mode=<committed|scratch>
#   root=<absolute path>
#   + with --paths in committed mode: project=<abs> docs=<abs> tickets=<abs> adr=<abs>
#
# Exit codes:
#   0 — resolved
#   1 — not inside a git worktree and no $BUILD_MEMORY_ROOT (cannot resolve)
#   2 — $BUILD_MEMORY_ROOT is set but names a missing dir (without --allow-missing), or a
#       BUILD_MEMORY_TICKETS / BUILD_MEMORY_ADR override is outside the project dir
#   3 — scratch would be chosen implicitly, but the worktree holds committed build memory in a subdir
#
# Read-only: this script never writes or mutates anything.
# Compatible with bash 3.2+ (macOS default). No associative arrays, no mapfile.

set -o pipefail

MARKER='<!-- build-memory: v2 -->'
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bm-paths.sh
. "$SELF_DIR/bm-paths.sh"

PATHS=0 ; ALLOW_MISSING=0 ; WT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --paths)         PATHS=1; shift ;;
    --allow-missing) ALLOW_MISSING=1; shift ;;
    -h|--help)       awk 'NR > 1 && !/^#/ {exit} NR > 1 {sub(/^# ?/, ""); print}' "$0"; exit 0 ;;
    *)               WT="$1"; shift ;;
  esac
done

committed() {   # committed <root> [base] — print the committed-mode lines
  printf 'mode=committed\n'
  printf 'root=%s\n' "$1"
  if [ "$PATHS" -eq 1 ]; then
    bm_set_paths "$1" "${2:-$1}" || { echo "memory-root.sh: $BM_ERR" >&2; exit 2; }
    printf 'project=%s\ndocs=%s\ntickets=%s\nadr=%s\n' "$BM_PROJECT" "$BM_DOCS" "$BM_TICKETS" "$BM_ADR"
  fi
  exit 0
}

# 1. Explicit override wins unconditionally — and must exist.
if [ -n "${BUILD_MEMORY_ROOT:-}" ]; then
  root="$(bm_resolve_against "$BUILD_MEMORY_ROOT" "${WT:-.}")"
  if [ ! -d "$root" ]; then
    if [ "$ALLOW_MISSING" -eq 1 ]; then
      echo "memory-root.sh: note: BUILD_MEMORY_ROOT=$BUILD_MEMORY_ROOT → $root does not exist yet (--allow-missing)" >&2
    else
      echo "memory-root.sh: BUILD_MEMORY_ROOT=$BUILD_MEMORY_ROOT resolves to $root, which does not exist." >&2
      echo "  A relative value resolves against the worktree toplevel ($(bm_toplevel "${WT:-.}" || true)). Run build-memory init" >&2
      echo "  (memory-root.sh --allow-missing) to create it, or fix the value. Not falling back to another root." >&2
      exit 2
    fi
  fi
  committed "$root" "${WT:-.}"
fi

if [ -z "$WT" ]; then
  WT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
fi

# 2. Committed mode: the worktree's docs/build/README.md carries the v2 marker.
if [ -n "$WT" ] && [ -f "$WT/docs/build/README.md" ] && grep -qF "$MARKER" "$WT/docs/build/README.md" 2>/dev/null; then
  committed "$WT/docs/build"
fi

# 3. Legacy scratch mode — today's rule, unchanged; never chosen silently over subproject build memory.
if [ -n "${AGENT_SCRATCH_DIR:-}" ]; then
  scratch="$AGENT_SCRATCH_DIR"
else
  common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  if [ -z "$common" ]; then
    echo "memory-root.sh: not a git worktree and no \$BUILD_MEMORY_ROOT set; cannot resolve a root" >&2
    exit 1
  fi
  scratch="$(dirname "$common")/.agents/scratch"
  nested="$(bm_nested_roots "${WT:-.}")"
  if [ -n "$nested" ]; then
    echo "memory-root.sh: BUILD_MEMORY_ROOT is unset and ${WT:-this worktree}/docs/build has no marker, but this worktree" >&2
    echo "  holds committed build memory at:" >&2
    printf '%s\n' "$nested" | sed 's/^/    /' >&2
    echo "  Set BUILD_MEMORY_ROOT=<one of those> (relative to the worktree toplevel), e.g. in .claude/settings.local.json" >&2
    echo "  \"env\" and in drive-build's environment. Set AGENT_SCRATCH_DIR to choose legacy scratch mode explicitly." >&2
    exit 3
  fi
fi
echo "memory-root.sh: mode=scratch (BUILD_MEMORY_ROOT unset; no '$MARKER' in ${WT:-<no worktree>}/docs/build/README.md)" >&2
printf 'mode=scratch\n'
printf 'root=%s\n' "$scratch"
exit 0
