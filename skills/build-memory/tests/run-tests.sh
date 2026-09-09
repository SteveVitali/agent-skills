#!/usr/bin/env bash
# run-tests.sh — self-test for the build-memory scripts against three fixture repos.
#
# Copies each fixture into a temp dir, inits git, and exercises memory-root.sh,
# check-build-memory.sh, adr-index.sh and migrate-legacy-scratch.sh, asserting exit
# codes and expected files. Prints one PASS line per fixture. Runnable by self-review's
# verify step.
#
# Usage:   run-tests.sh
# Exit codes: 0 — all fixtures pass; 1 — a fixture failed.
# Compatible with bash 3.2+ (macOS default). Read-only outside its own temp dirs.

set -o pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "$HERE/../scripts" && pwd)"
FAIL=0
say()  { printf '%s\n' "$*"; }
fail() { printf '  ✗ %s\n' "$*"; FAIL=1; }

tmp() { d="$(mktemp -d)"; printf '%s' "$d"; }
gitify() { ( cd "$1" && git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -qm init ) >/dev/null 2>&1 || true; }

# ── Fixture 1: v2-clean ──────────────────────────────────────────────────────
test_clean() {
  local W; W="$(tmp)/repo"; cp -R "$HERE/v2-clean" "$W"; gitify "$W"
  local ok=1
  # memory-root: committed after the marker is present
  local out root mode
  out="$(bash "$SCRIPTS/memory-root.sh" "$W")"
  mode="$(printf '%s' "$out" | sed -n 's/^mode=//p')"
  root="$(printf '%s' "$out" | sed -n 's/^root=//p')"
  [ "$mode" = "committed" ] || { fail "v2-clean: memory-root mode=$mode (want committed)"; ok=0; }
  [ "$root" = "$W/docs/build" ] || { fail "v2-clean: memory-root root=$root (want $W/docs/build)"; ok=0; }
  # validator clean
  bash "$SCRIPTS/check-build-memory.sh" "$W" >/dev/null 2>&1
  [ $? -eq 0 ] || { fail "v2-clean: check-build-memory did not exit 0"; ok=0; }
  # adr-index regenerates byte-identically
  local g; g="$(mktemp)"
  bash "$SCRIPTS/adr-index.sh" --check "$W/docs/adr" > "$g" 2>/dev/null
  cmp -s "$g" "$W/docs/adr/README.md" || { fail "v2-clean: adr-index not byte-identical to committed README"; ok=0; }
  rm -f "$g"
  [ "$ok" = 1 ] && say "PASS v2-clean"
}

# ── Fixture 2: v2-violations ─────────────────────────────────────────────────
test_violations() {
  local W; W="$(tmp)/repo"; cp -R "$HERE/v2-violations" "$W"; gitify "$W"
  local ok=1 out rc
  out="$(bash "$SCRIPTS/check-build-memory.sh" "$W" 2>&1)"; rc=$?
  [ "$rc" -eq 1 ] || { fail "v2-violations: check exit=$rc (want 1)"; ok=0; }
  # each seeded violation must be named
  for kw in "filename" "sequence" "forward dependency" "skeleton" "orphan) status" "Revisit trigger" "secret-shaped"; do
    printf '%s' "$out" | grep -qF "$kw" || { fail "v2-violations: output missing '$kw'"; ok=0; }
  done
  [ "$ok" = 1 ] && say "PASS v2-violations"
}

# ── Fixture 3: legacy-scratch ────────────────────────────────────────────────
test_legacy() {
  local W R; W="$(tmp)/repo"; R="$(tmp)/repo"
  cp -R "$HERE/legacy-scratch" "$W"; cp -R "$HERE/legacy-scratch" "$R"; gitify "$W"
  local ok=1 out rc mode
  # memory-root: scratch before migrate (no marker)
  mode="$(bash "$SCRIPTS/memory-root.sh" "$W" | sed -n 's/^mode=//p')"
  [ "$mode" = "scratch" ] || { fail "legacy: pre-migrate memory-root mode=$mode (want scratch)"; ok=0; }
  # validator: not a build-memory repo -> exit 2
  bash "$SCRIPTS/check-build-memory.sh" "$W" >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 2 ] || { fail "legacy: pre-migrate check exit=$rc (want 2)"; ok=0; }
  # migrate --apply
  bash "$SCRIPTS/migrate-legacy-scratch.sh" --from "$W/.agents/scratch" --apply >/dev/null 2>&1 \
    || { fail "legacy: migrate --apply failed"; ok=0; }
  for f in runs/P19.2.md runs/P20.3.md runs/P19.3.md runs/P21.9.md runs/implement-spec_scratchpad.md; do
    [ -f "$W/docs/build/$f" ] || { fail "legacy: expected docs/build/$f after migrate"; ok=0; }
  done
  [ "$(find "$W" -name '*.log' | wc -l | tr -d ' ')" = "0" ] || { fail "legacy: logs not dropped"; ok=0; }
  for k in manifest memoryRoot round; do
    grep -qE "^$k:" "$W/docs/build/LEDGER.md" || { fail "legacy: LEDGER.md missing added key '$k'"; ok=0; }
  done
  grep -q "Migration rename mapping" "$W/docs/build/README.md" || { fail "legacy: mapping not written to README"; ok=0; }
  # byte-identity of moved files vs pristine reference
  cmp -s "$W/docs/build/runs/P19.2.md" "$R/.agents/scratch/implement-spec_P19.2.md" || { fail "legacy: P19.2 not byte-identical"; ok=0; }
  cmp -s "$W/docs/build/runs/P20.3.md" "$R/.agents/scratch/implement-spec_p20-3_20260909.md" || { fail "legacy: P20.3 not byte-identical"; ok=0; }
  cmp -s "$W/docs/build/tools/gen.sh" "$R/.agents/scratch/tools/gen.sh" || { fail "legacy: gen.sh not byte-identical"; ok=0; }
  # memory-root now committed (migrate wrote the marker)
  mode="$(bash "$SCRIPTS/memory-root.sh" "$W" | sed -n 's/^mode=//p')"
  [ "$mode" = "committed" ] || { fail "legacy: post-migrate memory-root mode=$mode (want committed)"; ok=0; }
  [ "$ok" = 1 ] && say "PASS legacy-scratch"
}

# ── memory-root edge cases (AC2) ─────────────────────────────────────────────
test_memory_root() {
  local W; W="$(tmp)/repo"; mkdir -p "$W"; gitify "$W"
  local ok=1 mode root
  mode="$(bash "$SCRIPTS/memory-root.sh" "$W" | sed -n 's/^mode=//p')"
  [ "$mode" = "scratch" ] || { fail "memory-root: bare repo mode=$mode (want scratch)"; ok=0; }
  root="$(BUILD_MEMORY_ROOT=/opt/mem bash "$SCRIPTS/memory-root.sh" "$W" | sed -n 's/^root=//p')"
  [ "$root" = "/opt/mem" ] || { fail "memory-root: BUILD_MEMORY_ROOT override root=$root (want /opt/mem)"; ok=0; }
  [ "$ok" = 1 ] && say "PASS memory-root"
}

# ── adr-index: edit-one-title-changes-one-row (AC4) ──────────────────────────
test_adr_index() {
  local A; A="$(mktemp -d)/adr"; cp -R "$HERE/v2-clean/docs/adr" "$A"
  local ok=1
  # add a second valid ADR so "exactly one row" is observable
  cat > "$A/ADR-002-second.md" <<'EOF'
# ADR-002: Second decision

- **Status:** Accepted
- **Date:** 2026-09-09
- **Ticket:** T2
- **Requirement ids:** BM-DEMO-02

## Context
x
## Decision
y
## Consequences
z
## Alternatives considered
none
## Revisit trigger
revisit when x changes
EOF
  bash "$SCRIPTS/adr-index.sh" "$A" >/dev/null
  local before after
  before="$(mktemp)"; cp "$A/README.md" "$before"
  # regen is idempotent
  bash "$SCRIPTS/adr-index.sh" "$A" >/dev/null
  cmp -s "$before" "$A/README.md" || { fail "adr-index: not idempotent"; ok=0; }
  # edit exactly ADR-002's title
  sed -i.bak 's/^# ADR-002: Second decision/# ADR-002: Renamed decision/' "$A/ADR-002-second.md"; rm -f "$A/ADR-002-second.md.bak"
  bash "$SCRIPTS/adr-index.sh" "$A" >/dev/null
  after="$(mktemp)"; cp "$A/README.md" "$after"
  local changed; changed="$(diff "$before" "$after" | grep -cE '^[<>]')"
  [ "$changed" = "2" ] || { fail "adr-index: title edit changed $changed lines (want 2 = one row)"; ok=0; }
  rm -f "$before" "$after"
  [ "$ok" = 1 ] && say "PASS adr-index"
}

say "build-memory self-test"
test_clean
test_violations
test_legacy
test_memory_root
test_adr_index

if [ "$FAIL" -eq 0 ]; then
  say "ALL PASS"
  exit 0
fi
say "FAILURES above"
exit 1
