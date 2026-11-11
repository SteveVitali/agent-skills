#!/usr/bin/env bash
# bm-paths.sh — resolve the build-memory paths from one memory root. SOURCED, never run. (BM-ROOT-03.)
#
# memory-root.sh, check-build-memory.sh, check-history.sh, migrate-legacy-scratch.sh and the
# orchestrate-build / reconcile-build scripts source this file, so a memory root that lives in a
# monorepo subproject (e.g. <toplevel>/sub/proj/docs/build) resolves the same way everywhere.
#
# Environment (all optional; unset = the single-repo default, which is byte-identical to 0.5.3):
#   BUILD_MEMORY_ROOT     the memory root. A relative value resolves against the worktree toplevel
#                         (never the cwd), so each sibling worktree reads its own copy. Prefer relative.
#   BUILD_MEMORY_TICKETS  the tickets dir (default: <memory root>/../tickets). Same resolution rule;
#                         must lie under the project dir (below).
#   BUILD_MEMORY_ADR      the ADR dir (default: <memory root>/../adr). Same rules.
#
# Derived names, for a memory root X/docs/build (bm_set_paths):
#   BM_BUILD = X/docs/build   BM_DOCS = X/docs   BM_PROJECT = X   BM_TICKETS = X/docs/tickets   BM_ADR = X/docs/adr
#   BM_BREL / BM_DREL / BM_TREL / BM_AREL — the same dirs relative to BM_PROJECT (docs/build, docs,
#   docs/tickets, docs/adr in the standard layout). Every repo-relative label the validator prints is
#   relative to BM_PROJECT, the "project dir" (the git toplevel in a single-repo layout).
#
# Compatible with bash 3.2+. Defines functions and BM_* variables only; never writes.

# bm_canon PATH → an absolute path: the longest existing prefix made physical (pwd -P), the rest appended.
bm_canon() {
  local p="$1" rest=""
  case "$p" in /*) : ;; *) p="$(pwd)/$p" ;; esac
  while [ ! -d "$p" ] && [ "$p" != "/" ] && [ -n "$p" ]; do rest="/$(basename "$p")$rest"; p="$(dirname "$p")"; done
  p="$(cd "$p" 2>/dev/null && pwd -P)"; [ "$p" = "/" ] && p=""
  printf '%s%s\n' "$p" "$rest" | sed -E 's#/\./#/#g; s#/\.$##; s#//+#/#g'
}

# bm_toplevel DIR → the git worktree toplevel containing DIR (empty outside git).
bm_toplevel() { git -C "${1:-.}" rev-parse --show-toplevel 2>/dev/null; }

# bm_resolve_against VALUE BASE → VALUE made absolute: as given when absolute (0.5.3 printed it so), else
# against BASE's worktree toplevel (or BASE itself outside git).
bm_resolve_against() {
  local v="$1" base="${2:-.}" top
  case "$v" in
    /) printf '/\n' ;;
    /*) printf '%s\n' "${v%/}" ;;
    *)  top="$(bm_toplevel "$base")"; [ -n "$top" ] || top="$(cd "$base" 2>/dev/null && pwd -P || pwd -P)"
        bm_canon "$top/$v" ;;
  esac
}

# bm_rel_under PATH PROJECT → PATH relative to PROJECT; returns 1 when PATH is not under PROJECT.
bm_rel_under() {
  case "$1" in "$2"/*) printf '%s\n' "${1#"$2"/}" ;; *) return 1 ;; esac
}

# bm_set_paths ROOT [BASE] → BM_* from the memory root (BASE resolves the tickets/adr overrides; default ROOT).
# Returns 2 with BM_ERR set when an override does not lie under the project dir.
bm_set_paths() {
  local base="${2:-$1}" t
  BM_ERR=""
  BM_BUILD="$1"; BM_DOCS="$(dirname "$BM_BUILD")"; BM_PROJECT="$(dirname "$BM_DOCS")"
  BM_DREL="$(basename "$BM_DOCS")"; BM_BREL="$BM_DREL/$(basename "$BM_BUILD")"
  BM_TICKETS="$BM_DOCS/tickets"; BM_TREL="$BM_DREL/tickets"
  BM_ADR="$BM_DOCS/adr";         BM_AREL="$BM_DREL/adr"
  if [ -n "${BUILD_MEMORY_TICKETS:-}" ] || [ -n "${BUILD_MEMORY_ADR:-}" ]; then
    # An override is compared physically, so canonicalize the project the same way first.
    BM_PROJECT="$(bm_canon "$BM_PROJECT")"; BM_DOCS="$BM_PROJECT/$BM_DREL"; BM_BUILD="$BM_PROJECT/$BM_BREL"
    BM_TICKETS="$BM_PROJECT/$BM_TREL"; BM_ADR="$BM_PROJECT/$BM_AREL"
    if [ -n "${BUILD_MEMORY_TICKETS:-}" ]; then
      t="$(bm_canon "$(bm_resolve_against "$BUILD_MEMORY_TICKETS" "$base")")"
      BM_TREL="$(bm_rel_under "$t" "$BM_PROJECT")" || { BM_ERR="BUILD_MEMORY_TICKETS=$BUILD_MEMORY_TICKETS resolves to $t, which is not under the project dir $BM_PROJECT (the parent of the memory root's docs dir)"; return 2; }
      BM_TICKETS="$t"
    fi
    if [ -n "${BUILD_MEMORY_ADR:-}" ]; then
      t="$(bm_canon "$(bm_resolve_against "$BUILD_MEMORY_ADR" "$base")")"
      BM_AREL="$(bm_rel_under "$t" "$BM_PROJECT")" || { BM_ERR="BUILD_MEMORY_ADR=$BUILD_MEMORY_ADR resolves to $t, which is not under the project dir $BM_PROJECT"; return 2; }
      BM_ADR="$t"
    fi
  fi
  return 0
}

# bm_resolve REPO_ARG MEMROOT_FLAG → BM_* for a validator-style caller, and BM_SOURCE:
#   flag    --memory-root DIR given (relative to the cwd, like any path argument)
#   arg     REPO_ARG given and REPO_ARG/docs/build exists (an explicit project dir wins over the env)
#   env     $BUILD_MEMORY_ROOT (relative → against REPO_ARG's, else the cwd's, worktree toplevel); must exist
#   default <REPO_ARG | git toplevel | cwd>/docs/build — exactly the 0.5.3 rule
# Returns 2 with BM_ERR set when BUILD_MEMORY_ROOT names a missing dir or an override is outside the project.
bm_resolve() {
  local arg="$1" flag="$2" root proj
  BM_SOURCE=""; BM_ERR=""
  if [ -n "$flag" ]; then
    BM_SOURCE=flag; root="$(bm_canon "$flag")"
  elif [ -n "$arg" ] && [ -d "$arg/docs/build" ]; then
    BM_SOURCE=arg; root="$(cd "$arg" && pwd)/docs/build"
  elif [ -n "${BUILD_MEMORY_ROOT:-}" ]; then
    BM_SOURCE=env; root="$(bm_resolve_against "$BUILD_MEMORY_ROOT" "${arg:-.}")"
    if [ ! -d "$root" ]; then
      BM_ERR="BUILD_MEMORY_ROOT=$BUILD_MEMORY_ROOT resolves to $root, which does not exist (a relative value resolves against the worktree toplevel; run build-memory init, or fix the value)"
      return 2
    fi
  else
    BM_SOURCE=default
    proj="${arg:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
    proj="$(cd "$proj" 2>/dev/null && pwd || printf '%s' "$proj")"
    root="$proj/docs/build"
  fi
  bm_set_paths "$root" "${arg:-.}"
}

# bm_find_rel REL → the first existing of BM_PROJECT/REL and <toplevel>/REL (absolute REL as is), else
# BM_PROJECT/REL. Ledger values (manifest, canonicalSpec, orient paths) may be written relative to the
# project dir or to the worktree toplevel; both resolve.
bm_find_rel() {
  local top
  case "$1" in /*) printf '%s\n' "$1"; return 0 ;; esac
  [ -e "$BM_PROJECT/$1" ] && { printf '%s\n' "$BM_PROJECT/$1"; return 0; }
  top="$(bm_toplevel "$BM_PROJECT")"
  [ -n "$top" ] && [ -e "$top/$1" ] && { printf '%s\n' "$top/$1"; return 0; }
  printf '%s\n' "$BM_PROJECT/$1"
}

# bm_nested_roots DIR → tracked <sub>/docs/build/README.md files under DIR's worktree that carry the v2
# marker, as toplevel-relative memory roots (one per line). Paths under a tests/ or fixtures/ segment are
# fixtures, not build memory, and are skipped.
bm_nested_roots() {
  local top f
  top="$(bm_toplevel "${1:-.}")"; [ -n "$top" ] || return 0
  git -C "$top" ls-files -- ':(glob)**/docs/build/README.md' 2>/dev/null \
    | grep -vE '(^|/)(tests?|fixtures?)/' | while IFS= read -r f; do
      [ "$f" = "docs/build/README.md" ] && continue
      grep -qF '<!-- build-memory: v2 -->' "$top/$f" 2>/dev/null && printf '%s\n' "${f%/README.md}"
    done
}
