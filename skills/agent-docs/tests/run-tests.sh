#!/usr/bin/env bash
# run-tests.sh — self-test for check-agent-docs-freshness.sh against a throwaway git repo.
#
# Builds a fixture repo in a temp dir (a root AGENTS.md citing committed build memory under docs/build/, a stale
# agent-harness snapshot under .claude/worktrees/, and a build-output dir build/gen/ with enough source files to trip the
# coverage check), runs the freshness check from inside it and asserts the exit code and report lines.
#
# Usage:   run-tests.sh
# Exit codes: 0 — all cases pass; 1 — a case failed.
# Compatible with bash 3.2+ (macOS default). Read-only outside its own temp dirs.

set -o pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$(cd "$HERE/../scripts" && pwd)/check-agent-docs-freshness.sh"
FAIL=0
say()  { printf '%s\n' "$*"; }
fail() { printf '  ✗ %s\n' "$*"; FAIL=1; }

fixture() {   # fixture <dir> — the repo shape both cases start from
  local R="$1"
  mkdir -p "$R/docs/build" "$R/src/app" "$R/.claude/worktrees/old" "$R/build/gen"
  printf '# AGENTS.md\n\n## Key Files\n\n| File | Purpose |\n|---|---|\n| `src/app/Main.scala` | entry |\n| `docs/build/LEDGER.md` | the build ledger |\n\n## Build memory\n\nThe ledger is `docs/build/LEDGER.md`.\n' > "$R/AGENTS.md"
  printf '# build memory\n' > "$R/docs/build/README.md"
  printf '# ledger\n' > "$R/docs/build/LEDGER.md"
  printf 'object Main\n' > "$R/src/app/Main.scala"
  # a stale snapshot an agent harness left behind: it cites a file that does not exist
  printf '# stale snapshot\n\nSee `src/app/Gone.scala`.\n' > "$R/.claude/worktrees/old/AGENTS.md"
  # build output: five source files and no AGENTS.md would be a coverage gap if build/ were scanned
  local i; for i in 1 2 3 4 5; do printf 'object G%s\n' "$i" > "$R/build/gen/G$i.scala"; done
}
gitify() { ( cd "$1" && git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -qm init ) >/dev/null 2>&1 || true; }

# ── Case 1: committed docs/build/ is indexed, .claude/ snapshots are not scanned, build/ output stays excluded ──
test_excludes() {
  local ok=1 R out rc
  R="$(mktemp -d)/repo"; fixture "$R"; gitify "$R"
  out="$(cd "$R" && bash "$CHECK" 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] || { fail "excludes: exit=$rc (want 0)"; ok=0; }
  printf '%s' "$out" | grep -qF 'docs/build/LEDGER.md` which does not exist' && { fail "excludes: committed docs/build/LEDGER.md reported missing (docs/build/ not indexed)"; ok=0; }
  printf '%s' "$out" | grep -qF 'Gone.scala' && { fail "excludes: a .claude/ snapshot was scanned"; ok=0; }
  printf '%s' "$out" | grep -qF 'build/gen' && { fail "excludes: build-output dir build/gen was scanned"; ok=0; }
  printf '%s' "$out" | grep -qF '1 docs scanned' || { fail "excludes: want exactly the root AGENTS.md scanned"; ok=0; }
  [ "$ok" = 1 ] && say "PASS excludes"
}

# ── Case 2: a genuinely missing file under docs/build/ is still a critical issue ──────────────────────────────
test_docs_build_still_checked() {
  local ok=1 R out rc
  R="$(mktemp -d)/repo"; fixture "$R"
  printf '\nThe run ledgers are in `docs/build/RUNS.md`.\n' >> "$R/AGENTS.md"
  gitify "$R"
  out="$(cd "$R" && bash "$CHECK" 2>&1)"; rc=$?
  { [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -qF 'docs/build/RUNS.md` which does not exist'; } \
    || { fail "docs-build: a missing docs/build/ reference was not critical (exit=$rc)"; ok=0; }
  [ "$ok" = 1 ] && say "PASS docs-build-still-checked"
}

test_excludes
test_docs_build_still_checked

if [ "$FAIL" -eq 0 ]; then
  say "ALL PASS"
  exit 0
fi
say "FAILURES above"
exit 1
