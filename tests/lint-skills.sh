#!/usr/bin/env bash
# lint-skills.sh — skill-text lint: retired phrases stay retired, required rules stay present, and
# every BM-* rule id the build skills cite resolves. (B6 §6.7; the prose layer of SK-01…SK-25.)
#
# Usage:   tests/lint-skills.sh            (from anywhere; paths are relative to this repo)
# Exit codes: 0 — clean; 1 — a lint failed.
# Compatible with bash 3.2+ (macOS default). Read-only.

set -o pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S="$ROOT/skills"
OB="$S/orchestrate-build/SKILL.md" ; IS="$S/implement-spec/SKILL.md" ; LAY="$S/build-memory/layout.md"
FAIL=0
fail() { printf '  ✗ %s\n' "$*"; FAIL=1; }

# 1. Retired phrases — each, followed literally, reproduced an observed failure.
retired() {   # retired <ERE> <label> <files…>
  local re="$1" label="$2" hit; shift 2
  hit="$(grep -nE "$re" "$@" 2>/dev/null | head -3)"
  [ -z "$hit" ] || fail "retired phrase ($label) is back: $hit"
}
retired '[Nn]o CI[- ]poll' '"No CI polling" — SK-01/SK-10' "$S"/*/SKILL.md "$S"/*/README.md "$LAY"
retired 'treats? (every|all) items? as' '"auto" treats every gate item as skip — SK-03' "$OB" "$LAY"
retired '\(gitignored\) ledger' '"(gitignored) ledger" — SK-06' "$OB"
retired 'bump `updatedAt`' '"bump updatedAt" with no clock — SK-09' "$IS"
retired 'trigger paid/expensive operations\*\* — use' 'production rule with no named-mutation path — SK-06' "$IS"
retired '<date>' 'a bare <date> placeholder — SK-13' "$S"/build-memory/templates/*.md "$S"/build-memory/templates/tail/*.md \
  "$S"/synthesize-spec/modes/*.md "$S"/reconcile-build/modes/*.md
retired 'reconcile it yourself' '"reconcile it yourself" — SK-05' "$OB" "$LAY"
retired 'bump `updatedAt`' '"bump updatedAt" with no clock — SK-25' "$S"/synthesize-spec/SKILL.md "$S"/synthesize-spec/modes/*.md
retired '[Nn]o merging, no CI,' '"no CI" in reconcile-build (read is in scope) — SK-24' "$S"/reconcile-build/SKILL.md "$S"/reconcile-build/modes/*.md
retired '\(forward: SK-|forward: SK-[0-9]' 'a forward reference to an applied proposal — 0.5.0 applied SK-01…SK-25' \
  "$S"/*/SKILL.md "$S"/build-memory/layout.md "$S"/build-memory/templates/*.md "$S"/build-memory/templates/tail/*.md "$S"/*/modes/*.md

# 2. Rules that must be present.
present() {   # present <fixed string> <label> <file> — matched across line wraps
  tr '\n' ' ' < "$3" | sed -E 's/[[:space:]]+/ /g' | grep -qF -- "$1" || fail "$(basename "$(dirname "$3")")/$(basename "$3") lacks $2 ('$1')"
}
present '**CI truth (BM-CI-01).**' 'the boundary CI read (SK-01)' "$OB"
present 'scripts/ci-boundary.sh' 'the ci-boundary.sh call (SK-01)' "$OB"
present '**Gate-record rules (BM-GATE-05…09' 'the gate-record rules (SK-03)' "$OB"
present 'rights, counsel, publication and acceptance items always' '"auto" pausing at human items (SK-03)' "$OB"
present '**No out-of-ticket production changes (BM-PROD-01).**' 'the orchestrator production guardrail (SK-06)' "$OB"
present '### 0.5 — The clock rule' 'the worker clock rule (SK-09)' "$IS"
tr '\n' ' ' < "$IS" | grep -qE 'set +`updatedAt` from `date -u`' || fail "implement-spec/SKILL.md lacks 'set updatedAt from date -u' (SK-09)"
present '**Read CI on the pushed code head (BM-CI-01).**' 'the after-push CI read (SK-10)' "$IS"
present '**No CI fixing outside the ticket' 'the CI non-goal (SK-10)' "$IS"
present '`Production mutations:` header names that exact mutation' 'the worker production clause (SK-06)' "$IS"
present '**Record the harness identity (BM-HARNESS-01).**' 'the harness identity and switch rule (SK-04)' "$OB"
present 'harness switch' 'the harness-switch rule (SK-04)' "$OB"
present '`repair — close:' 'repair entries instead of silent reconciliation (SK-05)' "$OB"
present 'author its contract through `decompose-spec mode=extend`' 'inserts through decompose-spec (SK-05)' "$OB"
present '`retroactive` chain row' 'retroactive rows for out-of-loop work (SK-05)' "$OB"
present '**Orient within the budget (BM-ORIENT-01).**' 'the orient byte budget (SK-07)' "$OB"
present '**Transparency (BM-DIGEST-01).**' 'the layered progress line (SK-08)' "$OB"
present 'scripts/digest.sh' 'the operator digest (SK-08)' "$OB"
present '**Stop and ask**' 'stop-and-ask (SK-08)' "$OB"
present 'Silence is never consent.' 'silence is never consent (SK-08)' "$OB"
present '| item (spec §) | required layer | achieved layer |' 'the layered gap table (SK-11)' "$IS"
present 'met-engineered(D-id)' 'the met-engineered status (SK-11)' "$IS"
present '**Invariants, not living records (BM-TEST-01).**' 'tests assert invariants (SK-12)' "$IS"
present 'never plans a living-record pin' 'the test-matrix rule (SK-12)' "$IS"
present 'check-build-memory.sh . --staged' 'the staged history check at close (SK-16)' "$IS"
present '--range <chainTip before the ticket>' 'the boundary history check (SK-16)' "$OB"
present 'A run-time insert is a scoped extend' 'scoped inserts (SK-05)' "$S/decompose-spec/SKILL.md"
present 'merge-dryrun.sh --ci' 'the PR graph reads CI (SK-24)' "$S/reconcile-build/modes/integration.md"
present 'Revisit-trigger sweep' 'the REC sweeps (SK-23)' "$S/reconcile-build/modes/backlog.md"
present 'agent-drafted, pending confirmation' 'agent-drafted answers pending confirmation (SK-25)' "$S/synthesize-spec/modes/ratify.md"
present '--planning docs/research-ledger.md' 'the planning-ledger freshness check (SK-25)' "$S/synthesize-spec/modes/run.md"
for id in BM-CI-01 BM-GATE-05 BM-GATE-06 BM-GATE-07 BM-GATE-08 BM-GATE-09 BM-PROD-01 BM-HARNESS-01 BM-ORIENT-01 BM-TEST-01 BM-DIGEST-01 BM-HIST-01; do
  grep -qE "\(${id}\)|\(${id}," "$LAY" || fail "layout.md does not define $id"
done
grep -qE '^\| BM-[A-Z]+-[0-9]+ \|' "$LAY" && fail "layout.md still lists a rule in a 'cited before their full text lands' table"
grep -qF 'Rule ids cited before their full text lands' "$LAY" && fail "layout.md still has the 'cited before their full text lands' table"

# 3. Every BM-* id the build skills cite resolves: in layout.md, or (BM-SYNTH-*, BM-RECON-*) in the
#    owning skill's mode headers.
for id in $(grep -rhoE 'BM-[A-Z]+-[0-9]+' "$OB" "$IS" "$S/decompose-spec/SKILL.md" "$S/orchestrate-build/scripts" \
              "$S/build-memory/templates" "$S/build-memory/scripts" "$S/build-memory/SKILL.md" "$S/reconcile-build" \
              "$S/synthesize-spec" | sort -u); do
  case "$id" in
    BM-SYNTH-*) grep -qE "^# .*\(${id}\)" "$S"/synthesize-spec/modes/*.md || fail "$id is cited but no synthesize-spec mode defines it" ;;
    BM-RECON-*) grep -qE "^# .*\(${id}\)" "$S"/reconcile-build/modes/*.md || fail "$id is cited but no reconcile-build mode defines it" ;;
    *) grep -qF "$id" "$LAY" || fail "$id is cited but layout.md does not define it" ;;
  esac
done

if [ "$FAIL" -eq 0 ]; then echo "lint-skills: clean"; exit 0; fi
echo "lint-skills: FAILURES above"; exit 1
