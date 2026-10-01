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
  # the same tree without the marker only warns
  grep -v 'build-memory-guards' "$W/docs/build/README.md" > "$W/r.tmp" && mv "$W/r.tmp" "$W/docs/build/README.md"
  bash "$SCRIPTS/check-build-memory.sh" "$W" >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 0 ] || { fail "v2-guards-violations: without the marker exit=$rc (want 0)"; ok=0; }
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
  # a PENDING readout from templates/READOUT.md is not read as PASSED (its Status comment lists the values)
  W="$(tmp)/repo"; cp -R "$HERE/v2-clean" "$W"; mkdir -p "$W/docs/build/readouts"
  cp "$HERE/../templates/READOUT.md" "$W/docs/build/readouts/GATE-G1.md"
  printf '| D-T2-9 | gated by GATE-G1 | pending | GATE-G1 | readout | none | OPEN |\n' >> "$W/docs/tickets/DEFERRALS.md"
  bash "$SCRIPTS/check-build-memory.sh" "$W" >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 0 ] || { fail "variants: a PENDING template readout was read as PASSED (exit=$rc)"; ok=0; }
  [ "$ok" = 1 ] && say "PASS ledger-variants"
}

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

if [ "$FAIL" -eq 0 ]; then
  say "ALL PASS"
  exit 0
fi
say "FAILURES above"
exit 1
