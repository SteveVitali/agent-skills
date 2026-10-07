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
  # SK-15: the bolded done entry is now evaluated (reported), the off-enum status, the PR-pending row of a
  # Closed: run ledger, a readout without the guard sentence, a future date (warnings: no guards marker)
  for kw in "~ index: PHASE LOG marks T9 done" "~ ledger-value: LEDGER.md CURRENT STATE projectStatus 'IN-PROGRESS'" \
            "T2 still reads 'PR pending' but runs/T2.md is Closed:" "~ readout: 1 readout(s) predate the guard sentence" \
            "~ clock: LEDGER.md: 1 PHASE LOG lead date(s) later than the clock"; do
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
  # SK-21: the header forms in use — an em-dash title, a Phase field, plain bullets, an appended Superseded line,
  # a `|` inside a value — are parsed; the legacy (0.4.0) rendering is kept behind --legacy
  printf '# ADR-003 — Em-dash title\n\n- **Status:** Accepted\n- **Phase:** P7.1\n\n## Revisit trigger\nx\n' > "$A/ADR-003-em.md"
  printf '# ADR-004: Plain bullets\n\n- Status: accepted (scoped | narrow)\n- Phase / ticket: P8.2 — wiring\n\n## Revisit trigger\nx\n\nStatus: Superseded by ADR-003 (2026-09-30)\n' > "$A/ADR-004-plain.md"
  bash "$SCRIPTS/adr-index.sh" --check "$A" > "$A/new.txt"
  grep -qF '| [ADR-003](ADR-003-em.md) | Em-dash title | P7.1 | Accepted |' "$A/new.txt" || { fail "adr-index: em-dash title / Phase field not parsed"; ok=0; }
  grep -qF '| [ADR-004](ADR-004-plain.md) | Plain bullets | P8.2 — wiring | Superseded by ADR-003 (2026-09-30) |' "$A/new.txt" || { fail "adr-index: plain bullets / Phase / ticket / Superseded line not parsed"; ok=0; }
  bash "$SCRIPTS/adr-index.sh" --check --legacy "$A" | grep -qF '| [ADR-003](ADR-003-em.md) | — | — | Accepted |' || { fail "adr-index: --legacy does not reproduce the 0.4.0 rendering"; ok=0; }
  # an index the 0.4.0 generator wrote is a warning, not a violation; a hand edit is still a violation
  local W; W="$(tmp)/repo"; cp -R "$HERE/v2-clean" "$W"; cp "$A/ADR-003-em.md" "$W/docs/adr/"
  bash "$SCRIPTS/adr-index.sh" --check --legacy "$W/docs/adr" > "$W/docs/adr/README.md"
  out="$(bash "$SCRIPTS/check-build-memory.sh" "$W" 2>&1)"; rc=$?
  { [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qF "was generated by the pre-0.5.0 parser"; } || { fail "adr-index: a legacy-generated index is not a warning (exit=$rc)"; ok=0; }
  printf 'hand edit\n' >> "$W/docs/adr/README.md"
  bash "$SCRIPTS/check-build-memory.sh" "$W" >/dev/null 2>&1; [ $? -eq 1 ] || { fail "adr-index: a hand-edited index is no longer a violation"; ok=0; }
  [ "$ok" = 1 ] && say "PASS adr-index"
}

# ── Fixture 4: v2-legacy-ledger — pre-0.3.0 shapes still validate (SK-14, SK-18) ──
test_legacy_ledger() {
  local W; W="$(tmp)/repo"; cp -R "$HERE/v2-legacy-ledger" "$W"; gitify "$W"
  local ok=1 out rc
  out="$(bash "$SCRIPTS/check-build-memory.sh" "$W" 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] || { fail "v2-legacy-ledger: check exit=$rc (want 0 — legacy content only warns)"; ok=0; }
  for kw in "'| PRIOR'" "returnPass is not" "older regions exceed 2 KiB" "D-T2-2 (kind P" ; do
    printf '%s' "$out" | grep -qF "$kw" || { fail "v2-legacy-ledger: output missing warning '$kw'"; ok=0; }
  done
  printf '%s' "$out" | grep -qF "D-T2-3 (kind P" && { fail "v2-legacy-ledger: scheduled P row D-T2-3 was flagged"; ok=0; }
  [ "$ok" = 1 ] && say "PASS v2-legacy-ledger"
}

# ── Fixture 5: v2-guards-violations — the guards marker turns BM-LEDGER-08 into failures ──
test_guards() {
  local W; W="$(tmp)/repo"; cp -R "$HERE/v2-guards-violations" "$W"; gitify "$W"
  local ok=1 out rc
  out="$(bash "$SCRIPTS/check-build-memory.sh" "$W" 2>&1)"; rc=$?
  [ "$rc" -eq 1 ] || { fail "v2-guards-violations: check exit=$rc (want 1)"; ok=0; }
  for kw in "over the 12 KiB budget" "> 256 B" "'| PRIOR'" "not a PHASE LOG heading" "guards marker: on"; do
    printf '%s' "$out" | grep -qF "$kw" || { fail "v2-guards-violations: output missing '$kw'"; ok=0; }
  done
  # SK-07/SK-15: stale orient text fails under the marker; SK-04: a run ledger created after the marker needs Harness:
  for kw in ".agents/scratch/demo-build-ledger.md" \
            "- ledger-stale: LEDGER.md orient region (line 7) carries the stale token '.agents/scratch'" \
            "- ledger-stale: LEDGER.md orient region (line 7) carries the stale token 'gitignored'" \
            "- harness: runs/T1.md has no 'Harness: <harness>/<model-id>/<tier>' header line"; do
    printf '%s' "$out" | grep -qF -- "$kw" || { fail "v2-guards-violations: output missing '$kw'"; ok=0; }
  done
  # SK-03: 7-column GATE DECISIONS — an off-vocabulary kind and an unscoped pre-authorization fail
  for kw in "GATE DECISIONS kind 'decided' is not one of" "a pre-authorization row lacks expires:"; do
    printf '%s\n' "$out" | grep -E '^    - gate: LEDGER.md line [0-9]+: ' | grep -qF "$kw" \
      || { fail "v2-guards-violations: output missing violation '$kw'"; ok=0; }
  done
  # the same tree without the marker only warns
  grep -v 'build-memory-guards' "$W/docs/build/README.md" > "$W/r.tmp" && mv "$W/r.tmp" "$W/docs/build/README.md"
  out="$(bash "$SCRIPTS/check-build-memory.sh" "$W" 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] || { fail "v2-guards-violations: without the marker exit=$rc (want 0)"; ok=0; }
  printf '%s\n' "$out" | grep -E '^    ~ gate: LEDGER.md line [0-9]+: ' | grep -qF "a pre-authorization row lacks expires:" \
    || { fail "v2-guards-violations: without the marker the pre-authorization row is not a warning"; ok=0; }
  [ "$ok" = 1 ] && say "PASS v2-guards-violations"
}

# ── LEDGER variants on v2-clean: harness slot, seed + DONE warnings, Status-line readouts ──
edit() { awk "$2" "$1" > "$1.tmp" && mv "$1.tmp" "$1"; }   # edit <file> <awk program>
test_ledger_variants() {
  local ok=1 W L out rc
  # harness: accepted only between round and updatedAt (SK-14)
  W="$(tmp)/repo"; cp -R "$HERE/v2-clean" "$W"; L="$W/docs/build/LEDGER.md"
  edit "$L" '/^updatedAt:/ {print "harness:         claude-code/model-x/manual"} {print}'
  bash "$SCRIPTS/check-build-memory.sh" "$W" >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 0 ] || { fail "variants: harness in its slot exit=$rc (want 0)"; ok=0; }
  W="$(tmp)/repo"; cp -R "$HERE/v2-clean" "$W"; L="$W/docs/build/LEDGER.md"
  edit "$L" '{print} /^projectStatus:/ {print "harness:         claude-code/model-x/manual"}'
  out="$(bash "$SCRIPTS/check-build-memory.sh" "$W" 2>&1)"; rc=$?
  { [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -qF "out of order"; } || { fail "variants: harness out of its slot not rejected (exit=$rc)"; ok=0; }
  # a seed ledger with a non-pre-authorization GATE DECISIONS row warns "pre-answered gate?" (SK-22)
  W="$(tmp)/repo"; cp -R "$HERE/v2-clean" "$W"; L="$W/docs/build/LEDGER.md"
  edit "$L" '/— T1 done —/ {next} {print} /^\|---\|---\|---\|---\|---\|---\|$/ && !d {print "| 2026-09-09 | T2 | G1 | all | \"proceed\" | pre-answered |"; d=1}'
  out="$(bash "$SCRIPTS/check-build-memory.sh" "$W" 2>&1)"
  printf '%s' "$out" | grep -qF "pre-answered gate?" || { fail "variants: seed with a GATE DECISIONS answer not warned"; ok=0; }
  W="$(tmp)/repo"; cp -R "$HERE/v2-clean" "$W"; L="$W/docs/build/LEDGER.md"
  edit "$L" '/— T1 done —/ {next} {print}'
  out="$(bash "$SCRIPTS/check-build-memory.sh" "$W" 2>&1)"
  printf '%s' "$out" | grep -qF "pre-answered gate?" && { fail "variants: empty seed GATE DECISIONS was warned"; ok=0; }
  # DONE without a signed GATE-ACCEPT readout warns; a SIGNED Status line clears it (SK-20)
  W="$(tmp)/repo"; cp -R "$HERE/v2-clean" "$W"; L="$W/docs/build/LEDGER.md"
  edit "$L" '{sub(/^projectStatus:[[:space:]]+IN_PROGRESS/, "projectStatus:   DONE")} {print}'
  out="$(bash "$SCRIPTS/check-build-memory.sh" "$W" 2>&1)"
  printf '%s' "$out" | grep -qF "GATE-ACCEPT.md is missing or not signed" || { fail "variants: DONE without GATE-ACCEPT not warned"; ok=0; }
  mkdir -p "$W/docs/build/readouts"
  sed -e 's/^Status: PENDING/Status: SIGNED/' "$HERE/../templates/READOUT.md" > "$W/docs/build/readouts/GATE-ACCEPT.md"
  out="$(bash "$SCRIPTS/check-build-memory.sh" "$W" 2>&1)"
  printf '%s' "$out" | grep -qF "GATE-ACCEPT.md is missing or not signed" && { fail "variants: signed GATE-ACCEPT still warned"; ok=0; }
  # SK-03: a 7-column GATE DECISIONS table — valid kinds pass silently; an off-vocabulary kind and a
  # pre-authorization without expires:/voided-by: warn (no guards marker); a 6-column table is not judged
  W="$(tmp)/repo"; cp -R "$HERE/v2-clean" "$W"; L="$W/docs/build/LEDGER.md"
  edit "$L" '/^## RETURN PASS/ {
    print "### Round 2"; print ""
    print "| date | ticket | gate | item | answer (verbatim) | consequence | kind |"
    print "|---|---|---|---|---|---|---|"
    print "| 2026-09-10T01:00:00Z | T2 | G1 | budget | \"yes, release it\" (chat) | recorder: budget released | decision |"
    print "| 2026-09-10T01:05:00Z | T2 | G1 | G1.2 | \"pre-approved: G1.2 only\" (chat) | recorder: G1.2 | pre-authorization · expires: T3 · voided-by: any new item |"
    print "| 2026-09-10T01:06:00Z | T2 | CI | #7 web | \"waive web on #7\" (chat) | recorder: waived | waiver |"
    print ""
  } {print}'
  sed -e 's/| recorder: G1.2 | pre-authorization · expires: T3 · voided-by: any new item |/| recorder: G1.2 · expires: T3 · voided-by: any new item | pre-authorization |/' "$L" > "$L.tmp" && mv "$L.tmp" "$L"
  out="$(bash "$SCRIPTS/check-build-memory.sh" "$W" 2>&1)"; rc=$?
  { [ "$rc" -eq 0 ] && ! printf '%s' "$out" | grep -qE '^    [-~] gate: LEDGER.md line'; } \
    || { fail "variants: a valid 7-column GATE DECISIONS table was flagged (exit=$rc)"; printf '%s\n' "$out" | sed 's/^/      /'; ok=0; }
  edit "$L" '{print} /^\| 2026-09-10T01:06:00Z/ {
    print "| 2026-09-10T02:00:00Z | T2 | G1 | all | \"approve everything\" (chat) | recorder: blanket | pre-authorization |"
    print "| 2026-09-10T02:01:00Z | T2 | G1 | G1.3 | \"I wonder if we should\" (chat) | recorder: hedge | maybe |"
  }'
  out="$(bash "$SCRIPTS/check-build-memory.sh" "$W" 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] || { fail "variants: 7-column gate rows failed without the guards marker (exit=$rc)"; ok=0; }
  printf '%s' "$out" | grep -qF "a pre-authorization row lacks expires:" || { fail "variants: unscoped pre-authorization not warned"; ok=0; }
  printf '%s' "$out" | grep -qF "kind 'maybe' is not one of" || { fail "variants: off-vocabulary kind not warned"; ok=0; }
  # a PENDING readout from templates/READOUT.md is not read as PASSED (its Status comment lists the values)
  W="$(tmp)/repo"; cp -R "$HERE/v2-clean" "$W"; mkdir -p "$W/docs/build/readouts"
  cp "$HERE/../templates/READOUT.md" "$W/docs/build/readouts/GATE-G1.md"
  printf '| D-T2-9 | gated by GATE-G1 | pending | GATE-G1 | readout | none | OPEN |\n' >> "$W/docs/tickets/DEFERRALS.md"
  bash "$SCRIPTS/check-build-memory.sh" "$W" >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 0 ] || { fail "variants: a PENDING template readout was read as PASSED (exit=$rc)"; ok=0; }
  [ "$ok" = 1 ] && say "PASS ledger-variants"
}

# ── SK-15 tree-mode truth checks and honest reporting (enum, vacuous, budgets, nextTicket, index, clock,
#    JSON identity), SK-04/05/07/12/21 tree checks — each fails against 0.4.0 ──────────────────────────
test_truth() {
  local ok=1 W L out rc j1 j2
  # vacuous: every done entry unparseable → exit 3, never a quiet pass
  W="$(tmp)/repo"; cp -R "$HERE/v2-vacuous" "$W"; gitify "$W"
  out="$(bash "$SCRIPTS/check-build-memory.sh" "$W" --json "$W/r.json" 2>&1)"; rc=$?
  { [ "$rc" -eq 3 ] && printf '%s' "$out" | grep -qF "vacuous: LEDGER.md: 2 PHASE LOG 'done' entr(y/ies) but only 0 parse"; } \
    || { fail "truth: v2-vacuous exit=$rc (want 3)"; ok=0; }
  grep -qE '"phase-log-done":\{"candidates":2,"evaluated":0\}' "$W/r.json" && grep -q '"exit":3' "$W/r.json" \
    || { fail "truth: vacuous counts/exit not in the JSON"; ok=0; }
  # the bolded legacy shape parses (markup stripped) and is evaluated
  W="$(tmp)/repo"; cp -R "$HERE/v2-clean" "$W"; L="$W/docs/build/LEDGER.md"
  edit "$L" '{sub(/— T1 done —/, "— **T1 seed-schema done** —")} {print}'
  out="$(bash "$SCRIPTS/check-build-memory.sh" "$W" --json "$W/r.json" 2>&1)"; rc=$?
  { [ "$rc" -eq 0 ] && grep -qE '"phase-log-done":\{"candidates":1,"evaluated":1\}' "$W/r.json"; } || { fail "truth: bolded done entry not evaluated (exit=$rc)"; ok=0; }
  # CURRENT STATE vocabularies: warn without the marker, fail with it
  W="$(tmp)/repo"; cp -R "$HERE/v2-clean" "$W"; L="$W/docs/build/LEDGER.md"
  edit "$L" '{sub(/^projectStatus:[[:space:]]+IN_PROGRESS/, "projectStatus:   IN-PROGRESS"); sub(/^round:[[:space:]]+1/, "round:           one"); sub(/^autonomy:[[:space:]]+checkpoint/, "autonomy:        yolo")} {print}'
  out="$(bash "$SCRIPTS/check-build-memory.sh" "$W" 2>&1)"; rc=$?
  { [ "$rc" -eq 0 ] && [ "$(printf '%s' "$out" | grep -c '~ ledger-value:')" = "3" ]; } || { fail "truth: off-vocabulary values not warned (exit=$rc)"; ok=0; }
  printf '<!-- build-memory-guards: 1 -->\n' >> "$W/docs/build/README.md"
  out="$(bash "$SCRIPTS/check-build-memory.sh" "$W" 2>&1)"; rc=$?
  { [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -qF -- "- ledger-value: LEDGER.md CURRENT STATE projectStatus 'IN-PROGRESS' is not one of"; } || { fail "truth: off-enum projectStatus does not fail under the marker (exit=$rc)"; ok=0; }
  # nextTicket must be the lowest chain row not landed (warn)
  W="$(tmp)/repo"; cp -R "$HERE/v2-clean" "$W"; L="$W/docs/build/LEDGER.md"
  edit "$L" '{sub(/^nextTicket:[[:space:]]+T2/, "nextTicket:      T1")} {print}'
  out="$(bash "$SCRIPTS/check-build-memory.sh" "$W" 2>&1)"; printf '%s' "$out" | grep -qF -- "nextTicket 'T1' is not the lowest chain row that has not landed ('T2'" || { fail "truth: stale nextTicket not warned"; ok=0; }
  out="$(bash "$SCRIPTS/check-build-memory.sh" "$HERE/v2-clean" 2>&1)"; printf '%s' "$out" | grep -qF -- "is not the lowest chain row" && { fail "truth: a correct nextTicket was warned"; ok=0; }
  # SK-05: a second close repair in the round with blockedOn empty warns
  W="$(tmp)/repo"; cp -R "$HERE/v2-clean" "$W"; L="$W/docs/build/LEDGER.md"
  printf -- '- 2026-09-09 — T1 repair — close: BUILD_INDEX row missing (worker x, interrupted)\n- 2026-09-10 — T2 repair — close: PHASE LOG entry missing (worker x)\n' >> "$L"
  out="$(bash "$SCRIPTS/check-build-memory.sh" "$W" 2>&1)"; printf '%s' "$out" | grep -qF -- "2 'repair — close:' entries in the current PHASE LOG region but blockedOn is empty" || { fail "truth: two close repairs not warned"; ok=0; }
  # stale orient text: paths resolve against the repo or the memory root; a repo can add tokens and retire a default
  W="$(tmp)/repo"; cp -R "$HERE/v2-clean" "$W"; L="$W/docs/build/LEDGER.md"; printf '# spec\n' > "$W/docs/spec.md"
  mkdir -p "$W/docs/build/tools/record_policy"
  edit "$L" '/^## CURRENT STATE/ {print "> - Was gitignored; history in `runs/T1.md`; see `docs/old/plan.md`; the Codex hand-off is closed."; print ""} {print}'
  printf 'Codex hand-off   # a repo token\n!gitignored\n' > "$W/docs/build/tools/record_policy/stale_tokens.txt"
  out="$(bash "$SCRIPTS/check-build-memory.sh" "$W" 2>&1)"
  printf '%s' "$out" | grep -qF "names 1 repo path(s) that do not exist (docs/old/plan.md)" || { fail "truth: stale path not reported (or runs/T1.md not resolved under the memory root)"; ok=0; }
  printf '%s' "$out" | grep -qF "carries the stale token 'Codex hand-off'" || { fail "truth: a repo stale token not reported"; ok=0; }
  printf '%s' "$out" | grep -qF "stale token 'gitignored'" && { fail "truth: '!gitignored' did not retire the default"; ok=0; }
  # BUILD_INDEX shape: column count, duplicate seq, vocabulary (warnings)
  W="$(tmp)/repo"; cp -R "$HERE/v2-clean" "$W"
  printf '| 01 | T2 | ticket | demo/t2 | #2 | demo/t1 | 2026-09-09 | — | a|b | done-ish | runs/T2.md |\n' >> "$W/docs/build/BUILD_INDEX.md"
  out="$(bash "$SCRIPTS/check-build-memory.sh" "$W" 2>&1)"; rc=$?
  for kw in "1 row(s) do not have the header's column count" "1 duplicate seq value(s)"; do
    printf '%s' "$out" | grep -qF "$kw" || { fail "truth: BUILD_INDEX '$kw' not warned"; ok=0; }
  done
  W="$(tmp)/repo"; cp -R "$HERE/v2-clean" "$W"
  printf '| 02 | T2 | ticket | demo/t2 | #2 | demo/t1 | 2026-09-09 | — | — | ran-it | runs/T2.md |\n' >> "$W/docs/build/BUILD_INDEX.md"
  out="$(bash "$SCRIPTS/check-build-memory.sh" "$W" 2>&1)"; printf '%s' "$out" | grep -qF -- "1 live-verification value(s) outside live-executed" || { fail "truth: off-vocabulary live verification not warned"; ok=0; }
  # the clock in tree mode: a future record date warns; future-ok exempts
  W="$(tmp)/repo"; cp -R "$HERE/v2-clean" "$W"; L="$W/docs/build/LEDGER.md"
  printf -- '- 2026-09-12 — T2 blocked — waiting\n' >> "$L"
  out="$(bash "$SCRIPTS/check-build-memory.sh" "$W" --now 2026-09-10T00:00:00Z 2>&1)"; printf '%s' "$out" | grep -qF -- "1 PHASE LOG lead date(s) later than the clock 2026-09-10 (first: line" || { fail "truth: future PHASE LOG date not warned"; ok=0; }
  edit "$L" '{sub(/— T2 blocked — waiting/, "— T2 blocked — waiting (future-ok: scheduled: the window opens 09-12)")} {print}'
  out="$(bash "$SCRIPTS/check-build-memory.sh" "$W" --now 2026-09-10T00:00:00Z 2>&1)"; printf '%s' "$out" | grep -qF -- "lead date(s) later than the clock" && { fail "truth: future-ok did not exempt"; ok=0; }
  # V13: chain rows outside a numbered round banner warn (v2-clean predates banners)
  out="$(bash "$SCRIPTS/check-build-memory.sh" "$HERE/v2-clean" 2>&1)"; printf '%s' "$out" | grep -qF -- "2 chain row(s) are not under a numbered '### Round <n>' banner" || { fail "truth: unbannered chain rows not warned"; ok=0; }
  # orient probe (BM-ORIENT-01): over 48 KiB warns
  W="$(tmp)/repo"; cp -R "$HERE/v2-clean" "$W"; L="$W/docs/build/LEDGER.md"
  edit "$L" '/^## CURRENT STATE/ { for (i = 0; i < 700; i++) printf "> padding line %03d of the orient region, which the recipe reads whole every session\n", i } {print}'
  out="$(bash "$SCRIPTS/check-build-memory.sh" "$W" 2>&1)"; printf '%s' "$out" | grep -qF -- "orient recipe reads" || { fail "truth: orient probe over 48 KiB not warned"; ok=0; }
  # BM-TEST-01: a tracked test that pins a living record warns living-pin?
  W="$(tmp)/repo"; cp -R "$HERE/v2-clean" "$W"; mkdir -p "$W/tests"
  printf 'def test_next():\n    text = open("docs/build/LEDGER.md").read()\n    assert "nextTicket:      T2" in text\n' > "$W/tests/test_state.py"
  printf 'def test_schema():\n    assert open("docs/build/LEDGER.md").read().count("## CURRENT STATE") == 1\n' > "$W/tests/test_shape.py"
  gitify "$W"
  out="$(bash "$SCRIPTS/check-build-memory.sh" "$W" 2>&1)"
  printf '%s' "$out" | grep -qF "living-pin?: tests/test_state.py:3 reads a living build record" || { fail "truth: living-record pin not warned"; ok=0; }
  printf '%s' "$out" | grep -qF "tests/test_shape.py" && { fail "truth: an invariant test was flagged"; ok=0; }
  # JSON identity: a unique default path per run, --json honoured, schema/input/summary.exit
  W="$(tmp)/repo"; cp -R "$HERE/v2-clean" "$W"; gitify "$W"
  j1="$(bash "$SCRIPTS/check-build-memory.sh" "$W" 2>&1 | sed -n 's/^  JSON: //p')" & j2="$(bash "$SCRIPTS/check-build-memory.sh" "$W" 2>&1 | sed -n 's/^  JSON: //p')"; wait
  j1="$(bash "$SCRIPTS/check-build-memory.sh" "$W" 2>&1 | sed -n 's/^  JSON: //p')"
  { [ -n "$j1" ] && [ -n "$j2" ] && [ "$j1" != "$j2" ] && [ "$j1" != /tmp/build-memory-check.json ]; } || { fail "truth: the default JSON path is not unique per run ('$j1' '$j2')"; ok=0; }
  bash "$SCRIPTS/check-build-memory.sh" "$W" --json "$W/out/r.json" >/dev/null 2>&1
  { grep -q '"schema":"build-memory-check/2"' "$W/out/r.json" && grep -qE '"input":\{"repo":"[^"]+","commit":"[0-9a-f]{40}","dirty":false,"input_digest":"[0-9a-f]{64}"' "$W/out/r.json" \
    && grep -q '"summary":{"violations":0,"warnings":[0-9]*,"exit":0}' "$W/out/r.json" && grep -q '"severity":"warning","file":' "$W/out/r.json"; } \
    || { fail "truth: --json report lacks schema / input identity / summary.exit / diagnostics"; ok=0; }
  [ "$ok" = 1 ] && say "PASS truth-checks"
}

# ── 0.5.1 — fixes from seeding SIG Round 11 (SEED-02a/02c/15); each assertion fails against 0.5.0 ──
test_051() {
  local ok=1 W L M out rc tok
  # the JSON report keeps every field under its own key: an empty file/obligation/evidence never shifts the
  # message (bash `read` merged adjacent tab separators — SIG L3); an unwritable --json path exits 2 (SIG L2)
  W="$(tmp)/repo"; cp -R "$HERE/v2-violations" "$W"; gitify "$W"
  bash "$SCRIPTS/check-build-memory.sh" "$W" --json "$W/r.json" >/dev/null 2>&1
  grep -q '"message":""' "$W/r.json" && { fail "0.5.1 report: a diagnostic has an empty message (a field shifted)"; ok=0; }
  for kw in '"file":"docs/tickets/00_MANIFEST.md","obligation":"","evidence":"","message":"4 chain row(s) are not under' \
            '"obligation":"T9","evidence":"","message":"PHASE LOG marks T9 done' \
            '"obligation":"","evidence":"T2","message":"ticket 01_T1__seed-schema.md depends on T2'; do
    grep -qF -- "$kw" "$W/r.json" || { fail "0.5.1 report: a field is not under its own key ($kw)"; ok=0; }
  done
  out="$(bash "$SCRIPTS/check-build-memory.sh" "$HERE/v2-clean" --json /dev/null/nope/r.json 2>&1)"; rc=$?
  { [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -qF "cannot write report to /dev/null/nope/r.json"; } \
    || { fail "0.5.1 report: an unwritable --json path exit=$rc (want 2)"; ok=0; }
  # a run ledger is Closed: only by a dated stamp in its header — `- **Closed:** none.` in a body section
  # (deferrals closed) is not a close (SEED-02a)
  W="$(tmp)/repo"; cp -R "$HERE/v2-clean" "$W"
  printf '| 02 | T2 | ticket | demo/t2 | PR pending | demo/t1 | 2026-09-09 | — | — | n-a | runs/T2.md |\n' >> "$W/docs/build/BUILD_INDEX.md"
  printf '# T2 — run ledger\n\n- **Spec / Base / Branch / Config:** x\n\n## Deferrals opened / closed\n- **Opened:** none.\n- **Closed:** none.\n' > "$W/docs/build/runs/T2.md"
  out="$(bash "$SCRIPTS/check-build-memory.sh" "$W" 2>&1)"
  printf '%s' "$out" | grep -qF "runs/T2.md is Closed:" && { fail "0.5.1 closed: a body 'Closed: none.' line was read as a closed run ledger"; ok=0; }
  edit "$W/docs/build/runs/T2.md" '{print} /^- \*\*Spec/ {print "- **Closed:** 2026-09-09T12:00:00Z"}'
  out="$(bash "$SCRIPTS/check-build-memory.sh" "$W" 2>&1)"
  printf '%s' "$out" | grep -qF "T2 still reads 'PR pending' but runs/T2.md is Closed:" || { fail "0.5.1 closed: a dated header Closed: stamp was not read"; ok=0; }
  # V2: only an explicit gate-cell token takes a row out of the nextTicket order (SIG audit_current_state.py;
  # SEED-15) — a skip word in the scope/title never does
  W="$(tmp)/repo"; cp -R "$HERE/v2-clean" "$W"; L="$W/docs/build/LEDGER.md"; M="$W/docs/tickets/00_MANIFEST.md"
  edit "$M" '{sub(/\| wire the consumers \| — \|/, "| wire the deferred parser layers; drop the unused shims | — |")} {print}'
  out="$(bash "$SCRIPTS/check-build-memory.sh" "$W" 2>&1)"
  printf '%s' "$out" | grep -qF "is not the lowest chain row" && { fail "0.5.1 V2: a skip word in the scope cell took T2 out of the order"; ok=0; }
  edit "$L" '{sub(/^nextTicket:[[:space:]]+T2/, "nextTicket:      DONE")} {print}'
  out="$(bash "$SCRIPTS/check-build-memory.sh" "$W" 2>&1)"
  { printf '%s' "$out" | grep -qF "nextTicket 'DONE' is not the lowest chain row that has not landed ('T2'" \
    && printf '%s' "$out" | grep -qF "row T2 says 'deferred' outside its gate cell"; } || { fail "0.5.1 V2: a prose-only skip word was honoured (or not explained)"; ok=0; }
  for tok in 'superseded-by(T2a, T2b)' 'superseded-by-split' 'deferred(D-T2-1)' 'unused'; do
    W="$(tmp)/repo"; cp -R "$HERE/v2-clean" "$W"; L="$W/docs/build/LEDGER.md"; M="$W/docs/tickets/00_MANIFEST.md"
    edit "$M" '{sub(/\| wire the consumers \| — \|/, "| wire the consumers | — · '"$tok"' |")} {print}'
    edit "$L" '{sub(/^nextTicket:[[:space:]]+T2/, "nextTicket:      DONE")} {print}'
    out="$(bash "$SCRIPTS/check-build-memory.sh" "$W" 2>&1)"
    printf '%s' "$out" | grep -qE "is not the lowest chain row|bare word in the gate cell" && { fail "0.5.1 V2: the gate-cell token '$tok' did not skip T2 silently"; ok=0; }
  done
  # legacy: a bare word in the gate cell still skips, with a warning naming the token (old manifests keep working)
  W="$(tmp)/repo"; cp -R "$HERE/v2-clean" "$W"; L="$W/docs/build/LEDGER.md"; M="$W/docs/tickets/00_MANIFEST.md"
  edit "$M" '{sub(/\| wire the consumers \| — \|/, "| wire the consumers | superseded by T2a/T2b |")} {print}'
  edit "$L" '{sub(/^nextTicket:[[:space:]]+T2/, "nextTicket:      DONE")} {print}'
  out="$(bash "$SCRIPTS/check-build-memory.sh" "$W" 2>&1)"; rc=$?
  { [ "$rc" -eq 0 ] && ! printf '%s' "$out" | grep -qF "is not the lowest chain row" \
    && printf '%s' "$out" | grep -qF "~ manifest: chain row(s) T2 ('superseded') are out of the nextTicket order only by a bare word in the gate cell"; } \
    || { fail "0.5.1 V2: a legacy bare gate-cell word is not 'skip + warn' (exit=$rc)"; ok=0; }
  [ "$ok" = 1 ] && say "PASS 0.5.1-fixes"
}

# ── SK-04/SK-17/SK-21 under the guards marker: new files must comply, older ones only warn ──
test_new_files() {
  local ok=1 W out rc
  W="$(tmp)/repo"; cp -R "$HERE/v2-clean" "$W"; printf '# demo spec\n' > "$W/docs/spec.md"; gitify "$W"
  mkdir -p "$W/docs/build/readouts"
  printf '# GATE-G1 readout\nStatus: PENDING\n\n## Criterion (verbatim)\nx\n' > "$W/docs/build/readouts/GATE-G1.md"   # predates the marker
  ( cd "$W" && git add -A && git -c user.email=t@t -c user.name=t commit -qm old ) >/dev/null 2>&1
  printf '<!-- build-memory-guards: 1 -->\n' >> "$W/docs/build/README.md"
  ( cd "$W" && git add -A && git -c user.email=t@t -c user.name=t commit -qm guards ) >/dev/null 2>&1
  out="$(bash "$SCRIPTS/check-build-memory.sh" "$W" 2>&1)"; rc=$?
  { [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qF "~ readout: 1 readout(s) predate the guard sentence" && printf '%s' "$out" | grep -qF "~ harness: 1 run ledger(s) have no 'Harness:'"; } \
    || { fail "new-files: files older than the marker did not stay warnings (exit=$rc)"; printf '%s\n' "$out" | sed 's/^/      /'; ok=0; }
  printf '# GATE-G2 readout\nStatus: PENDING\n' > "$W/docs/build/readouts/GATE-G2.md"
  printf '# T2 — run ledger\n- **Spec / Base / Branch / Config:** x\n' > "$W/docs/build/runs/T2.md"
  printf '# Decision two\n\n- Owner: me\n\n## Revisit trigger\nnever\n' > "$W/docs/adr/ADR-002-two.md"; bash "$SCRIPTS/adr-index.sh" "$W/docs/adr" >/dev/null
  out="$(bash "$SCRIPTS/check-build-memory.sh" "$W" 2>&1)"; rc=$?
  for kw in "- readout: readouts/GATE-G2.md lacks the guard sentence" "- harness: runs/T2.md has no 'Harness:" "- adr: ADR-002-two.md: an ADR index cell reads '—'"; do
    printf '%s' "$out" | grep -qF -- "$kw" || { fail "new-files: '$kw' not a violation"; ok=0; }
  done
  [ "$rc" -eq 1 ] || { fail "new-files: exit=$rc (want 1)"; ok=0; }
  { printf 'Harness: devin-desktop/swe-2-high/manual\n'; cat "$W/docs/build/runs/T2.md"; } > "$W/t" && mv "$W/t" "$W/docs/build/runs/T2.md"
  out="$(bash "$SCRIPTS/check-build-memory.sh" "$W" 2>&1)"; printf '%s' "$out" | grep -qF -- "runs/T2.md has no" && { fail "new-files: a Harness: line did not satisfy BM-HARNESS-01"; ok=0; }
  [ "$ok" = 1 ] && say "PASS new-files"
}

# ── SK-25: planning-ledger freshness (V14) ────────────────────────────────────
test_planning() {
  local ok=1 W P out rc
  W="$(tmp)/repo"; mkdir -p "$W/docs"; P="$W/docs/research-ledger.md"
  cat > "$P" <<'EOR'
# demo — research & design ledger

## CURRENT STATE

```
projectStatus:   IN_PROGRESS
nextUnit:        A2
lastCompleted:   A1
blockedOn:       (nothing)
pauseRequested:  false
round:           1
updatedAt:       2026-09-30T18:00:00Z
```

## A. Ground truth

| id | item | owner | status | evidence |
|---|---|---|---|---|
| A1 | read the code | R | done | research/01_code.md |
| A2 | read the data | R | done | research/02_data.md |
| A3 | design | D | open | |

## Change log
- 2026-09-30T17:00:00Z — ledger created.
- 2026-09-30T18:00:00Z — A1 done.
- 2026-09-30T18:25:00Z — A2 done.
EOR
  out="$(bash "$SCRIPTS/check-build-memory.sh" "$W" --planning docs/research-ledger.md 2>&1)"; rc=$?
  [ "$rc" -eq 1 ] || { fail "planning: a stale CURRENT STATE passed (exit=$rc)"; ok=0; }
  for kw in "updatedAt 2026-09-30T18:00:00Z is older than the newest change-log stamp 2026-09-30T18:25:00Z" \
            "lastCompleted 'A1' is not the newest done row named in the change log" "nextUnit 'A2' is already a done row"; do
    printf '%s' "$out" | grep -qF "$kw" || { fail "planning: output lacks '$kw'"; ok=0; }
  done
  edit "$P" '{sub(/^nextUnit:[[:space:]]+A2/, "nextUnit:        A3"); sub(/^lastCompleted:[[:space:]]+A1/, "lastCompleted:   A2"); sub(/^updatedAt:.*/, "updatedAt:       2026-09-30T18:25:00Z")} {print}'
  bash "$SCRIPTS/check-build-memory.sh" "$W" --planning docs/research-ledger.md >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 0 ] || { fail "planning: a fresh CURRENT STATE failed (exit=$rc)"; ok=0; }
  bash "$SCRIPTS/check-build-memory.sh" "$W" --planning docs/nope.md >/dev/null 2>&1; [ $? -eq 2 ] || { fail "planning: a missing ledger is not exit 2"; ok=0; }
  [ "$ok" = 1 ] && say "PASS planning-v14"
}

# ── history mode (SK-16): tests/history/build.sh ──────────────────────────────
test_history() { bash "$HERE/history/build.sh" || FAIL=1; }

# ── Template golden checks (SK-13, SK-14, SK-17..SK-20, SK-22) ──────────────────
test_templates() {
  local T="$HERE/../templates" DS="$HERE/../../decompose-spec/SKILL.md" LAY="$HERE/../layout.md" ok=1 f
  # SK-13: no bare date placeholder anywhere in templates/
  grep -rnE '<date>|<ISO date>' "$T" >/dev/null && { fail "templates: a bare <date> placeholder remains"; ok=0; }
  # SK-17: the guard sentence is in every readout-bearing template
  for f in READOUT.md GATE.md HUMAN.md tail/GATE-ACCEPT.md; do
    tr '\n' ' ' < "$T/$f" | sed -E 's/[[:space:]>]+/ /g' | grep -qF "an agent must not sign or assume silence is approval" \
      || { fail "templates: $f lacks the guard sentence"; ok=0; }
  done
  for kw in "**Owner:**" "**Scheduled:**" "**Withheld until done:**" "**Deferrals so far:**"; do
    grep -qF "$kw" "$T/HUMAN.md" || { fail "templates: HUMAN.md lacks $kw"; ok=0; }
  done
  grep -qE '^Status: PENDING' "$T/READOUT.md" || { fail "templates: READOUT.md lacks the Status line"; ok=0; }
  # SK-18: contract header + operating clauses; manifest operating rules + round banner; DEFERRALS rule 5
  for kw in "**Production mutations:**" "**Size budget:**" "## Operating clauses" "layer: engineered"; do
    grep -qF "$kw" "$T/ticket.md" || { fail "templates: ticket.md lacks '$kw'"; ok=0; }
  done
  grep -qE '^## Operating rules' "$T/MANIFEST.md" || { fail "templates: MANIFEST.md lacks ## Operating rules"; ok=0; }
  grep -qE '^### Round 1 ' "$T/MANIFEST.md" || { fail "templates: MANIFEST.md lacks a round banner"; ok=0; }
  grep -qF "5. **Human work is scheduled" "$T/DEFERRALS.md" || { fail "templates: DEFERRALS.md lacks rule 5"; ok=0; }
  # SK-14: LEDGER seed — PHASE LOG — Round 1 last, 7-column GATE DECISIONS with no rows, harness slot
  [ "$(grep -E '^## ' "$T/LEDGER.md" | tail -1)" = "## PHASE LOG — Round 1" ] || { fail "templates: LEDGER.md last heading is not '## PHASE LOG — Round 1'"; ok=0; }
  grep -qF "| date | ticket | gate | item | answer (verbatim) | consequence | kind |" "$T/LEDGER.md" || { fail "templates: LEDGER.md GATE DECISIONS is not 7-column"; ok=0; }
  [ "$(awk '/^## GATE DECISIONS/{f=1;next} /^## /{f=0} f && /^\|/' "$T/LEDGER.md" | wc -l | tr -d ' ')" = "2" ] || { fail "templates: LEDGER.md seed GATE DECISIONS is not empty"; ok=0; }
  grep -qE '^harness:' "$T/LEDGER.md" || { fail "templates: LEDGER.md lacks the harness slot"; ok=0; }
  grep -qF "| evidence | harness |" "$T/BUILD_INDEX.md" || { fail "templates: BUILD_INDEX.md lacks the harness column"; ok=0; }
  # SK-19: matrix columns appended; verdict vocabulary; two sums
  head -1 "$T/COVERAGE_MATRIX.csv" | grep -qE ',note,required_domain,achieved_domain,owed_legs,accepted_scope$' || { fail "templates: COVERAGE_MATRIX.csv columns not appended"; ok=0; }
  for kw in "MET-ENGINEERED" "WAIVED" "owed_legs"; do grep -qF "$kw" "$T/tail/CAP.1__capstone-gap-analysis.md" || { fail "templates: CAP.1 lacks $kw"; ok=0; }; done
  for kw in "*engineering closed*" "*requirement satisfied*"; do grep -qF "$kw" "$T/tail/CAP.3__capstone-closure.md" || { fail "templates: CAP.3 lacks $kw"; ok=0; }; done
  grep -qF "never raises a verdict" "$T/tail/GATE-ACCEPT.md" || { fail "templates: GATE-ACCEPT lacks the scoped-acceptance rule"; ok=0; }
  # SK-20: every tail file has a live-read AC; the minimal tail keeps GATE-ACCEPT (layout + decompose-spec)
  for f in "$T"/tail/*.md; do grep -qF '*(live-read)*' "$f" || { fail "templates: $(basename "$f") lacks a (live-read) AC"; ok=0; }; done
  grep -qF '`tail=minimal` (default: `CAP.1`, `CAP.3`, `GATE-ACCEPT`, `DOC`' "$LAY" || { fail "layout: minimal tail does not include GATE-ACCEPT"; ok=0; }
  # SK-22: decompose-spec — minimal default incl. GATE-ACCEPT; never pre-answer; scheduled human rows; round banner
  grep -qF "'minimal' (default" "$DS" || { fail "decompose-spec: tail default is not minimal"; ok=0; }
  grep -qF "CAP.1, CAP.3, GATE-ACCEPT, DOC" "$DS" || { fail "decompose-spec: minimal tail lacks GATE-ACCEPT"; ok=0; }
  for kw in "Never pre-answer a gate" "HUMAN rows are scheduled like tickets" "round banner" "## Operating rules"; do
    grep -qF "$kw" "$DS" || { fail "decompose-spec: lacks '$kw'"; ok=0; }
  done
  # forward-referenced rule ids cited by the templates resolve in layout.md
  for id in BM-CLOCK-01 BM-CI-01 BM-STATUS-01 BM-VERDICT-01 BM-PROD-01 BM-TEST-01 BM-HARNESS-01 BM-ORIENT-01 BM-LEDGER-08 BM-TAIL-04 BM-COMPAT-06; do
    grep -qF "$id" "$LAY" || { fail "layout: rule id $id is cited but not defined"; ok=0; }
  done
  [ "$ok" = 1 ] && say "PASS templates"
}

# ── A seed instantiated from the templates validates clean under the guards marker ──
test_seed_from_templates() {
  local T="$HERE/../templates" W ok=1 out rc
  W="$(tmp)/repo"; mkdir -p "$W/docs/build/logs" "$W/docs/build/readouts" "$W/docs/tickets" "$W/docs/adr"
  { cat "$T/build-README.md"; printf '<!-- build-memory-guards: 1 -->\n'; } > "$W/docs/build/README.md"
  cp "$T/LEDGER.md" "$W/docs/build/LEDGER.md"; cp "$T/BUILD_INDEX.md" "$W/docs/build/BUILD_INDEX.md"
  cp "$T/READOUT.md" "$W/docs/build/readouts/_TEMPLATE.md"
  printf '*\n!.gitignore\n' > "$W/docs/build/logs/.gitignore"
  sed -e 's/`01_<ID>__<slug>\.md`/`01_T1__demo.md`/' "$T/MANIFEST.md" > "$W/docs/tickets/00_MANIFEST.md"
  sed -e 's/<ID>/T1/g' "$T/ticket.md" > "$W/docs/tickets/01_T1__demo.md"
  cp "$T/ticket.md" "$W/docs/tickets/_TEMPLATE.md"; cp "$T/DEFERRALS.md" "$W/docs/tickets/DEFERRALS.md"
  cp "$T/adr-TEMPLATE.md" "$W/docs/adr/_TEMPLATE.md"; bash "$SCRIPTS/adr-index.sh" "$W/docs/adr" >/dev/null 2>&1
  gitify "$W"
  out="$(bash "$SCRIPTS/check-build-memory.sh" "$W" 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] || { fail "seed-from-templates: check exit=$rc (want 0)"; printf '%s\n' "$out" | sed 's/^/      /'; ok=0; }
  printf '%s' "$out" | grep -qF "(0 warning(s))" || { fail "seed-from-templates: a fresh seed raised warnings"; printf '%s\n' "$out" | sed 's/^/      /'; ok=0; }
  [ "$ok" = 1 ] && say "PASS seed-from-templates"
}

# ── Clock: migrate records the UTC date in any local timezone (SK-13) ──────────
test_clock_tz() {
  local ok=1 tz W want
  for tz in Pacific/Kiritimati Pacific/Pago_Pago; do
    W="$(tmp)/repo"; cp -R "$HERE/legacy-scratch" "$W"; gitify "$W"
    want="$(date -u +%Y-%m-%d)"
    TZ="$tz" bash "$SCRIPTS/migrate-legacy-scratch.sh" --from "$W/.agents/scratch" --apply >/dev/null 2>&1 \
      || { fail "clock: migrate --apply failed under TZ=$tz"; ok=0; continue; }
    grep -q "migrate\` on $want\." "$W/docs/build/README.md" \
      || grep -q "migrate\` on $(date -u +%Y-%m-%d)\." "$W/docs/build/README.md" \
      || { fail "clock: migrate under TZ=$tz did not record the UTC date $want"; ok=0; }
  done
  [ "$ok" = 1 ] && say "PASS clock-tz"
}

# ── Fixture: v2-reqcov — non-literal spec ids and the literal requirement index (OF-21) ──
test_reqcov() {
  local W B ok=1 out rc
  W="$(tmp)/repo"; cp -R "$HERE/v2-reqcov" "$W"; gitify "$W"
  out="$(bash "$SCRIPTS/check-build-memory.sh" "$W" 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] || { fail "v2-reqcov: clean check exit=$rc (want 0)"; ok=0; }
  printf '%s' "$out" | grep -qE 'reqcov|reqindex' && { fail "v2-reqcov: range/continuation/list ids drew a reqcov or reqindex finding"; ok=0; }
  # seeded defects: a range row, an unknown id, a twice-indexed id, an owner that is no ticket, an unindexed stamp
  B="$(tmp)/repo"; cp -R "$HERE/v2-reqcov" "$B"
  printf '%s\n' '| `BM-ENG-1…4` | T4 |' '| `BM-NOPE-9` | T3 |' '| `BM-STATE-3` | T4 |' '| `BM-ENG-2` | T9 |' > "$B/rows.tmp"
  awk -v F="$B/rows.tmp" '{ print } /^\| `BM-ENG-3` \| T4 \|$/ { while ((getline l < F) > 0) print l }' "$B/docs/tickets/00_MANIFEST.md" > "$B/m.tmp" \
    && mv "$B/m.tmp" "$B/docs/tickets/00_MANIFEST.md"; rm -f "$B/rows.tmp"
  sed 's/^BM-HYP-2, BM-ENG-3\.$/BM-HYP-2, BM-ENG-3, BM-ENG-4./' "$B/docs/tickets/04_T4__engine-and-hypotheses.md" > "$B/t.tmp" \
    && mv "$B/t.tmp" "$B/docs/tickets/04_T4__engine-and-hypotheses.md"
  gitify "$B"
  out="$(bash "$SCRIPTS/check-build-memory.sh" "$B" 2>&1)"; rc=$?
  [ "$rc" -eq 1 ] || { fail "v2-reqcov: seeded check exit=$rc (want 1)"; ok=0; }
  for kw in "'BM-ENG-1…4' is not exactly one literal requirement id" "BM-NOPE-9 (line" "lists BM-STATE-3 twice" \
            "names owner 'T9'" "stamps BM-ENG-4 but the manifest index assigns it to 'nothing'"; do
    printf '%s' "$out" | grep -qF "$kw" || { fail "v2-reqcov: output missing '$kw'"; ok=0; }
  done
  [ "$ok" = 1 ] && say "PASS v2-reqcov"
}

# ── 0.5.3 — validator false positives found closing the fsq cost build (BL-60, BL-61, T44) ──
# Each "false positive" assertion fails against 0.5.2; each "true positive" one passes on both.
test_053() {
  local ok=1 W L D out rc
  # BL-60: OPEN × PASSED reads the row's leading status and the gate the row is owed to (its
  # `unblocked by` cell, or "owed at <gate>" in its status cell) — not a gate or an "open" anywhere
  W="$(tmp)/repo"; cp -R "$HERE/v2-clean" "$W"; D="$W/docs/tickets/DEFERRALS.md"; mkdir -p "$W/docs/build/readouts"
  printf '# GATE-G1 readout\nStatus: PASSED\n' > "$W/docs/build/readouts/GATE-G1.md"
  cat >> "$D" <<'EOF'
| D-T2-2 | drawer copy | time | T9 | open a team drawer; GATE-G1 named it | none | WONTFIX — copy dropped |
| D-T2-3 | gate metric | data | GATE-G1 | rerun | none | DONE 2026-09-10 (rerun green) — was: OPEN, owed at GATE-G1 |
| D-T2-4 | OPEN FINDINGS tidy | time | T9 | read GATE-G1 | none | DONE 2026-09-10 |
| D-T2-5 | later leg | budget | T9 | rerun | none | OPEN — routed to T9 by readouts/GATE-G1.md after GATE-G1 passed |
| D-T2-6 | other gate | budget | GATE-G10 | rerun | none | OPEN |
| D-T2-13 | re-owned | budget | GATE-G1 | rerun | none | OPEN — owed at T9 (re-owned by the GATE-G1 readout) |
EOF
  out="$(bash "$SCRIPTS/check-build-memory.sh" "$W" 2>&1)"; rc=$?
  { [ "$rc" -eq 0 ] && ! printf '%s' "$out" | grep -qF "owed to GATE-G1"; } \
    || { fail "0.5.3 BL-60: a mention of a PASSED gate (or a lowercase 'open') failed the check (exit=$rc)"; printf '%s\n' "$out" | grep deferrals | sed 's/^/      /'; ok=0; }
  # true positives: an OPEN row owed to the passed gate — by `unblocked by`, or "owed at" in the status cell
  printf '| D-T2-7 | live leg | budget | GATE-G1 | rerun | none | OPEN |\n| D-T2-8 | live leg 2 | budget | T9 | rerun | none | **OPEN** — owed at `GATE-G1` |\n' >> "$D"
  out="$(bash "$SCRIPTS/check-build-memory.sh" "$W" 2>&1)"; rc=$?
  { [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -qF "OPEN DEFERRALS row(s) D-T2-7 D-T2-8 owed to GATE-G1, whose readout says PASSED"; } \
    || { fail "0.5.3 BL-60: an OPEN row owed to a PASSED gate was not failed (exit=$rc)"; ok=0; }
  # BL-61: the leading status wins — a DONE kind-P row whose kept history says OPEN is not owed (no rule-5
  # warning); an OPEN one still warns; a cell with no canonical status is still an orphan
  W="$(tmp)/repo"; cp -R "$HERE/v2-clean" "$W"; D="$W/docs/tickets/DEFERRALS.md"
  printf '\n| id | item | why deferred | unblocked by | how to verify | proxy now | kind | status |\n|---|---|---|---|---|---|---|---|\n' >> "$D"
  printf '| D-T2-9 | sign | operator only | the operator | readout | none | P | DONE 2026-09-10 (signed) — was: OPEN |\n' >> "$D"
  printf '| D-T2-10 | sign 2 | operator only | the operator | readout | none | P | Verified DONE 2026-09-10; OPEN only for a live fixture |\n' >> "$D"
  out="$(bash "$SCRIPTS/check-build-memory.sh" "$W" 2>&1)"; rc=$?
  { [ "$rc" -eq 0 ] && ! printf '%s' "$out" | grep -qF "kind P, still owed"; } \
    || { fail "0.5.3 BL-61: a DONE row whose history says OPEN was read as OPEN (exit=$rc)"; printf '%s\n' "$out" | grep deferrals | sed 's/^/      /'; ok=0; }
  printf '| D-T2-11 | sign 3 | operator only | the operator | readout | none | P | **OPEN** (2026-09-10) — was DONE in error |\n| D-T2-12 | odd | x | T9 | x | none | P | ROOT-CAUSED |\n' >> "$D"
  out="$(bash "$SCRIPTS/check-build-memory.sh" "$W" 2>&1)"; rc=$?
  { [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -qF "DEFERRALS row D-T2-11 (kind P, still owed)" \
    && printf '%s' "$out" | grep -qF "DEFERRALS row D-T2-12 has an invalid (orphan) status 'ROOT-CAUSED'"; } \
    || { fail "0.5.3 BL-61: an OPEN P row was not warned, or an orphan status passed (exit=$rc)"; ok=0; }
  # T44: "done" inside a branch name, path or file name is not a ticket-close word
  W="$(tmp)/repo"; cp -R "$HERE/v2-clean" "$W"; L="$W/docs/build/LEDGER.md"
  cat >> "$L" <<'EOF'
- 2026-09-10 — DONE · branch svitali/round3-t2-text-done · PR #2 · next → DONE
- 2026-09-10 — T2 landed · branch demo/done · next → DONE
- 2026-09-10 — T2 landed · see docs/build/done/notes.md and pr/done.md · next → DONE
- note: branch feature/done merged
EOF
  out="$(bash "$SCRIPTS/check-build-memory.sh" "$W" --json "$W/r.json" 2>&1)"; rc=$?
  { [ "$rc" -eq 0 ] && ! printf '%s' "$out" | grep -qF "PHASE LOG marks" && grep -qF '"phase-log-done":{"candidates":1,"evaluated":1}' "$W/r.json"; } \
    || { fail "0.5.3 T44: a branch or path ending in 'done' was read as a ticket close (exit=$rc)"; printf '%s\n' "$out" | grep -E 'index|vacuous' | sed 's/^/      /'; ok=0; }
  # true positive: a real "T2 done" entry (whose branch also ends in -done) still demands its index row + run file
  printf -- '- 2026-09-10 — T2 done — branch demo/t2-done · PR #2 · next → DONE\n' >> "$L"
  out="$(bash "$SCRIPTS/check-build-memory.sh" "$W" 2>&1)"; rc=$?
  { [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -qF "PHASE LOG marks T2 done (line" \
    && printf '%s' "$out" | grep -qF "BUILD_INDEX.md has no row for it"; } \
    || { fail "0.5.3 T44: a real T2 done entry without a BUILD_INDEX row passed (exit=$rc)"; ok=0; }
  [ "$ok" = 1 ] && say "PASS 0.5.3-fixes"
}

say "build-memory self-test"
test_clean
test_violations
test_legacy
test_memory_root
test_adr_index
test_legacy_ledger
test_guards
test_ledger_variants
test_templates
test_seed_from_templates
test_clock_tz
test_truth
test_051
test_new_files
test_planning
test_history
test_reqcov
test_053

if [ "$FAIL" -eq 0 ]; then
  say "ALL PASS"
  exit 0
fi
say "FAILURES above"
exit 1
