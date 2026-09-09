#!/usr/bin/env bash
# memory-root.sh — resolve the build-memory root for the current worktree.
#
# Every build skill (decompose-spec, orchestrate-build, implement-spec) obtains its
# memory root from this one script, so committed mode and legacy scratch mode are
# decided in exactly one place. (BM-ROOT-01, BM-ROOT-02.)
#
# Usage:
#   memory-root.sh [worktree]
#
# Arguments:
#   worktree — directory to resolve from (default: the current git worktree toplevel).
#              Resolution always uses THIS worktree, so a sibling build worktree reads
#              the ledger on its own chain tip, never the main worktree's copy.
#
# Resolution order:
#   1. $BUILD_MEMORY_ROOT, if set          -> mode=committed, root=that path (absolutized)
#   2. <worktree>/docs/build, if its README.md contains the marker
#      line `<!-- build-memory: v2 -->`    -> mode=committed, root=<worktree>/docs/build
#   3. otherwise (legacy scratch mode, byte-for-byte today's rule):
#        root=${AGENT_SCRATCH_DIR:-<parent of git-common-dir>/.agents/scratch}
#                                          -> mode=scratch
#
# Output (exactly two lines, in this order, both consumed by callers):
#   mode=<committed|scratch>
#   root=<absolute path>
#
# Exit codes:
#   0 — resolved (always, when run inside a usable directory)
#   1 — not inside a git worktree and no $BUILD_MEMORY_ROOT (cannot resolve)
#
# Read-only: this script never writes or mutates anything.
# Compatible with bash 3.2+ (macOS default). No associative arrays, no mapfile.

set -o pipefail

MARKER='<!-- build-memory: v2 -->'

# 1. Explicit override wins unconditionally.
if [ -n "${BUILD_MEMORY_ROOT:-}" ]; then
  # Absolutize without requiring the directory to exist yet.
  case "$BUILD_MEMORY_ROOT" in
    /*) root="$BUILD_MEMORY_ROOT" ;;
    *)  root="$(pwd)/$BUILD_MEMORY_ROOT" ;;
  esac
  printf 'mode=committed\n'
  printf 'root=%s\n' "$root"
  exit 0
fi

WT="${1:-}"
if [ -z "$WT" ]; then
  WT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
fi

# 2. Committed mode: the worktree's docs/build/README.md carries the v2 marker.
if [ -n "$WT" ] && [ -f "$WT/docs/build/README.md" ] && grep -qF "$MARKER" "$WT/docs/build/README.md" 2>/dev/null; then
  printf 'mode=committed\n'
  printf 'root=%s\n' "$WT/docs/build"
  exit 0
fi

# 3. Legacy scratch mode — today's rule, unchanged.
if [ -n "${AGENT_SCRATCH_DIR:-}" ]; then
  scratch="$AGENT_SCRATCH_DIR"
else
  common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  if [ -z "$common" ]; then
    echo "memory-root.sh: not a git worktree and no \$BUILD_MEMORY_ROOT set; cannot resolve a root" >&2
    exit 1
  fi
  scratch="$(dirname "$common")/.agents/scratch"
fi
printf 'mode=scratch\n'
printf 'root=%s\n' "$scratch"
exit 0
